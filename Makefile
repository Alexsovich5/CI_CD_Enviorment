.PHONY: help start stop restart logs backup restore clean

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: ## Start all services
	docker-compose up -d

start-core: ## Start only core services (GitLab, SonarQube, Nexus)
	docker-compose up -d gitlab sonarqube nexus

start-monitoring: ## Start with monitoring profile
	docker-compose --profile monitoring up -d

start-security: ## Start with security profile
	docker-compose --profile security up -d

start-all: ## Start all services including optional profiles
	docker-compose --profile monitoring --profile security --profile webhooks --profile backup up -d

stop: ## Stop all services
	docker-compose down

restart: ## Restart all services
	docker-compose restart

logs: ## Show logs for all services
	docker-compose logs -f

logs-gitlab: ## Show GitLab logs
	docker-compose logs -f gitlab

logs-sonar: ## Show SonarQube logs
	docker-compose logs -f sonarqube

status: ## Show service status
	docker-compose ps

backup: ## Create backup of all data
	docker-compose exec backup /backup-script.sh

restore: ## Restore from backup (specify BACKUP_DATE=YYYYMMDD_HHMMSS)
	@if [ -z "$(BACKUP_DATE)" ]; then echo "Please specify BACKUP_DATE=YYYYMMDD_HHMMSS"; exit 1; fi
	docker-compose exec backup /restore-script.sh $(BACKUP_DATE)

clean: ## Remove all containers and volumes (DESTRUCTIVE)
	docker-compose down -v
	docker system prune -f

clean-soft: ## Remove containers but keep volumes
	docker-compose down

update: ## Pull latest images and restart
	docker-compose pull
	docker-compose up -d

health: ## Check health of all services
	@echo "=== Service Health Check ==="
	@curl -f http://localhost:8080/-/health && echo "✅ GitLab: Healthy" || echo "❌ GitLab: Unhealthy"
	@curl -f http://localhost:9000/api/system/status && echo "✅ SonarQube: Healthy" || echo "❌ SonarQube: Unhealthy"
	@curl -f http://localhost:8081/service/rest/v1/status && echo "✅ Nexus: Healthy" || echo "❌ Nexus: Unhealthy"
	@curl -f http://localhost:8082/login && echo "✅ Jenkins: Healthy" || echo "❌ Jenkins: Unhealthy"
	@curl -f http://localhost:3000/api/health && echo "✅ Grafana: Healthy" || echo "❌ Grafana: Unhealthy"

setup: ## Initial setup after first start
	@echo "🚀 Setting up DevOps stack..."
	@echo "1. Waiting for services to start..."
	@sleep 30
	@echo "2. Getting GitLab root password..."
	@docker-compose exec gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null || echo "GitLab not ready yet"
	@echo "3. Getting Jenkins admin password..."
	@docker-compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "Jenkins not ready yet"
	@echo "4. Service URLs:"
	@echo "   GitLab:     http://localhost:8080"
	@echo "   SonarQube:  http://localhost:9000 (admin/admin)"
	@echo "   Nexus:      http://localhost:8081 (admin/admin123)"
	@echo "   Jenkins:    http://localhost:8082"
	@echo "   Grafana:    http://localhost:3000 (admin/admin123)"
	@echo "   Portainer:  https://localhost:9443"
	@echo "   MinIO:      http://localhost:9002 (minioadmin/minioadmin123)"
	@echo "   Vault:      http://localhost:8200 (token: dev-root-token)"