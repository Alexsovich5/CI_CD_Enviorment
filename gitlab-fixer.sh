#!/bin/bash

# GitLab Startup Fixer Script
# Handles the common socket connection refused error

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[GITLAB] $1${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

# Check if GitLab is having socket issues
check_gitlab_socket_error() {
    local logs=$(docker-compose logs --tail=20 gitlab 2>/dev/null | grep -i "connection refused\|socket\|badgateway" || true)
    if [ -n "$logs" ]; then
        return 0  # Has socket error
    else
        return 1  # No socket error
    fi
}

# Wait for GitLab with progress indicator
wait_for_gitlab() {
    local max_wait=${1:-900}  # Default 15 minutes
    local count=0
    local dot_count=0
    
    log "Waiting for GitLab to fully start (max ${max_wait}s)..."
    
    while [ $count -lt $max_wait ]; do
        # Check if GitLab is responding
        if curl -f -s http://localhost:8080/-/health >/dev/null 2>&1; then
            echo
            log "✅ GitLab is now healthy and responding!"
            return 0
        fi
        
        # Show progress dots
        printf "."
        dot_count=$((dot_count + 1))
        if [ $dot_count -eq 60 ]; then
            echo " (${count}s)"
            dot_count=0
        fi
        
        sleep 1
        count=$((count + 1))
    done
    
    echo
    warn "GitLab didn't respond within ${max_wait}s"
    return 1
}

# Monitor GitLab startup logs
monitor_startup() {
    log "Monitoring GitLab startup logs..."
    
    # Start log monitoring in background
    docker-compose logs -f gitlab 2>&1 | while read line; do
        echo "$line" | grep -E "(Configuring|Starting|ready|Reconfigured|ERROR|FATAL)" || true
    done &
    
    local monitor_pid=$!
    
    # Wait for GitLab or timeout
    if wait_for_gitlab 600; then
        kill $monitor_pid 2>/dev/null || true
        return 0
    else
        kill $monitor_pid 2>/dev/null || true
        return 1
    fi
}

# Check system resources
check_resources() {
    log "Checking system resources..."
    
    # Check memory
    local total_mem=$(free -m | grep Mem | awk '{print $2}')
    local available_mem=$(free -m | grep Mem | awk '{print $7}')
    
    if [ $available_mem -lt 2048 ]; then
        warn "Low memory available: ${available_mem}MB (recommended: 4GB+)"
    else
        info "Memory looks good: ${available_mem}MB available"
    fi
    
    # Check disk space
    local disk_free=$(df . | tail -1 | awk '{print $4}')
    local disk_free_gb=$((disk_free / 1024 / 1024))
    
    if [ $disk_free_gb -lt 10 ]; then
        warn "Low disk space: ${disk_free_gb}GB free (recommended: 50GB+)"
    else
        info "Disk space looks good: ${disk_free_gb}GB free"
    fi
    
    # Check Docker memory limit
    local docker_mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
    local docker_mem_gb=$((docker_mem / 1024 / 1024 / 1024))
    
    if [ $docker_mem_gb -lt 4 ]; then
        warn "Docker memory limit: ${docker_mem_gb}GB (recommended: 8GB+)"
        warn "Increase in Docker Desktop: Preferences → Resources → Memory"
    else
        info "Docker memory limit looks good: ${docker_mem_gb}GB"
    fi
}

# Quick diagnostic
quick_diagnostic() {
    log "Running GitLab diagnostic..."
    
    # Container status
    info "Container status:"
    docker-compose ps gitlab
    echo
    
    # Resource usage
    info "Resource usage:"
    docker stats gitlab-ce --no-stream 2>/dev/null || echo "Container not running"
    echo
    
    # Port check
    info "Port availability:"
    if lsof -i :8080 >/dev/null 2>&1; then
        info "Port 8080: In use ✅"
    else
        warn "Port 8080: Not in use ❌"
    fi
    
    # Health check
    info "Health check:"
    if curl -f -s http://localhost:8080/-/health >/dev/null 2>&1; then
        info "GitLab health: OK ✅"
    else
        warn "GitLab health: Not responding ❌"
    fi
    
    # Internal services (if accessible)
    info "Internal services:"
    docker-compose exec gitlab gitlab-ctl status 2>/dev/null | head -10 || warn "Cannot access internal services yet"
}

# Fix socket error
fix_socket_error() {
    log "Attempting to fix GitLab socket error..."
    
    # Method 1: Restart unicorn service
    info "Trying to restart unicorn service..."
    if docker-compose exec gitlab gitlab-ctl restart unicorn 2>/dev/null; then
        log "Unicorn restarted, waiting for response..."
        if wait_for_gitlab 120; then
            return 0
        fi
    fi
    
    # Method 2: Full reconfigure
    info "Trying GitLab reconfigure..."
    if docker-compose exec gitlab gitlab-ctl reconfigure 2>/dev/null; then
        log "Reconfigure completed, waiting for response..."
        if wait_for_gitlab 180; then
            return 0
        fi
    fi
    
    # Method 3: Container restart
    info "Trying container restart..."
    docker-compose restart gitlab
    if wait_for_gitlab 300; then
        return 0
    fi
    
    return 1
}

# Nuclear option - complete reset
nuclear_reset() {
    warn "⚠️  NUCLEAR RESET - This will restart GitLab from scratch (data preserved)"
    echo "Are you sure? This will:"
    echo "- Stop GitLab container"
    echo "- Remove container (keeping data volumes)"
    echo "- Clean Docker system"
    echo "- Start fresh GitLab container"
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Reset cancelled"
        return 1
    fi
    
    log "Starting nuclear reset..."
    
    # Stop everything
    docker-compose stop gitlab
    
    # Remove container (keeps volumes)
    docker-compose rm -f gitlab
    
    # Clean up
    docker system prune -f
    
    # Wait a moment
    sleep 5
    
    # Start fresh
    log "Starting fresh GitLab container..."
    docker-compose up -d gitlab
    
    # Monitor startup
    monitor_startup
}

# Get GitLab credentials
get_credentials() {
    log "Retrieving GitLab credentials..."
    
    echo "GitLab Access Information:"
    echo "========================"
    echo "URL: http://localhost:8080"
    echo "Username: root"
    echo -n "Password: "
    
    if docker-compose exec gitlab test -f /etc/gitlab/initial_root_password 2>/dev/null; then
        docker-compose exec gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | cut -d' ' -f2
    else
        echo "Not available yet (GitLab still starting)"
    fi
    echo
}

# Show usage
usage() {
    echo "GitLab Startup Fixer"
    echo "==================="
    echo
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  check       - Check GitLab status and resources"
    echo "  wait        - Wait for GitLab to start (with progress)"
    echo "  fix         - Attempt to fix socket errors"
    echo "  reset       - Nuclear reset (keeps data)"
    echo "  logs        - Show GitLab logs"
    echo "  monitor     - Monitor startup process"
    echo "  password    - Get GitLab root password"
    echo "  help        - Show this help"
    echo
    echo "Examples:"
    echo "  $0 check          # Quick diagnostic"
    echo "  $0 wait           # Wait for startup"
    echo "  $0 fix            # Fix socket errors"
    echo
}

# Main function
main() {
    case "${1:-help}" in
        "check")
            check_resources
            echo
            quick_diagnostic
            ;;
        
        "wait")
            if wait_for_gitlab; then
                get_credentials
            else
                error "GitLab failed to start properly"
                echo "Try: $0 fix"
            fi
            ;;
        
        "fix")
            if check_gitlab_socket_error; then
                log "Socket error detected, attempting fix..."
                if fix_socket_error; then
                    log "✅ Socket error fixed!"
                    get_credentials
                else
                    error "Could not fix socket error automatically"
                    echo "Try: $0 reset"
                fi
            else
                info "No socket errors detected"
                quick_diagnostic
            fi
            ;;
        
        "reset")
            nuclear_reset
            ;;
        
        "logs")
            log "Showing GitLab logs (Ctrl+C to exit)..."
            docker-compose logs -f gitlab
            ;;
        
        "monitor")
            monitor_startup
            ;;
        
        "password")
            get_credentials
            ;;
        
        "help"|*)
            usage
            ;;
    esac
}

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    error "docker-compose.yml not found. Are you in the right directory?"
    exit 1
fi

# Run main function
main "$@"
