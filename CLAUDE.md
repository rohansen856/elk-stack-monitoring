# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **Sentinel**, an Advanced Threat Detection System - an enterprise-grade security monitoring platform combining todo management with real-time threat detection capabilities powered by the ELK Stack (Elasticsearch, Logstash, Kibana). The system detects APT (Advanced Persistent Threat) activities, brute force attacks, data exfiltration, and PowerShell attacks through structured log analysis and correlation.

## Architecture

### Multi-Service Docker Architecture

The application runs as a multi-container Docker Compose stack with the following service dependencies:

1. **Backend (FastAPI)** - Python API server at port 8000
   - Depends on: PostgreSQL, Redis, Elasticsearch, Logstash
   - Auto-runs database migrations via dedicated `migrate` service before starting

2. **Frontend (Next.js 16)** - TypeScript dashboard at port 3000
   - Depends on: Backend API

3. **Database Layer**
   - PostgreSQL (port 5432) - User data and todos
   - Redis (port 6379) - Caching layer

4. **ELK Stack**
   - Elasticsearch (ports 9200, 9300) - Security event storage and search
   - Logstash (ports 5044, 5000, 9600, 514, 12201) - Log processing and threat enrichment
   - Kibana (port 5601) - Security dashboards and visualizations
   - Filebeat - Log file shipping
   - Metricbeat - System metrics collection

### Backend Architecture (Python/FastAPI)

- **app/main.py** - Application entry point with router registration and middleware setup
- **app/api/** - API route handlers (auth.py, users.py, todos.py, security.py)
- **app/services/** - Business logic layer:
  - `threat_detection.py` - Core security analysis (brute force, data exfiltration, PowerShell attacks, APT correlation)
  - `security_logger.py` - Structured logging to ELK Stack
  - `alerting.py` - Security alerting system
  - `email_service.py` - Password reset functionality
- **app/crud/** - Database CRUD operations
- **app/models/** - SQLAlchemy ORM models (User, Todo, PasswordResetToken)
- **app/schemas/** - Pydantic request/response models
- **app/middleware.py** - Logging, CORS, and metrics middleware
- **app/cache.py** - Redis caching wrapper
- **app/config.py** - Settings loaded from environment variables via pydantic-settings
- **alembic/** - Database migration management

### Frontend Architecture (Next.js 16/TypeScript)

- **website/app/** - App Router pages (dashboard, login, register, forgot-password)
- **website/components/** - Reusable UI components (shadcn/ui)
- **website/lib/** - Utility functions and API clients
- **website/hooks/** - Custom React hooks
- **website/styles/** - Global styles and Tailwind config
- Uses Zustand for state management, React Hook Form for forms, and date-fns for dates

### Security Indices in Elasticsearch

The threat detection service searches across multiple index patterns:
- `security-auth-logs-*` - Authentication events
- `security-network-logs-*` - Network security events
- `security-audit-logs-*` - File access events
- `security-alerts-*` - Generated security alerts
- `windows-security-logs-*` - Windows event logs
- General `security-*` pattern for aggregated searches

## Development Commands

### Full Stack Development

**Recommended: Use the automated startup script**
```bash
# Start all services with automatic ELK setup (RECOMMENDED)
./local-startup.sh

# This script automatically:
# - Starts all services
# - Waits for Elasticsearch
# - Verifies setup-elk completed
# - Force-sets Kibana password (ensures auth works)
# - Restarts Kibana
# - Shows service status and access URLs
```

**Manual startup (if you prefer)**
```bash
# Start all services (includes automatic database migration)
docker-compose up -d

# IMPORTANT: If you see Kibana authentication errors, run this:
docker compose exec -T elasticsearch curl -X POST -s -u "elastic:$ELASTICSEARCH_PASSWORD" \
  "http://localhost:9200/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" -d '{"password":"$KIBANA_SYSTEM_PASSWORD"}'
docker compose restart kibana

# View logs for all services
docker-compose logs -f

# View logs for specific service
docker-compose logs -f app
docker-compose logs -f frontend
docker-compose logs -f elasticsearch

# Stop all services
docker-compose down

# Stop and remove volumes (fresh start)
docker-compose down -v

# Check service status
docker-compose ps
```

### Backend Development (Python)

```bash
# Manual setup (if not using Docker)
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Database migrations (inside Docker container)
docker compose exec app alembic revision --autogenerate -m "Description of changes"
docker compose exec app alembic upgrade head

# Database migrations (local development)
alembic revision --autogenerate -m "Description of changes"
alembic upgrade head

# Run backend server (development mode with auto-reload)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Run tests
pytest
pytest --cov=app --cov-report=html
pytest tests/test_auth.py
pytest tests/test_security.py

# Code quality
black app/ tests/
flake8 app/ tests/
mypy app/
```

### Frontend Development (Next.js)

```bash
cd website

# Install dependencies
npm install

# Run development server
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Lint
npm run lint
```

### Health Checks

```bash
# Backend health
curl http://localhost:8000/health

# Elasticsearch cluster health
curl http://localhost:9200/_cluster/health

# Logstash stats
curl http://localhost:9600/_node/stats

# Kibana status
curl http://localhost:5601/api/status
```

### ELK Stack Operations

```bash
# Check Elasticsearch indices
curl "localhost:9200/_cat/indices?v"

# Test Logstash TCP input (port 5000)
echo '{"message": "test"}' | nc localhost 5000

# Check index health and optimize
curl -X POST "localhost:9200/_optimize"
```

## Configuration

### Environment Variables

Both `.env` (backend) and `website/.env` (frontend) must be configured:

**Backend (.env)**:
- Database: `DATABASE_URL`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
- Redis: `REDIS_URL`
- JWT: `SECRET_KEY`, `ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES`
- ELK: `ELASTICSEARCH_URL`, `ELASTICSEARCH_HOST`, `LOGSTASH_HOST`, etc.
- Email: `EMAIL_SMTP_SERVER`, `EMAIL_SMTP_USERNAME`, `EMAIL_SMTP_PASSWORD` (for password reset)
- App: `ENVIRONMENT` (development/production), `LOG_LEVEL`

**Frontend (website/.env)**:
- API endpoint and other Next.js specific config

Copy from `.env.example` and `website/.env.example` to get started.

## Database Schema

### Users Table
- `id`, `email` (unique), `username` (unique), `hashed_password`
- `is_active`, `created_at`, `updated_at`

### Todos Table
- `id`, `title`, `description`, `completed`
- `priority` (enum: low/medium/high), `due_date`
- `owner_id` (FK to Users), `created_at`, `updated_at`

### PasswordResetToken Table
- Token-based password reset with expiration

## Key API Endpoints

### Authentication
- `POST /api/v1/users/register` - User registration
- `POST /api/v1/users/login` - Login (returns JWT token)
- `GET /api/v1/users/me` - Current user info

### Todos
- `GET /api/v1/todos/` - List todos (supports filters: completed, priority, search)
- `POST /api/v1/todos/` - Create todo
- `PUT /api/v1/todos/{id}` - Update todo
- `DELETE /api/v1/todos/{id}` - Delete todo
- `GET /api/v1/todos/stats/summary` - Todo statistics

### Security Monitoring
- `GET /api/v1/security/threats/brute-force` - Detect brute force attacks
- `GET /api/v1/security/threats/data-exfiltration` - Detect data exfiltration
- `GET /api/v1/security/threats/powershell` - Detect suspicious PowerShell activity
- `GET /api/v1/security/threats/apt-correlation` - APT kill-chain correlation
- `GET /api/v1/security/threats/scan` - Comprehensive threat scan
- `GET /api/v1/security/hunt/*` - Various threat hunting endpoints

### System
- `GET /health` - Health check (database, redis, elasticsearch)
- `GET /metrics` - Prometheus metrics
- `GET /docs` - API documentation (disabled in production)

## Testing & Simulation

The `scripts/apt-simulations-test/` directory contains sample APT simulation scripts for testing threat detection capabilities. These can be used to verify that the security monitoring pipeline is working correctly.

## Documentation

Comprehensive documentation is available in the `docs/` directory and deployed via MkDocs:
- System architecture and component interactions
- Detailed ELK stack configuration
- Kubernetes deployment guides
- API documentation and database schema
- Kibana alerting rules for APT detection

Build docs: Configure mkdocs according to `mkdocs.yaml`

## Important Notes

### Migration Handling
Database migrations run automatically via the `migrate` service in Docker Compose when migration files exist in `alembic/versions/`. The backend `app` service depends on successful migration completion before starting.

**Initial Setup**: If starting fresh or if the `alembic/versions/` directory is empty, you must create the initial migration:
```bash
# Create initial migration (generates migration file)
docker compose exec app alembic revision --autogenerate -m "Initial migration"

# Apply migrations
docker compose exec app alembic upgrade head
```

**Important**: All model classes referenced in `app/models/` must be imported in `alembic/env.py` for alembic to detect schema changes. Currently imported: User, Todo, PasswordResetToken.

### ELK Stack Configuration
Logstash pipeline configurations are in `logstash/pipeline/` and must be volume-mounted as read-only. These define the log parsing, enrichment, and routing logic.

### Automated ELK Stack Setup
The `setup-elk` service in docker-compose.yml automatically handles all ELK Stack initialization:

**What it does:**
1. Waits for Elasticsearch to be healthy
2. Sets the `kibana_system` password in Elasticsearch
3. Creates Filebeat index template for log collection
4. Creates Metricbeat index template for metric collection
5. Ensures all components can connect without errors

**How it works:**
- Runs after Elasticsearch is healthy (before Kibana and Beats start)
- Uses the `ELASTIC_PASSWORD` and `KIBANA_SYSTEM_PASSWORD` environment variables
- Creates necessary index templates to prevent data stream errors
- All services depend on successful completion of this setup

**Configuration:**
- Set `KIBANA_SYSTEM_PASSWORD` in `.env` (required - there is no default)
- Set `ELASTIC_PASSWORD` in `.env` (required - there is no default; the stack refuses to start without it)
- Both are also defined in `.env.example` for reference

**Benefits:**
- ✅ No manual password resets needed when recreating containers
- ✅ No Kibana authentication failures
- ✅ No Filebeat/Metricbeat template errors
- ✅ Consistent authentication across stack restarts
- ✅ Automatic synchronization between all ELK components

**What's automated:**
- Kibana system user password configuration
- Filebeat index templates (`filebeat-*`, `security-logs*`)
- Metricbeat index templates (`metricbeat-*`)

**Troubleshooting:**
Check the setup service logs to see what was configured:
```bash
docker compose logs setup-elk
```

Expected output:
```
=== ELK Stack Setup ===
✓ Elasticsearch ready
Setting kibana_system password...
✓ kibana_system password set
Setting up Filebeat index template...
✓ Filebeat template created
Setting up Metricbeat index template...
✓ Metricbeat template created
=== Setup complete ===
```

If setup fails, manually verify Elasticsearch access:
```bash
# Check Elasticsearch health
curl -u "elastic:$ELASTICSEARCH_PASSWORD" http://localhost:9200/_cluster/health

# Check if kibana_system user exists
curl -u "elastic:$ELASTICSEARCH_PASSWORD" http://localhost:9200/_security/user/kibana_system
```

### Security Context
This is a security monitoring application. When modifying threat detection logic in `app/services/threat_detection.py`, ensure:
- Risk scoring remains consistent (1-10 scale)
- Elasticsearch queries use proper time windows
- Detection patterns align with actual threat indicators
- New detections are logged appropriately

### Production Configuration

**Environment Setup:**
1. Copy `.env.production.example` to `.env` and configure all values
2. Generate a strong SECRET_KEY: `openssl rand -hex 64`
3. Update all passwords (database, email, etc.)
4. Set `ENVIRONMENT=production` to disable API docs
5. Configure email SMTP for password reset functionality

**Security Features Configured:**
- **Rate Limiting**:
  - API endpoints: 10 req/s, burst 20
  - Auth endpoints (login/register): 5 req/s, burst 5
  - General: 20 req/s
- **Security Headers**: X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, CSP
- **Kibana CSP**: Strict mode enabled, telemetry disabled
- **Next.js Optimizations**: Console removal in production, SWC minification, static asset caching
- **Server Hardening**: Server tokens hidden, compression enabled

**Production Checklist:**
- [ ] Strong SECRET_KEY (64+ characters) configured
- [ ] All default passwords changed
- [ ] Email SMTP credentials configured
- [ ] CORS restricted to actual domain
- [ ] HTTPS/TLS enabled (AWS ALB + ACM or Let's Encrypt)
- [ ] Elasticsearch security enabled (xpack.security.enabled=true)
- [ ] Log rotation configured
- [ ] Automated backups for PostgreSQL and Elasticsearch
- [ ] Monitoring and alerting configured
- [ ] Firewall rules restricted to ports 80/443
- [ ] ES_JAVA_OPTS adjusted for production memory (recommended: -Xms2g -Xmx2g)

## AWS Deployment with Nginx Reverse Proxy

The application uses **Nginx as a reverse proxy** to route all traffic through port 80, making it suitable for AWS EC2 deployment with minimal security group configuration.

### Architecture

```
Internet (Port 80) → Nginx → {
    /              → Redirects to /frontend
    /frontend      → Frontend Dashboard (3000)
    /backend       → Backend API (8000)
    /monitoring    → Kibana Dashboard (5601)
}
```

**Key Points:**
- Only **port 80** is exposed publicly via Nginx
- All other services (frontend:3000, backend:8000, kibana:5601) are **internal only** (using `expose` instead of `ports` in docker-compose)
- Database services (PostgreSQL, Redis, Elasticsearch) remain **completely private**

### AWS EC2 Setup

#### 1. Security Group Configuration

Configure your EC2 instance security group with **minimal open ports**:

| Type | Protocol | Port Range | Source      | Description                    |
|------|----------|------------|-------------|--------------------------------|
| HTTP | TCP      | 80         | 0.0.0.0/0   | Public web access via Nginx    |
| SSH  | TCP      | 22         | Your IP     | SSH access (restrict to your IP)|

**Important:** Do NOT open ports 3000, 5601, 8000, 9200, 5432, 6379 - these should remain internal.

#### 2. Deployment Steps

**Option A: Automated Setup (Recommended)**

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ec2-user@your-ec2-ip

# Install Docker and Docker Compose
sudo yum update -y
sudo yum install -y docker git
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Clone repository
git clone https://github.com/rohansen856/elk-stack-monitoring.git
cd elk-stack-monitoring

# Run automated setup script
# This will automatically detect EC2 IP, configure .env files, and build containers
chmod +x aws-ec2-setup.sh
./aws-ec2-setup.sh
```

**Option B: Manual Setup**

```bash
# After cloning the repository and installing Docker/Docker Compose:

# Configure environment
cp .env.example .env
cp website/.env.example website/.env

# IMPORTANT: Update website/.env with your EC2 public IP
# Replace: NEXT_PUBLIC_APP_URL=http://localhost/frontend
# With:    NEXT_PUBLIC_APP_URL=http://YOUR_EC2_IP/frontend
nano website/.env

# Build and start services (MUST rebuild frontend after changing .env)
docker compose build --no-cache
docker compose up -d

# Check status
docker compose ps
docker compose logs -f nginx
```

**⚠️ Important:** If you copied `.env` files BEFORE building, or if the frontend shows issues, you MUST rebuild:

```bash
docker compose down
docker compose build frontend --no-cache
docker compose up -d
```

**Troubleshooting:** See [AWS_EC2_TROUBLESHOOTING.md](AWS_EC2_TROUBLESHOOTING.md) for common issues and fixes.

#### 3. Access Your Application

Replace `YOUR_EC2_PUBLIC_IP` with your actual EC2 public IP or domain:

- **Frontend Dashboard**: `http://YOUR_EC2_PUBLIC_IP/frontend`
- **Backend API**: `http://YOUR_EC2_PUBLIC_IP/backend/api/v1/...`
- **Backend Health Check**: `http://YOUR_EC2_PUBLIC_IP/backend/health`
- **Backend API Documentation**: `http://YOUR_EC2_PUBLIC_IP/backend/docs` (if ENVIRONMENT=development)
- **Kibana Dashboard**: `http://YOUR_EC2_PUBLIC_IP/monitoring/`
- **Backend Metrics**: `http://YOUR_EC2_PUBLIC_IP/backend/metrics`

#### 4. Verify Nginx Routing

```bash
# Test nginx health
curl http://localhost/nginx-health

# Test frontend
curl http://localhost/frontend

# Test backend health
curl http://localhost/backend/health

# Test backend API
curl http://localhost/backend/api/v1/users/me

# Test Kibana (should return 302 redirect)
curl -I http://localhost/monitoring/

# View nginx logs
docker-compose logs nginx

# Test from outside (replace with your IP)
curl http://YOUR_EC2_PUBLIC_IP/backend/health
```

### Frontend API Configuration

The frontend needs to call the backend API. Update `website/.env`:

```env
NEXT_PUBLIC_API_URL=http://YOUR_EC2_PUBLIC_IP/backend
```

Or use relative URLs (`/backend`) since everything is on the same domain through Nginx.

### Production Hardening

The application includes production-ready configurations out of the box:

**✅ Already Configured:**
- ✅ Rate limiting (API: 10r/s, Auth: 5r/s with burst protection)
- ✅ Security headers (X-Frame-Options, CSP, HSTS, etc.)
- ✅ Server hardening (tokens hidden, compression enabled)
- ✅ Kibana CSP strict mode
- ✅ Next.js production optimizations (minification, console removal)
- ✅ Static asset caching (31536000s for immutable assets)

**Additional Steps for AWS Production:**

1. **Enable HTTPS** (Required):
   ```bash
   # Option 1: AWS Application Load Balancer + Certificate Manager
   # - Create ALB in AWS Console
   # - Add SSL certificate from ACM
   # - Configure target group pointing to EC2:80

   # Option 2: Let's Encrypt with Certbot
   sudo apt install certbot python3-certbot-nginx
   sudo certbot --nginx -d yourdomain.com
   ```

2. **Restrict Kibana Access**:
   ```nginx
   # Add to nginx.conf /monitoring location
   allow YOUR_IP_ADDRESS;
   deny all;
   ```

3. **Enable Elasticsearch Security**:
   ```yaml
   # In docker-compose.yml for elasticsearch service
   environment:
     - xpack.security.enabled=true
     - ELASTIC_PASSWORD=your_secure_password
   ```

4. **Use AWS Secrets Manager**:
   ```bash
   # Store secrets in AWS Secrets Manager
   aws secretsmanager create-secret --name sentinel/prod/db-password --secret-string "your_db_password"

   # Retrieve in startup script
   export POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value --secret-id sentinel/prod/db-password --query SecretString --output text)
   ```

5. **Configure CloudWatch Logging**:
   ```bash
   # Install CloudWatch agent
   wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
   sudo dpkg -i amazon-cloudwatch-agent.deb

   # Forward Docker logs
   docker-compose logs -f | aws logs put-log-events --log-group-name /sentinel/app
   ```

6. **Set up Automated Backups**:
   ```bash
   # PostgreSQL backup script
   docker compose exec db pg_dump -U user todo_db > backup_$(date +%Y%m%d).sql
   aws s3 cp backup_$(date +%Y%m%d).sql s3://your-backup-bucket/

   # Elasticsearch snapshot
   curl -X PUT "localhost:9200/_snapshot/my_backup" -H 'Content-Type: application/json' -d'
   {
     "type": "fs",
     "settings": {
       "location": "/usr/share/elasticsearch/backups"
     }
   }'
   ```

### Nginx Configuration

The production-ready Nginx configuration at [nginx/nginx.conf](nginx/nginx.conf) includes:
- **Rate limiting**: 3 zones (api_limit, auth_limit, general_limit)
- **Security headers**: X-Frame-Options, CSP, HSTS, X-Content-Type-Options
- **WebSocket support**: For Next.js hot reload and Kibana
- **CORS headers**: Configured for API requests
- **Proxy headers**: Real IP tracking (X-Real-IP, X-Forwarded-For)
- **Gzip compression**: For text/json/javascript/css files
- **Custom buffers**: Large request handling (100M max body size)
- **Health check**: Dedicated endpoint at `/nginx-health`
- **Server hardening**: Tokens hidden, optimized worker connections

### Troubleshooting AWS Deployment

```bash
# Check if nginx is running
docker-compose ps nginx

# View nginx error logs
docker-compose logs nginx --tail 100

# Test internal connectivity
docker-compose exec nginx wget -O- http://frontend:3000
docker-compose exec nginx wget -O- http://app:8000/health
docker-compose exec nginx wget -O- http://kibana:5601

# Test nginx routing
curl http://localhost/frontend
curl http://localhost/backend/health
curl http://localhost/monitoring/

# Restart nginx only
docker-compose restart nginx

# Check EC2 security group
# Ensure port 80 is open to 0.0.0.0/0
```
