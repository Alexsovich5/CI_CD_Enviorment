#!/bin/bash

if [ $# -eq 0 ]; then
    echo "Usage: $0 <backup_date>"
    echo "Example: $0 20241201_143000"
    exit 1
fi

BACKUP_DATE=$1
BACKUP_DIR="/backups/${BACKUP_DATE}"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Backup directory $BACKUP_DIR does not exist"
    exit 1
fi

echo "Restoring from backup: $BACKUP_DATE"

# Stop services before restore
echo "Stopping services..."
docker-compose stop sonarqube nexus vault

# Restore SonarQube database
if [ -f "$BACKUP_DIR/sonarqube_backup.sql" ]; then
    echo "Restoring SonarQube database..."
    psql -h sonarqube_db -U sonar sonarqube < $BACKUP_DIR/sonarqube_backup.sql
fi

# Restore Nexus data
if [ -f "$BACKUP_DIR/nexus_backup.tar.gz" ]; then
    echo "Restoring Nexus data..."
    tar -xzf $BACKUP_DIR/nexus_backup.tar.gz -C /nexus-data
fi

# Restore Vault data
if [ -f "$BACKUP_DIR/vault_backup.tar.gz" ]; then
    echo "Restoring Vault data..."
    tar -xzf $BACKUP_DIR/vault_backup.tar.gz -C /vault/data
fi

# Restore GitLab backup
GITLAB_BACKUP_FILE=$(ls $BACKUP_DIR/*_gitlab_backup.tar 2>/dev/null | head -1)
if [ -f "$GITLAB_BACKUP_FILE" ]; then
    echo "Restoring GitLab backup..."
    BACKUP_NAME=$(basename $GITLAB_BACKUP_FILE _gitlab_backup.tar)
    docker cp $GITLAB_BACKUP_FILE gitlab-ce:/var/opt/gitlab/backups/
    docker-compose exec gitlab gitlab-backup restore BACKUP=$BACKUP_NAME
fi

echo "Starting services..."
docker-compose start sonarqube nexus vault

echo "Restore completed from: $BACKUP_DIR"