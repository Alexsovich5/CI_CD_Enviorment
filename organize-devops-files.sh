#!/bin/bash

# DevOps Files Organization Script
# Moves existing files to proper structure and creates missing placeholders

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[ORGANIZE] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Create the complete directory structure
create_directory_structure() {
    log "Creating directory structure..."
    
    directories=(
        "config/gitlab"
        "config/nginx"
        "config/prometheus"
        "config/grafana/dashboards"
        "config/grafana/provisioning/datasources"
        "config/grafana/provisioning/dashboards"
        "config/sonarqube"
        "config/nexus"
        "config/jenkins/jobs"
        "config/vault"
        "scripts"
        "templates/gitlab-ci"
        "templates/sonarqube"
        "templates/jenkins"
        "templates/docker"
        "monitoring/grafana-dashboards"
        "monitoring/prometheus-rules"
        "monitoring/alertmanager"
        "backups/daily"
        "backups/weekly"
        "backups/manual"
        "logs/gitlab"
        "logs/sonarqube"
        "logs/nexus"
        "logs/scripts"
        "data"
        "ssl"
        "webhooks"
        "docs"
        "examples/java-spring-boot"
        "examples/node-express"
        "examples/python-flask"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "$dir"
    done
    
    log "Directory structure created ✅"
}

# Move existing files to their proper locations
organize_existing_files() {
    log "Organizing existing files..."
    
    # Check and move files with proper error handling
    
    # Root level files - keep in root
    root_files=(".env" "docker-compose.yml" "docker-compose.override.yml" "Makefile" "setup.sh" "readme.md")
    for file in "${root_files[@]}"; do
        if [ -f "$file" ]; then
            info "✅ $file already in correct location"
        else
            warn "❌ $file not found - will create placeholder"
        fi
    done
    
    # Fix docker-compose filename if needed
    if [ -f "docker-composed.yml" ]; then
        log "Renaming docker-composed.yml to docker-compose.yml"
        mv "docker-composed.yml" "docker-compose.yml"
    fi
    
    # Move configuration files
    config_moves=(
        "prometheus.yml:config/prometheus/prometheus.yml"
        "hooks.json:webhooks/hooks.json"
        "sonar-project.properties:templates/sonarqube/sonar-project.properties"
    )
    
    for move in "${config_moves[@]}"; do
        source_file="${move%%:*}"
        dest_file="${move##*:}"
        
        if [ -f "$source_file" ]; then
            log "Moving $source_file → $dest_file"
            mv "$source_file" "$dest_file"
        else
            warn "$source_file not found - will create placeholder at $dest_file"
        fi
    done
    
    # Move script files
    script_moves=(
        "backup-script.sh:scripts/backup.sh"
        "restore-script.sh:scripts/restore.sh"
    )
    
    for move in "${script_moves[@]}"; do
        source_file="${move%%:*}"
        dest_file="${move##*:}"
        
        if [ -f "$source_file" ]; then
            log "Moving $source_file → $dest_file"
            mv "$source_file" "$dest_file"
            chmod +x "$dest_file"
        else
            warn "$source_file not found - will create placeholder at $dest_file"
        fi
    done
    
    # Move CI/CD template
    if [ -f ".gitlab-ci.yml" ]; then
        log "Moving .gitlab-ci.yml → templates/gitlab-ci/.gitlab-ci.yml"
        mv ".gitlab-ci.yml" "templates/gitlab-ci/.gitlab-ci.yml"
    else
        warn ".gitlab-ci.yml not found - will create placeholder"
    fi
    
    log "File organization completed ✅"
}

# Create missing placeholder files
create_missing_files() {
    log "Creating missing configuration files..."
    
    # Configuration files with content
    config_files_with_content=(
        "config/prometheus/prometheus.yml"
        "config/grafana/grafana.ini"
        "config/nginx/nginx.conf"
        "config/gitlab/gitlab.rb"
        "config/sonarqube/sonar.properties"
        "config/nexus/nexus.properties"
        "config/jenkins/jenkins.yaml"
        "config/vault/vault.hcl"
        "webhooks/hooks.json"
        "templates/gitlab-ci/.gitlab-ci.yml"
        "templates/sonarqube/sonar-project.properties"
    )
    
    # Create prometheus.yml if missing
    if [ ! -f "config/prometheus/prometheus.yml" ]; then
        log "Creating config/prometheus/prometheus.yml"
        cat > config/prometheus/prometheus.yml << 'EOF'
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

  - job_name: 'nexus'
    static_configs:
      - targets: ['nexus:8081']
    metrics_path: '/service/metrics/prometheus'
EOF
    fi
    
    # Create webhooks/hooks.json if missing
    if [ ! -f "webhooks/hooks.json" ]; then
        log "Creating webhooks/hooks.json"
        cat > webhooks/hooks.json << 'EOF'
[
  {
    "id": "sonarqube-quality-gate",
    "execute-command": "/scripts/quality-gate-handler.sh",
    "command-working-directory": "/tmp",
    "response-message": "Quality gate webhook received"
  },
  {
    "id": "gitlab-pipeline-trigger",
    "execute-command": "/scripts/pipeline-handler.sh",
    "command-working-directory": "/tmp",
    "response-message": "Pipeline webhook received"
  }
]
EOF
    fi
    
    # Create .env.example if missing
    if [ ! -f ".env.example" ]; then
        log "Creating .env.example"
        cat > .env.example << 'EOF'
# GitLab Configuration
GITLAB_ROOT_PASSWORD=change-me-to-secure-password
GITLAB_EXTERNAL_URL=http://localhost:8080

# Database Passwords
POSTGRES_PASSWORD=change-me-to-secure-password
MYSQL_ROOT_PASSWORD=change-me-to-secure-password

# MinIO Configuration
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=change-me-to-secure-password

# Vault Configuration
VAULT_DEV_ROOT_TOKEN_ID=change-me-to-secure-token

# Grafana Configuration
GF_SECURITY_ADMIN_PASSWORD=change-me-to-secure-password

# Nexus Configuration
NEXUS_ADMIN_PASSWORD=change-me-to-secure-password

# Jenkins Configuration
JENKINS_ADMIN_PASSWORD=change-me-to-secure-password

# SonarQube Configuration
SONAR_TOKEN=change-me-to-sonar-token

# Webhook Configuration
WEBHOOK_SECRET=change-me-to-webhook-secret
EOF
    fi
    
    # Create .gitignore if missing
    if [ ! -f ".gitignore" ]; then
        log "Creating .gitignore"
        cat > .gitignore << 'EOF'
# Environment and secrets
.env
.env.local
*.key
*.pem

# Data and logs (these should be in Docker volumes)
data/
logs/
backups/
volumes/

# SSL certificates
ssl/

# System files
.DS_Store
Thumbs.db

# IDE files
.vscode/
.idea/
*.swp
*.swo

# Temporary files
*.tmp
*.temp
*.log
temp/

# Docker
.docker/
EOF
    fi
    
    # Create essential script files
    script_files=(
        "scripts/backup.sh"
        "scripts/restore.sh"
        "scripts/health-check.sh"
        "scripts/cleanup.sh"
        "scripts/init-services.sh"
        "scripts/update-services.sh"
    )
    
    for script in "${script_files[@]}"; do
        if [ ! -f "$script" ]; then
            info "Creating placeholder: $script"
            cat > "$script" << 'EOF'
#!/bin/bash
# Placeholder script - add your implementation here

echo "This is a placeholder script: $(basename $0)"
echo "Add your implementation here"
EOF
            chmod +x "$script"
        fi
    done
    
    # Create webhook handler scripts
    webhook_scripts=(
        "webhooks/quality-gate-handler.sh"
        "webhooks/deployment-notifier.sh"
    )
    
    for script in "${webhook_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            info "Creating placeholder: $script"
            cat > "$script" << 'EOF'
#!/bin/bash
# Webhook handler script

echo "Webhook received: $(basename $0)"
echo "Payload: $@"
# Add your webhook handling logic here
EOF
            chmod +x "$script"
        fi
    done
    
    # Create basic config files
    basic_configs=(
        "config/grafana/grafana.ini"
        "config/nginx/nginx.conf"
        "config/gitlab/gitlab.rb"
        "config/sonarqube/sonar.properties"
        "config/nexus/nexus.properties"
        "config/jenkins/jenkins.yaml"
        "config/vault/vault.hcl"
    )
    
    for config in "${basic_configs[@]}"; do
        if [ ! -f "$config" ]; then
            info "Creating placeholder: $config"
            echo "# Configuration file for $(basename $(dirname $config))" > "$config"
            echo "# Add your configuration here" >> "$config"
        fi
    done
    
    # Create template files if missing
    if [ ! -f "templates/gitlab-ci/.gitlab-ci.yml" ]; then
        info "Creating placeholder CI/CD template"
        cat > templates/gitlab-ci/.gitlab-ci.yml << 'EOF'
# GitLab CI/CD Template
stages:
  - build
  - test
  - deploy

variables:
  DOCKER_REGISTRY: "localhost:5050"

build:
  stage: build
  script:
    - echo "Add your build commands here"

test:
  stage: test
  script:
    - echo "Add your test commands here"

deploy:
  stage: deploy
  script:
    - echo "Add your deployment commands here"
EOF
    fi
    
    if [ ! -f "templates/sonarqube/sonar-project.properties" ]; then
        info "Creating SonarQube project template"
        cat > templates/sonarqube/sonar-project.properties << 'EOF'
# SonarQube Project Configuration Template
sonar.projectKey=your-project-key
sonar.projectName=Your Project Name
sonar.projectVersion=1.0

# Source code location
sonar.sources=src
sonar.tests=src/test

# Language-specific settings (adjust as needed)
sonar.java.source=11
sonar.java.target=11

# Exclusions
sonar.exclusions=**/*test*/**,**/node_modules/**
sonar.test.exclusions=src/test/**

# Quality gate settings
sonar.qualitygate.wait=true
EOF
    fi
    
    # Create documentation files
    doc_files=(
        "docs/setup-guide.md"
        "docs/troubleshooting.md"
        "docs/api-documentation.md"
        "docs/backup-recovery.md"
    )
    
    for doc in "${doc_files[@]}"; do
        if [ ! -f "$doc" ]; then
            info "Creating documentation: $doc"
            title=$(basename "$doc" .md | tr '-' ' ' | sed 's/\b\w/\u&/g')
            cat > "$doc" << EOF
# $title

## Overview

This document provides information about $(echo $title | tr '[:upper:]' '[:lower:]').

## Contents

- Add your content here
- Include relevant sections
- Provide examples and instructions

## Next Steps

- Review and update this documentation
- Add specific information for your use case
EOF
        fi
    done
    
    # Create example project files
    example_projects=("java-spring-boot" "node-express" "python-flask")
    
    for project in "${example_projects[@]}"; do
        project_dir="examples/$project"
        
        # Create .gitlab-ci.yml for each example
        if [ ! -f "$project_dir/.gitlab-ci.yml" ]; then
            info "Creating example CI/CD for $project"
            cat > "$project_dir/.gitlab-ci.yml" << EOF
# $project CI/CD Pipeline Example
stages:
  - build
  - test
  - quality
  - deploy

variables:
  DOCKER_REGISTRY: "localhost:5050"

build_$project:
  stage: build
  script:
    - echo "Building $project application"
    # Add build commands specific to $project

test_$project:
  stage: test
  script:
    - echo "Testing $project application"
    # Add test commands specific to $project

quality_check:
  stage: quality
  image: sonarsource/sonar-scanner-cli:latest
  script:
    - sonar-scanner
  only:
    - main
    - develop

deploy_$project:
  stage: deploy
  script:
    - echo "Deploying $project application"
    # Add deployment commands
  only:
    - main
EOF
        fi
        
        # Create sonar-project.properties for each example
        if [ ! -f "$project_dir/sonar-project.properties" ]; then
            info "Creating SonarQube config for $project"
            cat > "$project_dir/sonar-project.properties" << EOF
# SonarQube configuration for $project
sonar.projectKey=$project-example
sonar.projectName=$project Example Project
sonar.projectVersion=1.0

sonar.sources=src
sonar.tests=src/test

# Add language-specific settings for $project
EOF
        fi
        
        # Create basic Dockerfile for each example
        if [ ! -f "$project_dir/Dockerfile" ]; then
            info "Creating Dockerfile for $project"
            cat > "$project_dir/Dockerfile" << EOF
# Dockerfile for $project example
# Add appropriate base image and build steps for $project

FROM alpine:latest
RUN echo "Add build steps for $project here"
EXPOSE 8080
CMD ["echo", "Start command for $project"]
EOF
        fi
    done
    
    log "Missing files created ✅"
}

# Set proper file permissions
set_permissions() {
    log "Setting proper file permissions..."
    
    # Make scripts executable
    find scripts/ -name "*.sh" -exec chmod +x {} \;
    find webhooks/ -name "*.sh" -exec chmod +x {} \;
    chmod +x setup.sh 2>/dev/null || true
    
    # Secure environment files
    chmod 600 .env 2>/dev/null || true
    chmod 644 .env.example 2>/dev/null || true
    
    # Make sure config files are readable
    find config/ -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    log "File permissions set ✅"
}

# Create a summary of the organization
create_summary() {
    log "Creating organization summary..."
    
    cat > ORGANIZATION_SUMMARY.md << 'EOF'
# DevOps Stack File Organization Summary

## Directory Structure Created

```
devops-stack/
├── 📄 docker-compose.yml              # Main Docker Compose configuration
├── 📄 docker-compose.override.yml     # Development overrides
├── 📄 .env                           # Environment variables (secure)
├── 📄 .env.example                   # Environment template
├── 📄 .gitignore                     # Git ignore rules
├── 📄 Makefile                       # Automation commands
├── 📄 setup.sh                       # Setup and management script
├── 📄 readme.md                      # Project documentation
│
├── 📂 config/                        # Service configurations
│   ├── 📂 gitlab/                    # GitLab configuration
│   ├── 📂 nginx/                     # Nginx configuration
│   ├── 📂 prometheus/                # Prometheus configuration
│   ├── 📂 grafana/                   # Grafana configuration
│   ├── 📂 sonarqube/                 # SonarQube configuration
│   ├── 📂 nexus/                     # Nexus configuration
│   ├── 📂 jenkins/                   # Jenkins configuration
│   └── 📂 vault/                     # Vault configuration
│
├── 📂 scripts/                       # Automation scripts
│   ├── 📄 backup.sh                  # Backup script
│   ├── 📄 restore.sh                 # Restore script
│   ├── 📄 health-check.sh            # Health monitoring
│   ├── 📄 cleanup.sh                 # Cleanup script
│   ├── 📄 init-services.sh           # Service initialization
│   └── 📄 update-services.sh         # Service updates
│
├── 📂 templates/                     # Project templates
│   ├── 📂 gitlab-ci/                 # CI/CD templates
│   ├── 📂 sonarqube/                 # SonarQube templates
│   ├── 📂 jenkins/                   # Jenkins templates
│   └── 📂 docker/                    # Dockerfile templates
│
├── 📂 monitoring/                    # Monitoring configurations
│   ├── 📂 grafana-dashboards/        # Grafana dashboards
│   ├── 📂 prometheus-rules/          # Prometheus alert rules
│   └── 📂 alertmanager/              # Alert manager config
│
├── 📂 webhooks/                      # Webhook configurations
│   ├── 📄 hooks.json                 # Webhook definitions
│   ├── 📄 quality-gate-handler.sh    # SonarQube webhook handler
│   └── 📄 deployment-notifier.sh     # Deployment notifications
│
├── 📂 docs/                          # Documentation
│   ├── 📄 setup-guide.md             # Setup instructions
│   ├── 📄 troubleshooting.md         # Troubleshooting guide
│   ├── 📄 api-documentation.md       # API documentation
│   └── 📄 backup-recovery.md         # Backup procedures
│
├── 📂 examples/                      # Example projects
│   ├── 📂 java-spring-boot/          # Java example
│   ├── 📂 node-express/              # Node.js example
│   └── 📂 python-flask/              # Python example
│
├── 📂 backups/                       # Backup storage (gitignored)
├── 📂 logs/                          # Log files (gitignored)
├── 📂 data/                          # Persistent data (gitignored)
└── 📂 ssl/                           # SSL certificates (gitignored)
```

## File Movements Performed

- `prometheus.yml` → `config/prometheus/prometheus.yml`
- `hooks.json` → `webhooks/hooks.json`
- `sonar-project.properties` → `templates/sonarqube/sonar-project.properties`
- `backup-script.sh` → `scripts/backup.sh`
- `restore-script.sh` → `scripts/restore.sh`
- `.gitlab-ci.yml` → `templates/gitlab-ci/.gitlab-ci.yml`
- `docker-composed.yml` → `docker-compose.yml` (fixed filename)

## Next Steps

1. **Review Configuration**: Check all files in `config/` directory
2. **Customize Templates**: Update templates in `templates/` directory
3. **Set Environment Variables**: Copy `.env.example` to `.env` and customize
4. **Test Setup**: Run `./setup.sh check` to verify prerequisites
5. **Start Services**: Use `make start-core` to begin

## Security Notes

- `.env` file contains sensitive data and is gitignored
- All script files have been made executable
- SSL directory is prepared for certificates (gitignored)
- Backup directory is gitignored to prevent accidental commits

## Quick Commands

```bash
# Check system prerequisites
./setup.sh check

# Start core services
make start-core

# Check service health  
make health

# Create backup
make backup

# View all available commands
make help
```
EOF
    
    log "Organization summary created: ORGANIZATION_SUMMARY.md ✅"
}

# Main execution
main() {
    echo "🚀 DevOps Stack File Organization Script"
    echo "========================================"
    echo
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ] && [ ! -f "docker-composed.yml" ]; then
        error "No docker-compose.yml found. Are you in the right directory?"
        exit 1
    fi
    
    # Execute organization steps
    create_directory_structure
    organize_existing_files
    create_missing_files
    set_permissions
    create_summary
    
    echo
    log "🎉 File organization completed successfully!"
    echo
    info "📋 Summary:"
    echo "   • Directory structure created"
    echo "   • Existing files moved to proper locations"  
    echo "   • Missing configuration files created"
    echo "   • File permissions set correctly"
    echo "   • Organization summary created"
    echo
    info "📖 Next steps:"
    echo "   1. Review ORGANIZATION_SUMMARY.md"
    echo "   2. Copy .env.example to .env and customize"
    echo "   3. Run: ./setup.sh check"
    echo "   4. Run: make start-core"
    echo
    warn "⚠️  Remember to:"
    echo "   • Never commit .env to version control"
    echo "   • Review and customize configuration files"
    echo "   • Update templates for your specific needs"
    echo
}

# Run the main function
main "$@"