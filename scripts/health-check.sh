#!/bin/bash
# Health check script for all major deployed services

set -e

services=(
  "GitLab|http://localhost:8090/-/health"
  "SonarQube|http://localhost:9000/api/system/status"
  "Nexus|http://localhost:8081/service/rest/v1/status"
  "Jenkins|http://localhost:8084/login"
  "Grafana|http://localhost:3000/api/health"
  "Prometheus|http://localhost:9091"
  "MinIO|http://localhost:9001/minio/health/live"
  "Portainer|https://localhost:9443"
  "Vault|http://localhost:8200/v1/sys/health"
  "Traefik|http://localhost:8083/dashboard/"
  "OWASP ZAP|http://localhost:8093"
  "Webhook Receiver|http://localhost:9900"
)

# Redis is TCP only
check_redis() {
  if nc -z localhost 6379; then
    echo "✅ Redis: Healthy"
  else
    echo "❌ Redis: Unhealthy or not running"
  fi
}

# Check HTTP(S) endpoints
check_service() {
  local name="$1"
  local url="$2"
  local opts="--silent --fail --max-time 5"
  if [[ "$url" == https* ]]; then
    opts="$opts --insecure"
  fi
  if curl $opts "$url" > /dev/null; then
    echo "✅ $name: Healthy"
  else
    echo "❌ $name: Unhealthy or not running"
  fi
}

echo "=== Service Health Check ==="
for entry in "${services[@]}"; do
  IFS='|' read -r name url <<< "$entry"
  check_service "$name" "$url"
done
check_redis
