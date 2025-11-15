# Setup and Troubleshooting Guide

## 🚀 Complete Setup Guide

This guide will take you through setting up the Advanced Threat Detection System from scratch, with detailed explanations and troubleshooting tips for each step.

## 📋 Prerequisites

### System Requirements

```
MINIMUM REQUIREMENTS:
- OS: Linux (Ubuntu 18.04+), macOS (10.14+), or Windows 10+
- RAM: 8 GB (16 GB recommended)
- CPU: 4 cores (8 cores recommended)
- Storage: 50 GB free space (100 GB recommended)
- Network: Internet connection for downloading images

RECOMMENDED FOR PRODUCTION:
- RAM: 32 GB or more
- CPU: 16 cores or more
- Storage: 500 GB SSD
- Network: High-speed internet connection
```

### Required Software

```
✅ MUST HAVE:
- Docker (version 20.10+)
- Docker Compose (version 2.0+)
- Git (for cloning the repository)

✅ OPTIONAL BUT HELPFUL:
- curl (for testing APIs)
- jq (for formatting JSON responses)
- wget (for downloading files)
```

### Installing Prerequisites

#### Ubuntu/Debian
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install utilities
sudo apt install -y git curl jq wget

# Logout and login to apply Docker permissions
```

#### CentOS/RHEL/Fedora
```bash
# Install Docker
sudo dnf install -y docker docker-compose
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Install utilities
sudo dnf install -y git curl jq wget
```

#### macOS
```bash
# Install Docker Desktop from: https://docker.com/products/docker-desktop
# Or use Homebrew:
brew install docker docker-compose git curl jq wget
```

#### Windows
```powershell
# Install Docker Desktop from: https://docker.com/products/docker-desktop
# Install Git from: https://git-scm.com/download/win
# Install curl: Available in Windows 10+ by default
```

## 📥 Installation Steps

### Step 1: Clone the Repository
```bash
# Clone the repository
git clone https://github.com/rohansen856/elk-stack-monitoring
cd elk-stack-monitoring

# Verify you're in the right directory
ls -la
# You should see: docker-compose.yml, README.md, app/, etc.
```

### Step 2: Configure Environment Variables
```bash
# Copy the example environment file
cp .env.example .env

# Edit the configuration file
nano .env  # or use your preferred editor

# IMPORTANT: Change these settings for security
# - SECRET_KEY: Generate a strong secret key
# - Database passwords
# - Slack webhook URL (if using Slack alerts)
```

#### Example .env Configuration
```bash
# Database Configuration
DATABASE_URL=postgresql://user:password@db:5432/todo_db
POSTGRES_DB=todo_db
POSTGRES_USER=user
POSTGRES_PASSWORD=change_this_password

# Redis Configuration
REDIS_URL=redis://redis:6379

# Application Security
SECRET_KEY=change-this-to-a-very-long-random-string
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# ELK Stack Configuration
ELASTICSEARCH_URL=http://elasticsearch:9200
ELASTICSEARCH_HOST=elasticsearch
ELASTICSEARCH_PORT=9200

# Environment
ENVIRONMENT=development
LOG_LEVEL=INFO

# Alerting (Optional)
SLACK_WEBHOOK_URL=https://hooks.slack.com/your/webhook/url
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
EMAIL_USER=your-email@gmail.com
EMAIL_PASSWORD=your-email-password
```

### Step 3: Start the System
```bash
# Start all services
docker-compose up -d

# This will take 2-5 minutes the first time
# Docker will download all necessary images

# Check that all services are starting
docker-compose ps
```

### Step 4: Wait for Services to Initialize
```bash
# Check service health (wait for all to be healthy)
watch docker-compose ps

# Or check individual service logs
docker-compose logs -f elasticsearch
docker-compose logs -f logstash
docker-compose logs -f kibana
```

### Step 5: Verify Installation
```bash
# Check Elasticsearch
curl http://localhost:9200/_cluster/health
# Should return: {"status":"green"} or {"status":"yellow"}

# Check Logstash
curl http://localhost:9600/_node/stats
# Should return JSON with node statistics

# Check Kibana
curl http://localhost:5601/api/status
# Should return status information

# Check FastAPI application
curl http://localhost:8000/health
# Should return: {"status":"healthy","database":"ok","redis":"ok"}

# Check Redis
docker-compose exec redis redis-cli ping
# Should return: PONG
```

### Step 6: Initialize the Database
```bash
# Run database migrations
docker-compose exec app alembic upgrade head

# Verify tables were created
docker-compose exec db psql -U user -d todo_db -c "\dt"
# Should show: users, todos, and alembic_version tables
```

### Step 7: Access the System
```bash
# FastAPI Application (API and docs)
echo "Application: http://localhost:8000"
echo "API Docs: http://localhost:8000/docs"

# Kibana Dashboard
echo "Kibana: http://localhost:5601"

# Health Check
echo "Health: http://localhost:8000/health"

# Metrics
echo "Metrics: http://localhost:8000/metrics"
```

## 🔧 Configuration Guide

### Configuring Kibana Dashboards

1. **Access Kibana**: Open http://localhost:5601
2. **Create Index Patterns**:
   ```
   Go to "Stack Management" → "Index Patterns" → "Create Index Pattern"

   Create these patterns:
   - security-* (for all security logs)
   - security-auth-logs-* (for authentication events)
   - security-network-logs-* (for network events)
   - security-alerts-* (for threat alerts)
   ```

3. **Import Dashboards**:
   ```bash
   # If dashboard files exist in kibana/ directory
   # Import them through Kibana UI:
   # "Stack Management" → "Saved Objects" → "Import"
   ```

### Configuring Slack Alerts

1. **Create Slack Webhook**:
   - Go to https://api.slack.com/apps
   - Create new app → Incoming Webhooks
   - Copy the webhook URL

2. **Update .env File**:
   ```bash
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

3. **Test Alerts**:
   ```bash
   curl -X POST "http://localhost:8000/api/v1/security/alerts/test"
   ```

### Configuring Email Alerts

1. **Set up SMTP** (Gmail example):
   ```bash
   SMTP_SERVER=smtp.gmail.com
   SMTP_PORT=587
   EMAIL_USER=your-email@gmail.com
   EMAIL_PASSWORD=your-app-password  # Use app password, not regular password
   ```

2. **Test Email Alerts**:
   ```bash
   curl -X POST "http://localhost:8000/api/v1/security/alerts/test"
   ```

## 🛠️ Troubleshooting Common Issues

### Issue 1: Services Won't Start

#### Problem: Docker Compose fails to start
```
Error: "Cannot connect to the Docker daemon"
```

#### Solutions:
```bash
# Check if Docker is running
sudo systemctl status docker

# If not running, start Docker
sudo systemctl start docker

# Add your user to docker group (if not done during install)
sudo usermod -aG docker $USER
# Logout and login again
```

#### Problem: Port conflicts
```
Error: "Port 9200 is already in use"
```

#### Solutions:
```bash
# Check what's using the port
sudo netstat -tulpn | grep :9200

# Option 1: Stop conflicting service
sudo systemctl stop elasticsearch  # If system Elasticsearch is running

# Option 2: Change ports in docker-compose.yml
# Edit docker-compose.yml and change "9200:9200" to "9201:9200"
```

### Issue 2: Elasticsearch Won't Start

#### Problem: Elasticsearch container keeps restarting
```bash
# Check logs
docker-compose logs elasticsearch
```

#### Common causes and solutions:

1. **Memory Issues**:
   ```bash
   # Increase virtual memory
   sudo sysctl -w vm.max_map_count=262144

   # Make permanent
   echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
   ```

2. **Disk Space Issues**:
   ```bash
   # Check disk space
   df -h

   # Clean Docker if needed
   docker system prune -a
   ```

3. **Permission Issues**:
   ```bash
   # Fix Elasticsearch data permissions
   sudo chown -R 1000:1000 elasticsearch_data/
   ```

### Issue 3: Application Can't Connect to Database

#### Problem: FastAPI returns database errors
```bash
# Check logs
docker-compose logs app
```

#### Solutions:

1. **Database Not Ready**:
   ```bash
   # Wait for PostgreSQL to fully start
   docker-compose logs db

   # Look for: "database system is ready to accept connections"
   # This can take 30-60 seconds
   ```

2. **Wrong Credentials**:
   ```bash
   # Check .env file matches docker-compose.yml
   cat .env | grep POSTGRES
   cat docker-compose.yml | grep POSTGRES -A 2 -B 2
   ```

3. **Connection Issues**:
   ```bash
   # Test database connection manually
   docker-compose exec app python -c "
   from app.database import engine
   try:
       engine.connect()
       print('Database connection successful!')
   except Exception as e:
       print(f'Database connection failed: {e}')
   "
   ```

### Issue 4: Kibana Shows No Data

#### Problem: Dashboards are empty, no indices visible

#### Solutions:

1. **Check if data is being generated**:
   ```bash
   # Check if indices exist
   curl "http://localhost:9200/_cat/indices?v"

   # If empty, check if Logstash is processing data
   curl "http://localhost:9600/_node/stats/pipelines"
   ```

2. **Generate test data**:
   ```bash
   # Create a user and generate some activity
   curl -X POST "http://localhost:8000/api/v1/users/register" \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","username":"testuser","password":"testpass123"}'

   # Try logging in with wrong password (generates security events)
   curl -X POST "http://localhost:8000/api/v1/users/login" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "username=test@example.com&password=wrongpassword"
   ```

3. **Check index patterns in Kibana**:
   ```
   1. Go to http://localhost:5601
   2. Menu → Stack Management → Index Patterns
   3. Click "Create index pattern"
   4. Enter "security-*" as the pattern
   5. Select "@timestamp" as the time field
   ```

### Issue 5: Alerts Not Working

#### Problem: Not receiving security alerts

#### Solutions:

1. **Test the threat detection system**:
   ```bash
   # Test brute force detection
   curl "http://localhost:8000/api/v1/security/threats/brute-force"

   # Test alert system
   curl -X POST "http://localhost:8000/api/v1/security/alerts/test"
   ```

2. **Check Slack configuration**:
   ```bash
   # Verify webhook URL in .env
   grep SLACK_WEBHOOK_URL .env

   # Test webhook manually
   curl -X POST -H 'Content-type: application/json' \
     --data '{"text":"Test from Advanced Threat Detection System"}' \
     YOUR_SLACK_WEBHOOK_URL
   ```

3. **Check email configuration**:
   ```bash
   # Verify SMTP settings
   grep SMTP .env

   # Check app logs for email errors
   docker-compose logs app | grep -i mail
   ```

## 📊 Performance Tuning

### Optimizing for Production

#### Elasticsearch Optimization
```bash
# Increase JVM heap size (in docker-compose.yml)
environment:
  - "ES_JAVA_OPTS=-Xms1g -Xmx1g"  # Adjust based on available RAM

# For production, use at least 50% of available RAM
# Example for 16GB server:
  - "ES_JAVA_OPTS=-Xms8g -Xmx8g"
```

#### Database Optimization
```bash
# Increase PostgreSQL connection limits (in docker-compose.yml)
environment:
  POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=scram-sha-256"
command: ["postgres", "-c", "max_connections=200"]
```

#### Application Scaling
```yaml
# Scale FastAPI application (in docker-compose.yml)
app:
  # ... other config ...
  scale: 3  # Run 3 instances
```

### Monitoring Performance

#### Check Resource Usage
```bash
# Container resource usage
docker stats

# Specific service resource usage
docker stats elk-stack_elasticsearch_1

# System resource usage
htop  # or top
```

#### Check Service Performance
```bash
# Elasticsearch performance
curl "http://localhost:9200/_nodes/stats"

# Database performance
docker-compose exec db psql -U user -d todo_db -c "
SELECT schemaname,tablename,attname,n_distinct,correlation
FROM pg_stats WHERE tablename='users' OR tablename='todos';"

# Redis performance
docker-compose exec redis redis-cli info stats
```

## 🔐 Security Hardening

### Production Security Checklist

1. **Change Default Passwords**:
   ```bash
   # Generate secure passwords
   openssl rand -base64 32  # For SECRET_KEY
   openssl rand -base64 16  # For database passwords
   ```

2. **Enable HTTPS**:
   ```yaml
   # Add SSL termination (nginx example)
   nginx:
     image: nginx:alpine
     ports:
       - "443:443"
     volumes:
       - ./nginx/nginx.conf:/etc/nginx/nginx.conf
       - ./ssl/:/etc/ssl/
   ```

3. **Restrict Network Access**:
   ```yaml
   # In docker-compose.yml, remove public port bindings for internal services
   elasticsearch:
     # ports:
     #   - "9200:9200"  # Remove this for production
     expose:
       - "9200"  # Internal access only
   ```

4. **Enable Elasticsearch Security**:
   ```yaml
   elasticsearch:
     environment:
       - xpack.security.enabled=true
       - ELASTIC_PASSWORD=your-secure-password
   ```

## 🆘 Emergency Procedures

### Complete System Reset
```bash
# Stop all services
docker-compose down

# Remove all data (WARNING: This deletes everything!)
docker-compose down -v
docker system prune -a

# Start fresh
docker-compose up -d
```

### Backup Procedures
```bash
# Backup PostgreSQL
docker-compose exec db pg_dump -U user todo_db > backup_$(date +%Y%m%d).sql

# Backup Elasticsearch
curl -X PUT "localhost:9200/_snapshot/backup_repo" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/usr/share/elasticsearch/backup"
  }
}'
```

### Recovery Procedures
```bash
# Restore PostgreSQL
docker-compose exec db psql -U user todo_db < backup_20240115.sql

# Restore Elasticsearch
curl -X POST "localhost:9200/_snapshot/backup_repo/snapshot_1/_restore"
```

## 📞 Getting Support

### Log Collection for Support
```bash
# Collect all logs
mkdir support_logs_$(date +%Y%m%d)
cd support_logs_$(date +%Y%m%d)

# Service logs
docker-compose logs --no-color app > app.log
docker-compose logs --no-color db > db.log
docker-compose logs --no-color redis > redis.log
docker-compose logs --no-color elasticsearch > elasticsearch.log
docker-compose logs --no-color logstash > logstash.log
docker-compose logs --no-color kibana > kibana.log

# System info
docker-compose ps > services_status.txt
docker stats --no-stream > resource_usage.txt
df -h > disk_space.txt
free -h > memory_usage.txt

# Configuration
cp ../.env environment_config.txt
cp ../docker-compose.yml docker_config.yml

echo "Support logs collected in: $(pwd)"
```

### Health Check Script
```bash
#!/bin/bash
# Save as health_check.sh

echo "=== Advanced Threat Detection System Health Check ==="
echo

echo "1. Docker Services:"
docker-compose ps
echo

echo "2. Elasticsearch Health:"
curl -s http://localhost:9200/_cluster/health | jq '.'
echo

echo "3. Application Health:"
curl -s http://localhost:8000/health | jq '.'
echo

echo "4. Kibana Status:"
curl -s http://localhost:5601/api/status | head -5
echo

echo "5. System Resources:"
df -h | head -5
free -h
echo

echo "Health check complete!"
```

Run with: `chmod +x health_check.sh && ./health_check.sh`

This troubleshooting guide should help you resolve most common issues and get the Advanced Threat Detection System running smoothly in any environment.