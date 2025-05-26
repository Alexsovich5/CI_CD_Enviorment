#!/bin/bash

# Backup script for database and volumes
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/${DATE}"

# Create backup directory
mkdir -p ${BACKUP_DIR}

# Backup PostgreSQL (SonarQube)
echo "Backing up SonarQube database..."
pg_dump -h sonarqube_db -U sonar sonarqube > ${BACKUP_DIR}/sonarqube_backup.sql

# Backup GitLab
echo "Creating GitLab backup..."
docker-compose exec gitlab gitlab-backup create BACKUP=${DATE}

# Backup Nexus data
echo "Backing up Nexus data..."
tar -czf ${BACKUP_DIR}/nexus_backup.tar.gz -C /nexus-data .

# Backup Vault data
echo "Backing up Vault data..."
tar -czf ${BACKUP_DIR}/vault_backup.tar.gz -C /vault/data .

# Cleanup old backups (keep last 7 days)
find /backups -type d -mtime +7 -exec rm -rf {} \;

echo "Backup completed: ${BACKUP_DIR}"
# Notify user