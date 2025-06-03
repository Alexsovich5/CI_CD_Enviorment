#!/bin/bash
# Service initialization script for DevOps stack

set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check if .env file exists
if [ ! -f .env ]; then
    log "WARNING: .env file not found. Using defaults from docker-compose.yml"
    log "Consider copying .env.example to .env and setting secure passwords"
fi

# Start core services first
log "Starting core services..."
docker-compose up -d sonarqube_db redis

# Wait for database to be ready
log "Waiting for database to be ready..."
sleep 30

# Start main services
log "Starting main services..."
docker-compose up -d gitlab sonarqube nexus jenkins

# Start monitoring services
log "Starting monitoring services..."
docker-compose up -d grafana prometheus

# Start utility services
log "Starting utility services..."
docker-compose up -d portainer traefik vault minio

log "All services started. Run health check to verify status."
