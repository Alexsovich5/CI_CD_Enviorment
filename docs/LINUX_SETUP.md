# DevOps Stack for Linux

This DevOps environment has been adapted to work seamlessly on Linux systems. Below are the installation and setup instructions for Linux distributions.

## Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+, CentOS 8+, Debian 11+, or any modern Linux distribution
- **RAM**: 8GB minimum, 16GB recommended
- **Disk**: 50GB+ free space
- **CPU**: 4+ cores recommended

### Required Software

#### 1. Install Docker Engine
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Add your user to docker group (logout/login required after this)
sudo usermod -aG docker $USER
```

#### 2. Install Docker Compose
```bash
# Install Docker Compose (latest version)
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker-compose --version
```

#### For CentOS/RHEL/Fedora:
```bash
# Install Docker
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER
```

## Linux-Specific Configuration

### 1. System Limits
For optimal performance, especially for SonarQube, adjust system limits:

```bash
# Edit limits configuration
sudo tee -a /etc/security/limits.conf << EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 4096
* hard nproc 4096
EOF

# Edit sysctl configuration for SonarQube
sudo tee -a /etc/sysctl.conf << EOF
vm.max_map_count=262144
fs.file-max=65536
EOF

# Apply sysctl settings
sudo sysctl -p
```

### 2. Firewall Configuration
```bash
# Ubuntu/Debian (UFW)
sudo ufw allow 8080/tcp   # GitLab
sudo ufw allow 9000/tcp   # SonarQube
sudo ufw allow 8081/tcp   # Nexus
sudo ufw allow 8082/tcp   # Jenkins
sudo ufw allow 3000/tcp   # Grafana
sudo ufw allow 9090/tcp   # Prometheus

# CentOS/RHEL (firewalld)
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --add-port=9000/tcp
sudo firewall-cmd --permanent --add-port=8081/tcp
sudo firewall-cmd --permanent --add-port=8082/tcp
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=9090/tcp
sudo firewall-cmd --reload
```

## Quick Start

### 1. Clone and Setup
```bash
git clone <your-repo-url>
cd ClaudeDevEnv

# Make setup script executable
chmod +x setup.sh

# Check prerequisites
./setup.sh check
```

### 2. Initialize Environment
```bash
# Initialize project structure
./setup.sh init
```

### 3. Start Core Services
```bash
# Start core DevOps services
./setup.sh start core

# Or start all services
./setup.sh start full
```

### 4. Access Services
After startup (5-10 minutes), access services at:
- **GitLab**: http://localhost:8080
- **SonarQube**: http://localhost:9000
- **Nexus Repository**: http://localhost:8081
- **Jenkins**: http://localhost:8082
- **Grafana**: http://localhost:3000
- **Prometheus**: http://localhost:9090

## Linux-Specific Features

### 1. Service Management
```bash
# Check service status
./setup.sh status

# View logs
./setup.sh logs [service-name]

# Monitor resources
./setup.sh resources

# Health check
./setup.sh health
```

### 2. System Integration
The stack integrates with Linux system services:

```bash
# Create systemd service for auto-start (optional)
sudo tee /etc/systemd/system/devops-stack.service << EOF
[Unit]
Description=DevOps Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/path/to/ClaudeDevEnv
ExecStart=/path/to/ClaudeDevEnv/setup.sh start core
ExecStop=/path/to/ClaudeDevEnv/setup.sh stop
TimeoutStartSec=0
User=your-username

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable devops-stack.service
```

### 3. Backup and Maintenance
```bash
# Create backup
./setup.sh backup

# Cleanup (removes all containers and volumes)
./setup.sh cleanup

# Update services
docker-compose pull
./setup.sh restart
```

## Troubleshooting

### Common Linux Issues

1. **Permission Denied for Docker Socket**
   ```bash
   sudo usermod -aG docker $USER
   newgrp docker  # Or logout/login
   ```

2. **Port Already in Use**
   ```bash
   sudo netstat -tulpn | grep :8080
   sudo kill -9 <PID>
   ```

3. **Insufficient Memory for SonarQube**
   ```bash
   # Check available memory
   free -h
   
   # If needed, create swap space
   sudo fallocate -l 2G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

4. **SELinux Issues (CentOS/RHEL)**
   ```bash
   # Temporarily disable SELinux
   sudo setenforce 0
   
   # Or set proper contexts
   sudo setsebool -P container_manage_cgroup on
   ```

### Performance Optimization

1. **For Production Environments**
   ```bash
   # Increase file descriptors
   echo 'fs.file-max = 65536' | sudo tee -a /etc/sysctl.conf
   
   # Optimize Docker
   sudo tee /etc/docker/daemon.json << EOF
   {
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "10m",
       "max-file": "3"
     },
     "storage-driver": "overlay2"
   }
   EOF
   
   sudo systemctl restart docker
   ```

2. **Resource Monitoring**
   ```bash
   # Monitor Docker containers
   docker stats
   
   # Monitor system resources
   htop
   iotop
   ```

## Environment Variables

Set these environment variables for Linux-specific configurations:

```bash
# Add to ~/.bashrc or ~/.profile
export JENKINS_USER="1000:1000"  # Use your user:group ID
export COMPOSE_PROJECT_NAME="claudedevenv"
export DOCKER_BUILDKIT=1
```

## Security Considerations

1. **Network Security**
   - Services are bound to localhost by default
   - Use reverse proxy (Traefik included) for external access
   - Configure SSL certificates for production

2. **Container Security**
   - Containers run with minimal privileges
   - Regular security updates via `docker-compose pull`
   - Secrets managed via Docker secrets or Vault

3. **Data Protection**
   - All data stored in named Docker volumes
   - Regular backups via included backup scripts
   - Volume encryption available for sensitive data

This Linux-adapted DevOps stack provides a robust, scalable environment for development and CI/CD workflows on Linux systems.