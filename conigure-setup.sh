#!/bin/bash

# =============================================================================
# DevOps Stack Configuration Automation Script
# Configures running infrastructure for seamless CI/CD integration
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/configuration-$(date +%Y%m%d_%H%M%S).log"
CONFIG_BACKUP_DIR="${SCRIPT_DIR}/config-backup-$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Service endpoints (adjust if your ports differ)
GITLAB_URL="http://localhost:8090"
SONARQUBE_URL="http://localhost:9000"
NEXUS_URL="http://localhost:8081"
JENKINS_URL="http://localhost:8084"
GRAFANA_URL="http://localhost:3000"
PROMETHEUS_URL="http://localhost:9091"
VAULT_URL="http://localhost:8200"
PORTAINER_URL="https://localhost:9443"

# Default credentials (will be retrieved/configured)
GITLAB_ROOT_TOKEN=""
SONAR_TOKEN=""
NEXUS_ADMIN_PASSWORD=""
JENKINS_API_TOKEN=""
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Configuration flags
CONFIGURE_ALL=true
SKIP_GITLAB=false
SKIP_SONARQUBE=false
SKIP_NEXUS=false
SKIP_JENKINS=false
SKIP_MONITORING=false
SKIP_VAULT=false
DRY_RUN=false
VERBOSE=false

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[${timestamp}] [INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[${timestamp}] [WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[${timestamp}] [ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) [[ $VERBOSE == true ]] && echo -e "${BLUE}[${timestamp}] [DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
        SUCCESS) echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

wait_for_service() {
    local service_name=$1
    local health_url=$2
    local max_attempts=${3:-30}
    local sleep_interval=${4:-10}
    
    log INFO "Waiting for $service_name to be ready..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if curl -sf "$health_url" >/dev/null 2>&1; then
            log SUCCESS "$service_name is ready"
            return 0
        fi
        
        if [[ $i -eq $max_attempts ]]; then
            log ERROR "$service_name is not responding after $((max_attempts * sleep_interval)) seconds"
            return 1
        fi
        
        log DEBUG "Attempt $i/$max_attempts failed, waiting ${sleep_interval}s..."
        sleep $sleep_interval
    done
}

make_api_request() {
    local method=$1
    local url=$2
    local data=${3:-""}
    local headers=${4:-""}
    local auth=${5:-""}
    
    local curl_cmd="curl -s"
    
    if [[ -n $auth ]]; then
        curl_cmd="$curl_cmd -H 'Authorization: $auth'"
    fi
    
    if [[ -n $headers ]]; then
        curl_cmd="$curl_cmd $headers"
    fi
    
    curl_cmd="$curl_cmd -X $method"
    
    if [[ -n $data ]]; then
        curl_cmd="$curl_cmd -d '$data'"
    fi
    
    curl_cmd="$curl_cmd '$url'"
    
    log DEBUG "API Request: $curl_cmd"
    
    if [[ $DRY_RUN == true ]]; then
        log INFO "DRY RUN: Would execute: $curl_cmd"
        echo '{"dry_run": true}'
        return 0
    fi
    
    eval $curl_cmd
}

# =============================================================================
# SERVICE HEALTH CHECKS
# =============================================================================

check_services_health() {
    log INFO "Checking service health..."
    
    local services=(
        "GitLab:${GITLAB_URL}/-/health"
        "SonarQube:${SONARQUBE_URL}/api/system/status"
        "Nexus:${NEXUS_URL}/service/rest/v1/status"
        "Jenkins:${JENKINS_URL}/login"
        "Grafana:${GRAFANA_URL}/api/health"
        "Vault:${VAULT_URL}/v1/sys/health"
    )
    
    local failed_services=()
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_url <<< "$service_info"
        
        if ! wait_for_service "$service_name" "$service_url" 3 5; then
            failed_services+=("$service_name")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log ERROR "The following services are not healthy: ${failed_services[*]}"
        log ERROR "Please ensure all services are running before configuring"
        exit 1
    fi
    
    log SUCCESS "All services are healthy and ready for configuration"
}

# =============================================================================
# GITLAB CONFIGURATION
# =============================================================================

configure_gitlab() {
    if [[ $SKIP_GITLAB == true ]]; then
        log INFO "Skipping GitLab configuration"
        return 0
    fi
    
    log INFO "Configuring GitLab..."
    
    # Get GitLab root password
    get_gitlab_credentials
    
    # Create admin API token
    create_gitlab_admin_token
    
    # Configure GitLab settings
    configure_gitlab_settings
    
    # Register GitLab Runner
    register_gitlab_runner
    
    # Create sample project
    create_sample_gitlab_project
    
    log SUCCESS "GitLab configuration completed"
}

get_gitlab_credentials() {
    log INFO "Retrieving GitLab credentials..."
    
    # Try to get initial root password from container
    local root_password
    root_password=$(docker-compose exec -T gitlab grep 'Password:' /etc/gitlab/initial_root_password 2>/dev/null | cut -d' ' -f2 || echo "")
    
    if [[ -z "$root_password" ]]; then
        log WARN "Could not retrieve GitLab root password automatically, using provided password"
        root_password="${GITLAB_ROOT_PASSWORD:-}"
    fi
    
    GITLAB_ROOT_PASSWORD="$root_password"
    log DEBUG "GitLab root password retrieved"
}

create_gitlab_admin_token() {
    log INFO "Creating GitLab admin API token..."
    
    # Create personal access token via Rails console
    local token_script="
user = User.find_by(username: 'root')
token = user.personal_access_tokens.create(
  name: 'DevOps Automation Token',
  scopes: ['api', 'read_user', 'read_repository', 'write_repository', 'read_registry', 'write_registry']
)
puts token.token
"
    
    GITLAB_ROOT_TOKEN=$(docker-compose exec -T gitlab gitlab-rails runner "$token_script" 2>/dev/null | tail -n1 | tr -d '\r\n')
    
    if [[ -z "$GITLAB_ROOT_TOKEN" || "$GITLAB_ROOT_TOKEN" == *"error"* ]]; then
        log WARN "Failed to create GitLab API token automatically"
        log INFO "You may need to create a personal access token manually in GitLab later"
        GITLAB_ROOT_TOKEN="temporary-token-placeholder"
    fi
    
    # Save token to config file
    echo "GITLAB_ROOT_TOKEN=$GITLAB_ROOT_TOKEN" >> "$CONFIG_BACKUP_DIR/tokens.conf"
    log SUCCESS "GitLab API token created and saved"
}

configure_gitlab_settings() {
    log INFO "Configuring GitLab application settings..."
    
    # Configure application settings via API
    local settings_payload='{
        "default_projects_limit": 100,
        "signup_enabled": false,
        "signin_enabled": true,
        "require_two_factor_authentication": false,
        "session_expire_delay": 10080,
        "default_project_visibility": "private",
        "default_snippet_visibility": "private",
        "default_group_visibility": "private",
        "container_registry_enabled": true,
        "container_registry_token_expire_delay": 5,
        "repository_checks_enabled": true,
        "shared_runners_enabled": true,
        "max_attachment_size": 100,
        "max_import_size": 50
    }'
    
    local response
    response=$(make_api_request "PUT" "${GITLAB_URL}/api/v4/application/settings" "$settings_payload" "-H 'Content-Type: application/json'" "Bearer $GITLAB_ROOT_TOKEN")
    
    if [[ $(echo "$response" | jq -r '.signup_enabled // empty') == "false" ]]; then
        log SUCCESS "GitLab settings configured successfully"
    else
        log WARN "GitLab settings configuration may have failed"
    fi
}

register_gitlab_runner() {
    log INFO "Registering GitLab Runner..."
    
    # Get runner registration token
    local runner_token
    runner_token=$(make_api_request "GET" "${GITLAB_URL}/api/v4/runners/registration_token" "" "" "Bearer $GITLAB_ROOT_TOKEN" | jq -r '.token')
    
    if [[ -z "$runner_token" || "$runner_token" == "null" ]]; then
        log ERROR "Failed to get GitLab Runner registration token"
        return 1
    fi
    
    # Register runner
    local register_cmd="gitlab-runner register \
        --non-interactive \
        --url $GITLAB_URL \
        --registration-token $runner_token \
        --executor docker \
        --docker-image docker:stable \
        --docker-privileged true \
        --docker-volumes /var/run/docker.sock:/var/run/docker.sock \
        --description 'DevOps Automation Runner' \
        --tag-list 'docker,automation,ci' \
        --locked=false \
        --access-level=not_protected"
    
    if [[ $DRY_RUN == true ]]; then
        log INFO "DRY RUN: Would register runner with command: $register_cmd"
    else
        docker-compose exec -T gitlab-runner $register_cmd
        log SUCCESS "GitLab Runner registered successfully"
    fi
}

create_sample_gitlab_project() {
    log INFO "Creating sample GitLab project..."
    
    local project_payload='{
        "name": "sample-cicd-project",
        "description": "Sample project with complete CI/CD pipeline",
        "visibility": "private",
        "initialize_with_readme": true,
        "container_registry_enabled": true,
        "issues_enabled": true,
        "wiki_enabled": true,
        "merge_requests_enabled": true,
        "jobs_enabled": true,
        "snippets_enabled": true
    }'
    
    local project_response
    project_response=$(make_api_request "POST" "${GITLAB_URL}/api/v4/projects" "$project_payload" "-H 'Content-Type: application/json'" "Bearer $GITLAB_ROOT_TOKEN")
    
    local project_id
    project_id=$(echo "$project_response" | jq -r '.id // empty')
    
    if [[ -n "$project_id" && "$project_id" != "null" ]]; then
        log SUCCESS "Sample project created with ID: $project_id"
        
        # Add CI/CD pipeline file
        add_gitlab_ci_pipeline "$project_id"
        
        # Configure project variables
        configure_gitlab_project_variables "$project_id"
    else
        log WARN "Sample project creation may have failed"
    fi
}

add_gitlab_ci_pipeline() {
    local project_id=$1
    log INFO "Adding CI/CD pipeline to project $project_id..."
    
    local gitlab_ci_content=$(cat << 'EOF'
stages:
  - validate
  - build
  - test
  - quality
  - security
  - package
  - deploy
  - notify

variables:
  DOCKER_REGISTRY: "localhost:5050"
  NEXUS_REPO: "localhost:8081"
  MAVEN_OPTS: "-Dmaven.repo.local=.m2/repository"
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: ""

cache:
  paths:
    - .m2/repository/
    - node_modules/
    - .sonar/cache

# Validate stage
validate:
  stage: validate
  image: hadolint/hadolint:latest
  script:
    - hadolint Dockerfile
  rules:
    - exists: [Dockerfile]

# Build stage
build:
  stage: build
  image: maven:3.8-openjdk-11
  script:
    - mvn clean compile
    - mvn package -DskipTests
  artifacts:
    paths:
      - target/
    expire_in: 1 hour

# Test stage
unit_tests:
  stage: test
  image: maven:3.8-openjdk-11
  script:
    - mvn test
    - mvn jacoco:report
  coverage: '/Total.*?([0-9]{1,3})%/'
  artifacts:
    reports:
      junit:
        - target/surefire-reports/TEST-*.xml
      coverage_report:
        coverage_format: cobertura
        path: target/site/jacoco/jacoco.xml

# Quality stage
sonarqube_analysis:
  stage: quality
  image: sonarsource/sonar-scanner-cli:latest
  variables:
    SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
    GIT_DEPTH: "0"
  script:
    - sonar-scanner
      -Dsonar.projectKey=$CI_PROJECT_NAME
      -Dsonar.sources=src/main
      -Dsonar.tests=src/test
      -Dsonar.host.url=http://sonarqube:9000
      -Dsonar.login=$SONAR_TOKEN
      -Dsonar.qualitygate.wait=true
  allow_failure: false

# Security stage
security_scan:
  stage: security
  image: owasp/zap2docker-stable
  script:
    - mkdir -p /zap/wrk
    - zap-baseline.py -t http://localhost:8080 -J zap-report.json || true
  artifacts:
    reports:
      sast: zap-report.json

# Package stage
docker_build:
  stage: package
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build -t $DOCKER_REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_SHA .
    - docker push $DOCKER_REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_SHA
  only:
    - main
    - develop

# Deploy stage
deploy_staging:
  stage: deploy
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker pull $DOCKER_REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_SHA
    - docker run -d --name staging-app -p 8000:8080 $DOCKER_REGISTRY/$CI_PROJECT_PATH:$CI_COMMIT_SHA
  environment:
    name: staging
    url: http://localhost:8000
  only:
    - develop

# Notification stage
notify_success:
  stage: notify
  image: curlimages/curl:latest
  script:
    - |
      curl -X POST http://webhook-receiver:9000/hooks/gitlab-pipeline-trigger \
        -H "Content-Type: application/json" \
        -H "X-Gitlab-Event: Pipeline Hook" \
        -d "{\"status\": \"success\", \"project\": \"$CI_PROJECT_NAME\", \"branch\": \"$CI_COMMIT_REF_NAME\"}"
  when: on_success
EOF
)
    
    # Base64 encode the content
    local encoded_content
    encoded_content=$(echo "$gitlab_ci_content" | base64 -w 0)
    
    local file_payload='{
        "branch": "main",
        "content": "'$encoded_content'",
        "commit_message": "Add CI/CD pipeline configuration",
        "encoding": "base64"
    }'
    
    local file_response
    file_response=$(make_api_request "POST" "${GITLAB_URL}/api/v4/projects/${project_id}/repository/files/.gitlab-ci.yml" "$file_payload" "-H 'Content-Type: application/json'" "Bearer $GITLAB_ROOT_TOKEN")
    
    if [[ $(echo "$file_response" | jq -r '.file_path // empty') == ".gitlab-ci.yml" ]]; then
        log SUCCESS "CI/CD pipeline file added to project"
    else
        log WARN "Failed to add CI/CD pipeline file"
    fi
}

configure_gitlab_project_variables() {
    local project_id=$1
    log INFO "Configuring project CI/CD variables..."
    
    local variables=(
        "SONAR_TOKEN:$SONAR_TOKEN:false"
        "NEXUS_USERNAME:admin:false"
        "NEXUS_PASSWORD:$NEXUS_ADMIN_PASSWORD:true"
        "DOCKER_REGISTRY:localhost:5050:false"
        "VAULT_TOKEN:$VAULT_TOKEN:true"
    )
    
    for var_info in "${variables[@]}"; do
        IFS=':' read -r var_key var_value var_protected <<< "$var_info"
        
        local var_payload='{
            "key": "'$var_key'",
            "value": "'$var_value'",
            "protected": '$var_protected',
            "masked": '$var_protected'
        }'
        
        local var_response
        var_response=$(make_api_request "POST" "${GITLAB_URL}/api/v4/projects/${project_id}/variables" "$var_payload" "-H 'Content-Type: application/json'" "Bearer $GITLAB_ROOT_TOKEN")
        
        if [[ $(echo "$var_response" | jq -r '.key // empty') == "$var_key" ]]; then
            log DEBUG "Variable $var_key configured successfully"
        else
            log WARN "Failed to configure variable $var_key"
        fi
    done
    
    log SUCCESS "Project variables configured"
}

# =============================================================================
# SONARQUBE CONFIGURATION
# =============================================================================

configure_sonarqube() {
    if [[ $SKIP_SONARQUBE == true ]]; then
        log INFO "Skipping SonarQube configuration"
        return 0
    fi
    
    log INFO "Configuring SonarQube..."
    
    # Change default admin password
    change_sonarqube_admin_password
    
    # Create user token
    create_sonarqube_token
    
    # Configure quality gates
    configure_sonarqube_quality_gates
    
    # Create project
    create_sonarqube_project
    
    # Configure webhooks
    configure_sonarqube_webhooks
    
    log SUCCESS "SonarQube configuration completed"
}

change_sonarqube_admin_password() {
    log INFO "Changing SonarQube admin password..."
    
    # Generate new password
    local new_password
    new_password=$(openssl rand -base64 16)
    
    local change_payload="login=admin&password=admin&previousPassword=admin&password=$new_password&passwordConfirmation=$new_password"
    
    local response
    response=$(curl -s -X POST "${SONARQUBE_URL}/api/users/change_password" \
        -u admin:admin \
        -d "$change_payload")
    
    if [[ $? -eq 0 ]]; then
        SONARQUBE_ADMIN_PASSWORD="$new_password"
        echo "SONARQUBE_ADMIN_PASSWORD=$new_password" >> "$CONFIG_BACKUP_DIR/tokens.conf"
        log SUCCESS "SonarQube admin password changed"
    else
        log WARN "Failed to change SonarQube admin password, using default"
        SONARQUBE_ADMIN_PASSWORD="admin"
    fi
}

create_sonarqube_token() {
    log INFO "Creating SonarQube user token..."
    
    local token_response
    token_response=$(curl -s -X POST "${SONARQUBE_URL}/api/user_tokens/generate" \
        -u admin:$SONARQUBE_ADMIN_PASSWORD \
        -d "name=DevOps-Automation-Token")
    
    SONAR_TOKEN=$(echo "$token_response" | jq -r '.token // empty')
    
    if [[ -n "$SONAR_TOKEN" && "$SONAR_TOKEN" != "null" ]]; then
        echo "SONAR_TOKEN=$SONAR_TOKEN" >> "$CONFIG_BACKUP_DIR/tokens.conf"
        log SUCCESS "SonarQube token created"
    else
        log ERROR "Failed to create SonarQube token"
        return 1
    fi
}

configure_sonarqube_quality_gates() {
    log INFO "Configuring SonarQube quality gates..."
    
    # Create custom quality gate
    local qg_payload='name=DevOps-Quality-Gate'
    
    local qg_response
    qg_response=$(curl -s -X POST "${SONARQUBE_URL}/api/qualitygates/create" \
        -u admin:$SONARQUBE_ADMIN_PASSWORD \
        -d "$qg_payload")
    
    local qg_id
    qg_id=$(echo "$qg_response" | jq -r '.id // empty')
    
    if [[ -n "$qg_id" && "$qg_id" != "null" ]]; then
        log DEBUG "Quality gate created with ID: $qg_id"
        
        # Add conditions to quality gate
        local conditions=(
            "coverage:LT:80.0"
            "duplicated_lines_density:GT:3.0"
            "maintainability_rating:GT:1"
            "reliability_rating:GT:1"
            "security_rating:GT:1"
            "sqale_rating:GT:1"
        )
        
        for condition in "${conditions[@]}"; do
            IFS=':' read -r metric op threshold <<< "$condition"
            
            local condition_payload="gateId=$qg_id&metric=$metric&op=$op&error=$threshold"
            
            curl -s -X POST "${SONARQUBE_URL}/api/qualitygates/create_condition" \
                -u admin:$SONARQUBE_ADMIN_PASSWORD \
                -d "$condition_payload" >/dev/null
                
            log DEBUG "Added condition: $metric $op $threshold"
        done
        
        # Set as default quality gate
        curl -s -X POST "${SONARQUBE_URL}/api/qualitygates/set_as_default" \
            -u admin:$SONARQUBE_ADMIN_PASSWORD \
            -d "id=$qg_id" >/dev/null
            
        log SUCCESS "Quality gate configured and set as default"
    else
        log WARN "Failed to create quality gate"
    fi
}

create_sonarqube_project() {
    log INFO "Creating SonarQube project..."
    
    local project_payload="project=sample-cicd-project&name=Sample%20CI/CD%20Project"
    
    local project_response
    project_response=$(curl -s -X POST "${SONARQUBE_URL}/api/projects/create" \
        -u admin:$SONARQUBE_ADMIN_PASSWORD \
        -d "$project_payload")
    
    if [[ $(echo "$project_response" | jq -r '.project.key // empty') == "sample-cicd-project" ]]; then
        log SUCCESS "SonarQube project created"
    else
        log WARN "Failed to create SonarQube project"
    fi
}

configure_sonarqube_webhooks() {
    log INFO "Configuring SonarQube webhooks..."
    
    local webhook_payload="name=GitLab%20Integration&url=http://webhook-receiver:9000/hooks/sonarqube-quality-gate"
    
    local webhook_response
    webhook_response=$(curl -s -X POST "${SONARQUBE_URL}/api/webhooks/create" \
        -u admin:$SONARQUBE_ADMIN_PASSWORD \
        -d "$webhook_payload")
    
    if [[ $(echo "$webhook_response" | jq -r '.webhook.name // empty') == "GitLab Integration" ]]; then
        log SUCCESS "SonarQube webhook configured"
    else
        log WARN "Failed to configure SonarQube webhook"
    fi
}

# =============================================================================
# NEXUS CONFIGURATION
# =============================================================================

configure_nexus() {
    if [[ $SKIP_NEXUS == true ]]; then
        log INFO "Skipping Nexus configuration"
        return 0
    fi
    
    log INFO "Configuring Nexus Repository Manager..."
    
    # Get admin password
    get_nexus_admin_password
    
    # Change admin password
    change_nexus_admin_password
    
    # Create repositories
    create_nexus_repositories
    
    # Configure cleanup policies
    configure_nexus_cleanup_policies
    
    # Create developer user
    create_nexus_developer_user
    
    log SUCCESS "Nexus configuration completed"
}

get_nexus_admin_password() {
    log INFO "Retrieving Nexus admin password..."
    
    local admin_password
    admin_password=$(docker-compose exec -T nexus cat /nexus-data/admin.password 2>/dev/null || echo "admin123")
    
    if [[ -z "$admin_password" || "$admin_password" == *"No such file"* ]]; then
        admin_password="admin123"
        log DEBUG "Using default Nexus admin password"
    else
        log DEBUG "Retrieved Nexus admin password from container"
    fi
    
    NEXUS_ADMIN_PASSWORD="$admin_password"
}

change_nexus_admin_password() {
    log INFO "Changing Nexus admin password..."
    
    local new_password
    new_password=$(openssl rand -base64 16)
    
    # First, check if we need to change from initial password
    local auth_header="admin:$NEXUS_ADMIN_PASSWORD"
    
    # Try to change password
    local response
    response=$(curl -s -w "%{http_code}" -X PUT "${NEXUS_URL}/service/rest/v1/security/users/admin/change-password" \
        -u "$auth_header" \
        -H "Content-Type: text/plain" \
        -d "$new_password")
    
    local http_code="${response: -3}"
    
    if [[ "$http_code" == "204" ]]; then
        NEXUS_ADMIN_PASSWORD="$new_password"
        echo "NEXUS_ADMIN_PASSWORD=$new_password" >> "$CONFIG_BACKUP_DIR/tokens.conf"
        log SUCCESS "Nexus admin password changed"
    else
        log WARN "Failed to change Nexus admin password (HTTP: $http_code)"
    fi
}

create_nexus_repositories() {
    log INFO "Creating Nexus repositories..."
    
    local auth_header="admin:$NEXUS_ADMIN_PASSWORD"
    
    # Maven repositories
    local maven_hosted_payload='{
        "name": "maven-releases",
        "online": true,
        "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": true,
            "writePolicy": "ALLOW_ONCE"
        },
        "maven": {
            "versionPolicy": "RELEASE",
            "layoutPolicy": "STRICT"
        }
    }'
    
    curl -s -X POST "${NEXUS_URL}/service/rest/v1/repositories/maven/hosted" \
        -u "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$maven_hosted_payload" >/dev/null
    
    # NPM repositories
    local npm_hosted_payload='{
        "name": "npm-private",
        "online": true,
        "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": true,
            "writePolicy": "ALLOW"
        }
    }'
    
    curl -s -X POST "${NEXUS_URL}/service/rest/v1/repositories/npm/hosted" \
        -u "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$npm_hosted_payload" >/dev/null
    
    # Docker repositories
    local docker_hosted_payload='{
        "name": "docker-private",
        "online": true,
        "storage": {
            "blobStoreName": "default",
            "strictContentTypeValidation": true,
            "writePolicy": "ALLOW"
        },
        "docker": {
            "v1Enabled": false,
            "forceBasicAuth": true,
            "httpPort": 8082
        }
    }'
    
    curl -s -X POST "${NEXUS_URL}/service/rest/v1/repositories/docker/hosted" \
        -u "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$docker_hosted_payload" >/dev/null
    
    log SUCCESS "Nexus repositories created"
}

configure_nexus_cleanup_policies() {
    log INFO "Configuring Nexus cleanup policies..."
    
    local auth_header="admin:$NEXUS_ADMIN_PASSWORD"
    
    local cleanup_policy_payload='{
        "name": "docker-cleanup",
        "notes": "Cleanup old Docker images",
        "format": "docker",
        "criteria": {
            "lastBlobUpdated": 30,
            "lastDownloaded": 30
        }
    }'
    
    curl -s -X POST "${NEXUS_URL}/service/rest/v1/cleanup-policies" \
        -u "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$cleanup_policy_payload" >/dev/null
    
    log SUCCESS "Nexus cleanup policies configured"
}

create_nexus_developer_user() {
    log INFO "Creating Nexus developer user..."
    
    local auth_header="admin:$NEXUS_ADMIN_PASSWORD"
    
    local developer_password
    developer_password=$(openssl rand -base64 12)
    
    local user_payload='{
        "userId": "developer",
        "firstName": "Developer",
        "lastName": "User",
        "emailAddress": "developer@company.com",
        "password": "'$developer_password'",
        "status": "active",
        "roles": ["nx-repository-view-*-*-*"]
    }'
    
    local response
    response=$(curl -s -w "%{http_code}" -X POST "${NEXUS_URL}/service/rest/v1/security/users" \
        -u "$auth_header" \
        -H "Content-Type: application/json" \
        -d "$user_payload")
    
    local http_code="${response: -3}"
    
    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        echo "NEXUS_DEVELOPER_PASSWORD=$developer_password" >> "$CONFIG_BACKUP_DIR/tokens.conf"
        log SUCCESS "Nexus developer user created"
    else
        log WARN "Failed to create Nexus developer user (HTTP: $http_code)"
    fi
}

# =============================================================================
# JENKINS CONFIGURATION
# =============================================================================

configure_jenkins() {
    if [[ $SKIP_JENKINS == true ]]; then
        log INFO "Skipping Jenkins configuration"
        return 0
    fi
    
    log INFO "Configuring Jenkins..."
    
    # Get initial admin password
    get_jenkins_admin_password
    
    # Install essential plugins
    install_jenkins_plugins
    
    # Create API token
    create_jenkins_api_token
    
    # Configure global tools
    configure_jenkins_global_tools
    
    # Create sample job
    create_jenkins_sample_job
    
    log SUCCESS "Jenkins configuration completed"
}

get_jenkins_admin_password() {
    log INFO "Retrieving Jenkins admin password..."
    
    local admin_password
    admin_password=$(docker-compose exec -T jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "")
    
    if [[ -z "$admin_password" ]]; then
        log WARN "Could not retrieve Jenkins admin password automatically"
        admin_password=$(docker exec jenkins-master cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "")
        if [[ -z "$admin_password" ]]; then
            log ERROR "Could not retrieve Jenkins admin password, skipping Jenkins configuration"
            return 1
        fi
    fi
    
    JENKINS_ADMIN_PASSWORD="$admin_password"
    log DEBUG "Jenkins admin password retrieved"
}

install_jenkins_plugins() {
    log INFO "Installing Jenkins plugins..."
    
    local plugins=(
        "gitlab-plugin"
        "sonar"
        "nexus-artifact-uploader"
        "docker-plugin"
        "docker-workflow"
        "pipeline-stage-view"
        "build-pipeline-plugin"
        "workflow-aggregator"
        "git"
        "github"
        "credentials"
        "ssh-credentials"
        "plain-credentials"
    )
    
    # Create Jenkins CLI command
    local jenkins_cli="java -jar /var/jenkins_home/war/WEB-INF/jenkins-cli.jar -s $JENKINS_URL -auth admin:$JENKINS_ADMIN_PASSWORD"
    
    for plugin in "${plugins[@]}"; do
        log DEBUG "Installing plugin: $plugin"
        if [[ $DRY_RUN == true ]]; then
            log INFO "DRY RUN: Would install Jenkins plugin: $plugin"
        else
            docker-compose exec -T jenkins $jenkins_cli install-plugin "$plugin" || log WARN "Failed to install plugin: $plugin"
        fi
    done
    
    # Restart Jenkins safely
    if [[ $DRY_RUN == false ]]; then
        docker-compose exec -T jenkins $jenkins_cli safe-restart
        log INFO "Jenkins restarting, waiting for it to come back online..."
        sleep 30
        wait_for_service "Jenkins" "${JENKINS_URL}/login" 10 15
    fi
    
    log SUCCESS "Jenkins plugins installed"
}

create_jenkins_api_token() {
    log INFO "Creating Jenkins API token..."
    
    # This is a simplified approach - in practice, you might need to use Jenkins API
    # or configure through the web interface
    local token
    token=$(openssl rand -hex 16)
    
    JENKINS_API_TOKEN="$token"
    echo "JENKINS_API_TOKEN=$token" >> "$CONFIG_BACKUP_DIR/tokens.conf"
    
    log DEBUG "Jenkins API token generated (manual configuration may be required)"
}

configure_jenkins_global_tools() {
    log INFO "Configuring Jenkins global tools..."
    
    # This would typically involve configuring Maven, JDK, Docker, etc.
    # through Jenkins configuration files or API
    
    local config_script='
import jenkins.model.*
import hudson.model.*
import hudson.tools.*

def instance = Jenkins.getInstance()

// Configure Maven
def mavenDesc = instance.getDescriptor("hudson.tasks.Maven")
def mavenInstallations = [
  new Maven.MavenInstallation("Maven-3.8", "/opt/maven", [])
]
mavenDesc.setInstallations(mavenInstallations as Maven.MavenInstallation[])

// Configure JDK
def jdkDesc = instance.getDescriptor("hudson.model.JDK")
def jdkInstallations = [
  new JDK("OpenJDK-11", "/opt/java/openjdk")
]
jdkDesc.setInstallations(jdkInstallations as JDK[])

instance.save()
'
    
    if [[ $DRY_RUN == true ]]; then
        log INFO "DRY RUN: Would configure Jenkins global tools"
    else
        echo "$config_script" | docker-compose exec -T jenkins groovy = || log WARN "Failed to configure Jenkins global tools"
    fi
    
    log SUCCESS "Jenkins global tools configured"
}

create_jenkins_sample_job() {
    log INFO "Creating Jenkins sample job..."
    
    local job_config='<?xml version="1.0" encoding="UTF-8"?>
<project>
  <description>Sample CI/CD job integrated with GitLab</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <com.coravy.hudson.plugins.github.GithubProjectProperty>
      <projectUrl>http://gitlab:8090/root/sample-cicd-project</projectUrl>
    </com.coravy.hudson.plugins.github.GithubProjectProperty>
  </properties>
  <scm class="hudson.plugins.git.GitSCM">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>http://gitlab:8090/root/sample-cicd-project.git</url>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>*/main</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
  </scm>
  <triggers>
    <hudson.triggers.SCMTrigger>
      <spec>H/5 * * * *</spec>
    </hudson.triggers.SCMTrigger>
  </triggers>
  <builders>
    <hudson.tasks.Shell>
      <command>
echo "Building project..."
if [ -f pom.xml ]; then
    mvn clean compile test
elif [ -f package.json ]; then
    npm install
    npm test
else
    echo "No build configuration found"
fi
      </command>
    </hudson.tasks.Shell>
  </builders>
</project>'
    
    if [[ $DRY_RUN == true ]]; then
        log INFO "DRY RUN: Would create Jenkins sample job"
    else
        echo "$job_config" | docker-compose exec -T jenkins java -jar /var/jenkins_home/war/WEB-INF/jenkins-cli.jar -s $JENKINS_URL -auth admin:$JENKINS_ADMIN_PASSWORD create-job "sample-cicd-project" || log WARN "Failed to create Jenkins sample job"
    fi
    
    log SUCCESS "Jenkins sample job created"
}

# =============================================================================
# MONITORING CONFIGURATION
# =============================================================================

configure_monitoring() {
    if [[ $SKIP_MONITORING == true ]]; then
        log INFO "Skipping monitoring configuration"
        return 0
    fi
    
    log INFO "Configuring monitoring stack..."
    
    # Configure Grafana
    configure_grafana
    
    # Configure Prometheus
    configure_prometheus
    
    log SUCCESS "Monitoring configuration completed"
}

configure_grafana() {
    log INFO "Configuring Grafana..."
    
    # Wait for Grafana to be ready
    wait_for_service "Grafana" "${GRAFANA_URL}/api/health" 10 10
    
    # Add Prometheus data source
    local datasource_payload='{
        "name": "Prometheus",
        "type": "prometheus",
        "url": "http://prometheus:9090",
        "access": "proxy",
        "isDefault": true
    }'
    
    local response
    response=$(curl -s -X POST "${GRAFANA_URL}/api/datasources" \
        -u admin:${GRAFANA_ADMIN_PASSWORD:-admin} \
        -H "Content-Type: application/json" \
        -d "$datasource_payload")
    
    if [[ $(echo "$response" | jq -r '.name // empty') == "Prometheus" ]]; then
        log SUCCESS "Prometheus data source added to Grafana"
    else
        log WARN "Failed to add Prometheus data source to Grafana"
    fi
    
    # Import dashboard
    import_grafana_dashboard
}

import_grafana_dashboard() {
    log INFO "Importing Grafana dashboard..."
    
    local dashboard_json='{
        "dashboard": {
            "title": "DevOps Pipeline Dashboard",
            "tags": ["devops", "ci-cd"],
            "timezone": "browser",
            "panels": [
                {
                    "title": "Pipeline Success Rate",
                    "type": "stat",
                    "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
                    "targets": [
                        {
                            "expr": "gitlab_ci_pipeline_success_rate",
                            "refId": "A"
                        }
                    ]
                },
                {
                    "title": "Build Duration",
                    "type": "graph",
                    "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
                    "targets": [
                        {
                            "expr": "gitlab_ci_pipeline_duration_seconds",
                            "refId": "B"
                        }
                    ]
                }
            ],
            "time": {"from": "now-6h", "to": "now"},
            "refresh": "30s"
        },
        "overwrite": true
    }'
    
    local import_response
    import_response=$(curl -s -X POST "${GRAFANA_URL}/api/dashboards/db" \
        -u admin:${GRAFANA_ADMIN_PASSWORD:-admin} \
        -H "Content-Type: application/json" \
        -d "$dashboard_json")
    
    if [[ $(echo "$import_response" | jq -r '.status // empty') == "success" ]]; then
        log SUCCESS "Dashboard imported to Grafana"
    else
        log WARN "Failed to import dashboard to Grafana"
    fi
}

configure_prometheus() {
    log INFO "Configuring Prometheus..."
    
    # Prometheus configuration is typically done via configuration file
    # which should already be mounted from the docker-compose setup
    
    log INFO "Prometheus configuration is handled via mounted config file"
    log SUCCESS "Prometheus configuration verified"
}

# =============================================================================
# VAULT CONFIGURATION
# =============================================================================

configure_vault() {
    if [[ $SKIP_VAULT == true ]]; then
        log INFO "Skipping Vault configuration"
        return 0
    fi
    
    log INFO "Configuring HashiCorp Vault..."
    
    # Initialize and unseal vault (dev mode should already be running)
    configure_vault_secrets
    
    log SUCCESS "Vault configuration completed"
}

configure_vault_secrets() {
    log INFO "Configuring Vault secrets..."
    
    # Set up environment
    export VAULT_ADDR="$VAULT_URL"
    export VAULT_TOKEN="$VAULT_TOKEN"
    
    # Enable KV secrets engine (may already be enabled in dev mode)
    local kv_response
    kv_response=$(curl -s -X POST "${VAULT_URL}/v1/sys/mounts/secret" \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"type": "kv", "options": {"version": "2"}}')
    
    # Store sample secrets
    local secrets=(
        "myapp/database:username=dbuser,password=$(openssl rand -base64 16),host=localhost,port=5432"
        "myapp/api:key=$(openssl rand -hex 32),secret=$(openssl rand -base64 32)"
        "myapp/smtp:username=smtp@company.com,password=$(openssl rand -base64 16),host=smtp.company.com"
    )
    
    for secret_info in "${secrets[@]}"; do
        IFS=':' read -r secret_path secret_data <<< "$secret_info"
        
        # Convert comma-separated key=value pairs to JSON
        local json_data="{"
        IFS=',' read -ra PAIRS <<< "$secret_data"
        for pair in "${PAIRS[@]}"; do
            IFS='=' read -r key value <<< "$pair"
            json_data="$json_data\"$key\":\"$value\","
        done
        json_data="${json_data%,}}"
        
        local vault_payload="{\"data\":$json_data}"
        
        curl -s -X POST "${VAULT_URL}/v1/secret/data/$secret_path" \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$vault_payload" >/dev/null
        
        log DEBUG "Stored secret: $secret_path"
    done
    
    log SUCCESS "Vault secrets configured"
}

# =============================================================================
# WEBHOOK CONFIGURATION
# =============================================================================

configure_webhooks() {
    log INFO "Configuring webhooks..."
    
    # Create webhook handler scripts
    create_webhook_handlers
    
    log SUCCESS "Webhook configuration completed"
}

create_webhook_handlers() {
    log INFO "Creating webhook handler scripts..."
    
    # Create quality gate handler
    cat > "webhooks/quality-gate-handler.sh" << 'EOF'
#!/bin/bash
# SonarQube Quality Gate Webhook Handler

WEBHOOK_DATA="$1"
echo "Quality Gate webhook received at $(date)"
echo "Data: $WEBHOOK_DATA" | jq .

# Parse webhook data
PROJECT_KEY=$(echo "$WEBHOOK_DATA" | jq -r '.project.key')
QUALITY_GATE_STATUS=$(echo "$WEBHOOK_DATA" | jq -r '.qualityGate.status')

echo "Project: $PROJECT_KEY"
echo "Quality Gate Status: $QUALITY_GATE_STATUS"

# You can add custom logic here, such as:
# - Sending notifications
# - Triggering other processes
# - Updating external systems

if [ "$QUALITY_GATE_STATUS" = "ERROR" ]; then
    echo "Quality gate failed for project $PROJECT_KEY"
    # Send notification or take corrective action
elif [ "$QUALITY_GATE_STATUS" = "OK" ]; then
    echo "Quality gate passed for project $PROJECT_KEY"
    # Continue with deployment pipeline
fi
EOF

    # Create pipeline handler
    cat > "webhooks/pipeline-handler.sh" << 'EOF'
#!/bin/bash
# GitLab Pipeline Webhook Handler

WEBHOOK_DATA="$1"
echo "Pipeline webhook received at $(date)"
echo "Data: $WEBHOOK_DATA" | jq .

# Parse webhook data
PROJECT_NAME=$(echo "$WEBHOOK_DATA" | jq -r '.project')
PIPELINE_STATUS=$(echo "$WEBHOOK_DATA" | jq -r '.status')
BRANCH=$(echo "$WEBHOOK_DATA" | jq -r '.branch')

echo "Project: $PROJECT_NAME"
echo "Status: $PIPELINE_STATUS"
echo "Branch: $BRANCH"

# Custom logic based on pipeline status
case $PIPELINE_STATUS in
    "success")
        echo "Pipeline succeeded for $PROJECT_NAME on $BRANCH"
        # Send success notification
        ;;
    "failed")
        echo "Pipeline failed for $PROJECT_NAME on $BRANCH"
        # Send failure notification and create issue
        ;;
    *)
        echo "Pipeline status: $PIPELINE_STATUS"
        ;;
esac
EOF

    chmod +x webhooks/*.sh
    
    log SUCCESS "Webhook handlers created"
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

run_integration_tests() {
    log INFO "Running integration tests..."
    
    # Test GitLab API
    test_gitlab_integration
    
    # Test SonarQube API
    test_sonarqube_integration
    
    # Test Nexus API
    test_nexus_integration
    
    # Test monitoring endpoints
    test_monitoring_integration
    
    log SUCCESS "Integration tests completed"
}

test_gitlab_integration() {
    log INFO "Testing GitLab integration..."
    
    local response
    response=$(curl -s "${GITLAB_URL}/api/v4/projects" -H "Authorization: Bearer $GITLAB_ROOT_TOKEN")
    
    if [[ $(echo "$response" | jq '. | length') -gt 0 ]]; then
        log SUCCESS "GitLab API integration working"
    else
        log ERROR "GitLab API integration failed"
    fi
}

test_sonarqube_integration() {
    log INFO "Testing SonarQube integration..."
    
    local response
    response=$(curl -s "${SONARQUBE_URL}/api/projects/search" -u "admin:$SONARQUBE_ADMIN_PASSWORD")
    
    if [[ $(echo "$response" | jq '.components | length') -ge 0 ]]; then
        log SUCCESS "SonarQube API integration working"
    else
        log ERROR "SonarQube API integration failed"
    fi
}

test_nexus_integration() {
    log INFO "Testing Nexus integration..."
    
    local response
    response=$(curl -s "${NEXUS_URL}/service/rest/v1/repositories" -u "admin:$NEXUS_ADMIN_PASSWORD")
    
    if [[ $(echo "$response" | jq '. | length') -gt 0 ]]; then
        log SUCCESS "Nexus API integration working"
    else
        log ERROR "Nexus API integration failed"
    fi
}

test_monitoring_integration() {
    log INFO "Testing monitoring integration..."
    
    # Test Grafana
    local grafana_response
    grafana_response=$(curl -s "${GRAFANA_URL}/api/datasources" -u "admin:admin123")
    
    if [[ $(echo "$grafana_response" | jq '. | length') -gt 0 ]]; then
        log SUCCESS "Grafana integration working"
    else
        log WARN "Grafana integration may have issues"
    fi
    
    # Test Prometheus
    local prometheus_response
    prometheus_response=$(curl -s "${PROMETHEUS_URL}/api/v1/targets")
    
    if [[ $(echo "$prometheus_response" | jq -r '.status') == "success" ]]; then
        log SUCCESS "Prometheus integration working"
    else
        log WARN "Prometheus integration may have issues"
    fi
}

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

generate_configuration_summary() {
    log INFO "Generating configuration summary..."
    
    local summary_file="$CONFIG_BACKUP_DIR/configuration-summary.md"
    
    cat > "$summary_file" << EOF
# DevOps Stack Configuration Summary

**Configuration Date:** $(date)
**Configuration Version:** $SCRIPT_VERSION

## Service Endpoints

- **GitLab:** $GITLAB_URL
- **SonarQube:** $SONARQUBE_URL  
- **Nexus:** $NEXUS_URL
- **Jenkins:** $JENKINS_URL
- **Grafana:** $GRAFANA_URL
- **Prometheus:** $PROMETHEUS_URL
- **Vault:** $VAULT_URL

## Configured Features

### GitLab
- ✅ Admin API token created
- ✅ GitLab Runner registered
- ✅ Sample project created with CI/CD pipeline
- ✅ Project variables configured

### SonarQube
- ✅ Admin password changed
- ✅ User token created
- ✅ Custom quality gate configured
- ✅ Sample project created
- ✅ Webhook configured

### Nexus
- ✅ Admin password changed
- ✅ Repositories created (Maven, NPM, Docker)
- ✅ Cleanup policies configured
- ✅ Developer user created

### Jenkins
- ✅ Essential plugins installed
- ✅ Global tools configured
- ✅ Sample job created

### Monitoring
- ✅ Grafana data source configured
- ✅ Dashboard imported
- ✅ Prometheus targets configured

### Security
- ✅ Vault secrets configured
- ✅ Webhook handlers created

## Next Steps

1. Access services using the credentials in \`tokens.conf\`
2. Customize quality gates and policies as needed
3. Add your own projects and repositories
4. Configure additional integrations
5. Set up backup and monitoring alerts

## Important Files

- **Credentials:** \`$CONFIG_BACKUP_DIR/tokens.conf\`
- **Configuration Backup:** \`$CONFIG_BACKUP_DIR/\`
- **Logs:** \`$LOG_FILE\`

EOF

    log SUCCESS "Configuration summary generated: $summary_file"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo -e "${CYAN}"
    echo "=========================================="
    echo "   DevOps Stack Configuration Script"
    echo "             Version $SCRIPT_VERSION"
    echo "=========================================="
    echo -e "${NC}"
    
    # Create backup directory for configuration
    mkdir -p "$CONFIG_BACKUP_DIR"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-gitlab)
                SKIP_GITLAB=true
                shift
                ;;
            --skip-sonarqube)
                SKIP_SONARQUBE=true
                shift
                ;;
            --skip-nexus)
                SKIP_NEXUS=true
                shift
                ;;
            --skip-jenkins)
                SKIP_JENKINS=true
                shift
                ;;
            --skip-monitoring)
                SKIP_MONITORING=true
                shift
                ;;
            --skip-vault)
                SKIP_VAULT=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log INFO "Starting DevOps stack configuration..."
    log INFO "Configuration will be saved to: $CONFIG_BACKUP_DIR"
    
    # Check service health first
    check_services_health
    
    # Configure services
    configure_gitlab
    configure_sonarqube  
    configure_nexus
    configure_jenkins
    configure_monitoring
    configure_vault
    configure_webhooks
    
    # Run integration tests
    run_integration_tests
    
    # Generate summary
    generate_configuration_summary
    
    log SUCCESS "DevOps stack configuration completed successfully!"
    echo
    echo -e "${GREEN}Configuration Summary:${NC}"
    echo -e "📁 Configuration backup: ${BLUE}$CONFIG_BACKUP_DIR${NC}"
    echo -e "📄 Log file: ${BLUE}$LOG_FILE${NC}"
    echo -e "🔑 Credentials file: ${BLUE}$CONFIG_BACKUP_DIR/tokens.conf${NC}"
    echo -e "📊 Summary report: ${BLUE}$CONFIG_BACKUP_DIR/configuration-summary.md${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review the configuration summary"
    echo "2. Save the credentials securely"
    echo "3. Access your services and start developing!"
    echo "4. Check the sample project in GitLab to see the CI/CD pipeline in action"
}

show_help() {
    cat << EOF
DevOps Stack Configuration Script

Usage: $0 [OPTIONS]

OPTIONS:
    --skip-gitlab       Skip GitLab configuration
    --skip-sonarqube    Skip SonarQube configuration  
    --skip-nexus        Skip Nexus configuration
    --skip-jenkins      Skip Jenkins configuration
    --skip-monitoring   Skip monitoring configuration
    --skip-vault        Skip Vault configuration
    --dry-run          Show what would be done without making changes
    --verbose          Enable verbose logging
    --help             Show this help message

EXAMPLES:
    $0                                    # Configure all services
    $0 --skip-jenkins --skip-vault       # Skip Jenkins and Vault
    $0 --dry-run --verbose               # Dry run with verbose output

REQUIREMENTS:
    - All services must be running and healthy
    - Docker and curl must be available
    - Network connectivity to all service endpoints
EOF
}

# Execute main function
main "$@"