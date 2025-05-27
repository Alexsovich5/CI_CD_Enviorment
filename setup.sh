#!/bin/bash

# DevOps Stack Setup and Management Script
# For Solo Developer CI/CD Pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STACK_NAME="devops-stack"
REQUIRED_MEMORY_GB=8
REQUIRED_DISK_GB=50

# Helper functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Detect OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS_TYPE="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
    else
        OS_TYPE="unknown"
    fi
    
    info "Detected OS: $OS_TYPE"
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        if [[ "$OS_TYPE" == "linux" ]]; then
            error "Docker is not installed. Please install Docker Engine for Linux."
        else
            error "Docker is not installed. Please install Docker Desktop for Mac."
        fi
    fi
    
    if ! docker info &> /dev/null; then
        if [[ "$OS_TYPE" == "linux" ]]; then
            error "Docker is not running. Please start Docker service: sudo systemctl start docker"
        else
            error "Docker is not running. Please start Docker Desktop."
        fi
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        if [[ "$OS_TYPE" == "linux" ]]; then
            error "docker-compose is not installed. Please install docker-compose or use 'docker compose' plugin."
        else
            error "docker-compose is not installed or not in PATH."
        fi
    fi
    
    # Check Docker memory allocation
    DOCKER_MEMORY=$(docker system info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    DOCKER_MEMORY_GB=$((DOCKER_MEMORY / 1024 / 1024 / 1024))
    
    if [ $DOCKER_MEMORY_GB -lt $REQUIRED_MEMORY_GB ]; then
        warn "Docker has only ${DOCKER_MEMORY_GB}GB allocated. Recommended: ${REQUIRED_MEMORY_GB}GB+"
        if [[ "$OS_TYPE" == "linux" ]]; then
            warn "On Linux, Docker uses host memory directly. Ensure your system has enough RAM."
        else
            warn "Increase Docker Desktop memory allocation in Preferences -> Resources"
        fi
    fi
    
    # Check available disk space
    if [[ "$OS_TYPE" == "linux" ]]; then
        # Linux - use df with human readable and convert to GB
        AVAILABLE_SPACE=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    elif [[ "$OS_TYPE" == "macos" ]]; then
        # macOS
        AVAILABLE_SPACE=$(df -g . | awk 'NR==2 {print $4}')
    else
        # Fallback
        AVAILABLE_SPACE=$(df -h . | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
    if [ "$AVAILABLE_SPACE" -lt $REQUIRED_DISK_GB ]; then
        warn "Only ${AVAILABLE_SPACE}GB disk space available. Recommended: ${REQUIRED_DISK_GB}GB+"
    fi
    
    # Check if user has proper permissions (Linux specific)
    if [[ "$OS_TYPE" == "linux" ]]; then
        if ! docker info &> /dev/null; then
            warn "You may need to add your user to the docker group: sudo usermod -aG docker \$USER"
            warn "Then log out and back in, or run: newgrp docker"
        fi
    fi
    
    log "Prerequisites check completed ✅"
}

# Initialize project structure
init_project() {
    log "Initializing project structure..."
    
    # Create necessary directories
    mkdir -p logs backups config/nginx config/prometheus config/grafana scripts
    
    # Create prometheus.yml if it doesn't exist
    if [ ! -f "prometheus.yml" ]; then
        log "Creating prometheus.yml configuration..."
        cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'gitlab'
    static_configs:
      - targets: ['gitlab:80']
    metrics_path: '/-/metrics'

  - job_name: 'sonarqube'
    static_configs:
      - targets: ['sonarqube:9000']
    metrics_path: '/api/monitoring/metrics'
EOF
    fi
    
    # Create hooks.json for webhooks
    if [ ! -f "hooks.json" ]; then
        log "Creating webhook configuration..."
        cat > hooks.json << 'EOF'
[
  {
    "id": "gitlab-pipeline",
    "execute-command": "/bin/echo",
    "command-working-directory": "/tmp",
    "response-message": "Pipeline webhook received"
  }
]
EOF
    fi
    
    # Create backup script
    if [ ! -f "scripts/backup.sh" ]; then
        log "Creating backup script..."
        cat > scripts/backup.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups/${DATE}"
mkdir -p ${BACKUP_DIR}

echo "Creating backup: ${DATE}"

# Backup databases
docker-compose exec -T sonarqube_db pg_dump -U sonar sonarqube > ${BACKUP_DIR}/sonarqube_backup.sql

# Create GitLab backup
docker-compose exec -T gitlab gitlab-backup create BACKUP=${DATE}

# Copy GitLab backup to host
docker cp gitlab-ce:/var/opt/gitlab/backups/${DATE}_gitlab_backup.tar ${BACKUP_DIR}/

echo "Backup completed: ${BACKUP_DIR}"
EOF
        chmod +x scripts/backup.sh
    fi
    
    log "Project structure initialized ✅"
}

# Start services
start_services() {
    local profile=${1:-core}
    
    log "Starting services with profile: $profile"
    
    case $profile in
        "core")
            docker-compose up -d gitlab sonarqube sonarqube_db nexus redis
            ;;
        "monitoring")
            docker-compose --profile monitoring up -d
            ;;
        "security")
            docker-compose --profile security up -d
            ;;
        "full")
            docker-compose --profile monitoring --profile security up -d
            ;;
        *)
            docker-compose up -d
            ;;
    esac
    
    log "Services starting... This may take a few minutes."
    
    # Wait for core services to be healthy
    wait_for_services
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    
    local max_attempts=60
    local attempt=1
    
    services=("gitlab:8080/-/health" "sonarqube:9000/api/system/status" "nexus:8081/service/rest/v1/status")
    
    for service in "${services[@]}"; do
        IFS=':' read -r container port_path <<< "$service"
        local url="http://localhost:${port_path}"
        
        info "Waiting for $container to be ready..."
        
        while [ $attempt -le $max_attempts ]; do
            if curl -sf "$url" >/dev/null 2>&1; then
                log "$container is ready ✅"
                break
            fi
            
            if [ $attempt -eq $max_attempts ]; then
                warn "$container may not be ready yet. Check logs: docker-compose logs $container"
                break
            fi
            
            sleep 10
            ((attempt++))
        done
        attempt=1
    done
}

# Get initial passwords and tokens
get_credentials() {
    log "Retrieving initial credentials..."
    
    echo
    echo "=== 🔐 INITIAL CREDENTIALS ==="
    echo
    
    # GitLab root password
    echo "GitLab (http://localhost:8080):"
    echo "  Username: root"
    echo -n "  Password: "
    docker-compose exec gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | cut -d' ' -f2 || echo "Not ready yet"
    echo
    
    # SonarQube
    echo "SonarQube (http://localhost:9000):"
    echo "  Username: admin"
    echo "  Password: admin (change on first login)"
    echo
    
    # Nexus
    echo "Nexus (http://localhost:8081):"
    echo "  Username: admin"
    echo -n "  Password: "
    docker-compose exec nexus cat /nexus-data/admin.password 2>/dev/null || echo "admin123 (default)"
    echo
    
    # Jenkins (if running)
    if docker-compose ps jenkins | grep -q "Up"; then
        echo "Jenkins (http://localhost:8082):"
        echo "  Username: admin"
        echo -n "  Password: "
        docker-compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Not ready yet"
        echo
    fi
    
    # Other services
    echo "Grafana (http://localhost:3000): admin/admin123"
    echo "MinIO (http://localhost:9002): minioadmin/minioadmin123"
    echo "Vault (http://localhost:8200): Token: dev-root-token"
    echo "Portainer (http://localhost:9443): Create admin user on first visit"
    echo
}

# Health check
health_check() {
    log "Performing health check..."
    
    local services=(
        "GitLab:8080/-/health"
        "SonarQube:9000/api/system/status"
        "Nexus:8081/service/rest/v1/status"
        "Grafana:3000/api/health"
        "Jenkins:8082/login"
    )
    
    echo
    echo "=== 🏥 HEALTH CHECK ==="
    echo
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port_path <<< "$service"
        local url="http://localhost:${port_path}"
        
        if curl -sf "$url" >/dev/null 2>&1; then
            echo "✅ $name: Healthy"
        else
            echo "❌ $name: Unhealthy or not running"
        fi
    done
    echo
}

# Show resource usage
show_resources() {
    log "Showing resource usage..."
    
    echo
    echo "=== 📊 RESOURCE USAGE ==="
    echo
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
    echo
}

# Backup function
backup() {
    log "Creating backup..."
    
    if [ -f "scripts/backup.sh" ]; then
        ./scripts/backup.sh
    else
        error "Backup script not found. Run 'init' first."
    fi
}

# Stop services
stop_services() {
    log "Stopping all services..."
    docker-compose down
    log "All services stopped ✅"
}

# Clean up everything
cleanup() {
    warn "This will remove all containers and volumes. Are you sure? (y/N)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        log "Cleaning up everything..."
        docker-compose down -v
        docker system prune -f
        log "Cleanup completed ✅"
    else
        log "Cleanup cancelled"
    fi
}

# Show usage
usage() {
    echo "DevOps Stack Management Script"
    echo
    echo "Usage: $0 [command] [options]"
    echo
    echo "Commands:"
    echo "  init                 Initialize project structure"
    echo "  check               Check prerequisites"
    echo "  start [profile]     Start services (core|monitoring|security|full)"
    echo "  stop                Stop all services"
    echo "  restart             Restart all services"
    echo "  status              Show service status"
    echo "  health              Perform health check"
    echo "  credentials         Show initial credentials"
    echo "  resources           Show resource usage"
    echo "  logs [service]      Show logs for all or specific service"
    echo "  backup              Create backup"
    echo "  cleanup             Remove all containers and volumes"
    echo "  help                Show this help message"
    echo
    echo "Examples:"
    echo "  $0 init             # Initialize project"
    echo "  $0 start core       # Start core services only"
    echo "  $0 start full       # Start all services"
    echo "  $0 logs gitlab      # Show GitLab logs"
    echo
}

# Main script logic
main() {
    case "${1:-help}" in
        "init")
            check_prerequisites
            init_project
            ;;
        "check")
            check_prerequisites
            ;;
        "start")
            check_prerequisites
            start_services "${2:-core}"
            sleep 30  # Give services time to start
            get_credentials
            ;;
        "stop")
            stop_services
            ;;
        "restart")
            stop_services
            start_services "${2:-core}"
            ;;
        "status")
            docker-compose ps
            ;;
        "health")
            health_check
            ;;
        "credentials")
            get_credentials
            ;;
        "resources")
            show_resources
            ;;
        "logs")
            if [ -n "$2" ]; then
                docker-compose logs -f "$2"
            else
                docker-compose logs -f
            fi
            ;;
        "backup")
            backup
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|*)
            usage
            ;;
    esac
}

# Run main function with all arguments
main "$@"