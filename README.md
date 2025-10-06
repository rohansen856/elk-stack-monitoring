# Advanced Threat Detection System with ELK Stack

A comprehensive security monitoring solution built with FastAPI, PostgreSQL, Redis, and an integrated ELK (Elasticsearch, Logstash, Kibana) stack for advanced persistent threat (APT) detection and real-time security monitoring.

## Features

### 🛡️ Security Monitoring & Threat Detection
- **Real-time APT Detection**: Advanced persistent threat monitoring using machine learning patterns
- **Brute Force Detection**: Automated detection of credential stuffing and brute force attacks
- **Data Exfiltration Monitoring**: Detection of unusual outbound data transfers
- **PowerShell Attack Detection**: Monitoring for suspicious PowerShell command execution
- **Cross-system Correlation**: APT kill-chain correlation across multiple data sources
- **Risk Scoring**: Automated threat severity assessment (1-10 scale)
- **Real-time Alerting**: Slack, email, and system notifications for security incidents

### 📊 ELK Stack Integration
- **Elasticsearch**: Distributed search and analytics for log data
- **Logstash**: Real-time log processing and enrichment pipeline
- **Kibana**: Interactive dashboards and security visualizations
- **Filebeat**: System and application log collection
- **Metricbeat**: System metrics and performance monitoring
- **Winlogbeat**: Windows Event Log collection for hybrid environments

### 🔐 Application Security
- **Authentication & Authorization**: JWT-based authentication with secure password hashing
- **CRUD Operations**: Full create, read, update, delete operations for todos
- **Filtering & Search**: Filter todos by completion status, priority, and search in title/description
- **Caching**: Redis-based caching for improved performance
- **Database**: PostgreSQL with SQLAlchemy ORM and Alembic migrations
- **Monitoring**: Prometheus metrics and structured logging
- **Error Handling**: Comprehensive error handling with detailed logging
- **Testing**: Complete test suite with pytest
- **Docker**: Containerized deployment with Docker Compose
- **Documentation**: Auto-generated API documentation with FastAPI

## Tech Stack

### 🛡️ Security & Monitoring
- **Elasticsearch**: 8.11.0 - Search and analytics engine
- **Logstash**: 8.11.0 - Log processing pipeline
- **Kibana**: 8.11.0 - Data visualization and dashboards
- **Filebeat**: 8.11.0 - Log shipping agent
- **Metricbeat**: 8.11.0 - System metrics collection
- **Winlogbeat**: 8.11.0 - Windows Event Log collection

### 🚀 Application Framework
- **Framework**: FastAPI
- **Database**: PostgreSQL
- **Cache**: Redis
- **ORM**: SQLAlchemy
- **Migration**: Alembic
- **Authentication**: JWT with python-jose
- **Password Hashing**: bcrypt
- **Logging**: structlog
- **Monitoring**: Prometheus
- **Testing**: pytest
- **Containerization**: Docker & Docker Compose

## Quick Start

### Using Docker Compose (Recommended)

1. Clone the repository:
```bash
git clone https://github.com/rohansen856/elk-stack-monitoring
cd elk-stack-monitoring
```

2. Copy environment variables:
```bash
cp .env.example .env
```

3. Start the services:
```bash
docker-compose up -d
```

4. Run database migrations:
```bash
docker-compose exec app alembic upgrade head
```

The API will be available at `http://localhost:8000`

### Manual Setup

1. Create and activate virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Set up environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. Start PostgreSQL and Redis services

5. Run database migrations:
```bash
alembic upgrade head
```

6. Start the application:
```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## API Endpoints

### Authentication

- `POST /api/v1/users/register` - Register a new user
- `POST /api/v1/users/login` - Login user
- `GET /api/v1/users/me` - Get current user info

### Todos

- `GET /api/v1/todos/` - List todos with optional filters
- `POST /api/v1/todos/` - Create a new todo
- `GET /api/v1/todos/{id}` - Get a specific todo
- `PUT /api/v1/todos/{id}` - Update a todo
- `DELETE /api/v1/todos/{id}` - Delete a todo
- `GET /api/v1/todos/stats/summary` - Get todo statistics

### System

- `GET /health` - Health check endpoint
- `GET /metrics` - Prometheus metrics
- `GET /docs` - Interactive API documentation (development only)

### Security & Monitoring

- `GET /api/v1/security/threats/brute-force` - Detect brute force attacks
- `GET /api/v1/security/threats/data-exfiltration` - Detect data exfiltration attempts
- `GET /api/v1/security/threats/powershell` - Detect suspicious PowerShell activity
- `GET /api/v1/security/threats/apt-correlation` - APT kill-chain correlation analysis
- `POST /api/v1/security/alerts/test` - Test security alerting system

## API Usage Examples

### Register a new user
```bash
curl -X POST "http://localhost:8000/api/v1/users/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "username": "testuser",
    "password": "securepassword123"
  }'
```

### Login
```bash
curl -X POST "http://localhost:8000/api/v1/users/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=user@example.com&password=securepassword123"
```

### Create a todo
```bash
curl -X POST "http://localhost:8000/api/v1/todos/" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Buy groceries",
    "description": "Milk, bread, and eggs",
    "priority": "medium",
    "due_date": "2024-12-31T10:00:00"
  }'
```

### Get todos with filters
```bash
curl "http://localhost:8000/api/v1/todos/?completed=false&priority=high&search=urgent" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | Required |
| `REDIS_URL` | Redis connection string | Required |
| `SECRET_KEY` | JWT secret key | Required |
| `ALGORITHM` | JWT algorithm | HS256 |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Token expiration time | 30 |
| `ENVIRONMENT` | Environment (development/production) | development |
| `LOG_LEVEL` | Logging level | INFO |

## Database Schema

### Users Table
- `id` (Primary Key)
- `email` (Unique)
- `username` (Unique)
- `hashed_password`
- `is_active`
- `created_at`
- `updated_at`

### Todos Table
- `id` (Primary Key)
- `title`
- `description`
- `completed`
- `priority` (low, medium, high)
- `due_date`
- `created_at`
- `updated_at`
- `owner_id` (Foreign Key to Users)

## Testing

Run the test suite:
```bash
pytest
```

Run tests with coverage:
```bash
pytest --cov=app --cov-report=html
```

## Development

### Database Migrations

Create a new migration:
```bash
alembic revision --autogenerate -m "Description of changes"
```

Apply migrations:
```bash
alembic upgrade head
```

### Code Quality

Format code:
```bash
black app/ tests/
```

Lint code:
```bash
flake8 app/ tests/
```

Type checking:
```bash
mypy app/
```

## Monitoring

### Metrics

The application exposes Prometheus metrics at `/metrics` including:
- Request count by method, endpoint, and status
- Request duration histograms
- Custom application metrics

### Logging

Structured logging with the following fields:
- `timestamp`
- `level`
- `message`
- `request_id`
- `user_id` (when applicable)
- Additional context fields

### Health Check

The `/health` endpoint returns:
```json
{
  "status": "healthy",
  "database": "ok",
  "redis": "ok"
}
```

## Production Deployment

### Security Considerations

1. Use strong, unique `SECRET_KEY`
2. Enable HTTPS in production
3. Set up proper CORS policies
4. Use environment-specific database credentials
5. Enable rate limiting
6. Set up proper logging and monitoring

### Scaling

- Use multiple application instances behind a load balancer
- Scale Redis for caching
- Use read replicas for PostgreSQL
- Consider connection pooling

## 🛡️ Advanced Security Monitoring with ELK Stack

This project features a comprehensive security monitoring solution built on the ELK stack, specifically designed for Advanced Persistent Threat (APT) detection and real-time security analytics.

### 🔍 Elasticsearch - Security Data Lake
- **Port**: 9200
- **Purpose**: Distributed search and analytics engine for security logs
- **Indices**: Specialized security indices (`security-*`, `windows-security-*`, `security-alerts-*`)
- **Health Check**: `http://localhost:9200/_cluster/health`
- **Features**: GeoIP enrichment, risk scoring, automated threat detection

### ⚚️ Logstash - Security Log Processing
- **Ports**:
  - 5044 (Beats input - Filebeat, Metricbeat, Winlogbeat)
  - 5000 (TCP input for application logs)
  - 9600 (API/Monitoring)
  - 514 (Syslog UDP/TCP for network devices)
  - 12201 (GELF for Docker logs)
- **Purpose**: Real-time log processing, enrichment, and threat detection
- **Configuration**: `./logstash/pipeline/logstash.conf`
- **Security Features**: Automatic risk scoring, GeoIP lookups, threat correlation

### 📊 Kibana - Security Operations Center
- **Port**: 5601
- **Purpose**: Security dashboards and threat visualization
- **Access**: `http://localhost:5601`
- **Dashboards**: APT detection, geographic threat maps, security event timelines
- **Features**: Real-time alerting, investigation tools, threat hunting queries

## Configuration

### Environment Variables (.env)
```bash
# ELK Stack Configuration
ELASTICSEARCH_URL=http://elasticsearch:9200
ELASTICSEARCH_HOST=elasticsearch
ELASTICSEARCH_PORT=9200
KIBANA_HOST=kibana
KIBANA_PORT=5601
LOGSTASH_HOST=logstash
LOGSTASH_PORT=5044
LOGSTASH_TCP_PORT=5000

# Elasticsearch Settings
ES_JAVA_OPTS=-Xms512m -Xmx512m
ELASTIC_PASSWORD=changeme
KIBANA_PASSWORD=changeme
```

## Usage

### 🚀 Starting the Security Monitoring Stack
```bash
# Start all services including ELK stack and security monitoring
docker-compose up -d

# Start only ELK services
docker-compose up -d elasticsearch logstash kibana filebeat metricbeat

# Check service health
docker-compose ps
curl http://localhost:9200/_cluster/health
curl http://localhost:5601/api/status
```

### 🔍 Security Dashboard Setup
1. **Access Kibana**: Open `http://localhost:5601`
2. **Create Security Index Patterns**:
   - `security-*` for general security events
   - `security-auth-logs-*` for authentication events
   - `security-network-logs-*` for network security events
   - `security-alerts-*` for security alerts
   - `windows-security-logs-*` for Windows security events
3. **Import Security Dashboards**: Navigate to "Stack Management" > "Saved Objects"
4. **Start Threat Hunting**: Go to "Discover" for real-time security log analysis

### 🔥 Testing Threat Detection
```bash
# Test the security monitoring system
curl "http://localhost:8000/api/v1/security/threats/brute-force"
curl "http://localhost:8000/api/v1/security/threats/data-exfiltration"
curl "http://localhost:8000/api/v1/security/threats/powershell"
curl "http://localhost:8000/api/v1/security/threats/apt-correlation"

# Test alerting system
curl -X POST "http://localhost:8000/api/v1/security/alerts/test"
```

### 📊 Security Event Collection
The security monitoring system automatically collects and analyzes:

#### 🔐 Authentication & Access Logs
- Login attempts (successful/failed)
- Privilege escalation events
- Account lockouts and password changes
- Off-hours access attempts
- Geographic access anomalies

#### 🌐 Network Security Events
- Firewall blocks and allows
- Network traffic patterns
- Outbound data transfers
- Command & Control communication attempts
- Lateral movement detection

#### ⚙️ System & Process Monitoring
- Process creation and execution
- PowerShell command monitoring
- Suspicious script execution
- Service creation and modification
- Registry changes (Windows)

#### 📁 File Access & Data Protection
- Sensitive file access
- Data staging activities
- Configuration file modifications
- Unauthorized data access attempts

### 📄 Security Log Format
Security events are structured in JSON format with enhanced fields:

#### Standard Fields
- `@timestamp`: ISO timestamp
- `level`: Log level (INFO, ERROR, DEBUG, etc.)
- `logger_name`: Logger identifier
- `message`: Log message
- `service`: Service name

#### Security-Specific Fields
- `security_event`: Event type (authentication_failure, network_block, etc.)
- `src_ip`: Source IP address
- `geo.country`: Geographic location
- `risk_score`: Automated threat score (1-10)
- `user.name`: Username involved
- `process.name`: Process name
- `network.bytes_out`: Outbound data transfer
- `threat_indicators`: Array of threat indicators

## Troubleshooting

### Common Issues

1. **Services not starting**: Wait 2-3 minutes for all services to initialize
2. **Memory issues**: Adjust `ES_JAVA_OPTS` in .env for lower memory usage
3. **Connection refused**: Ensure all services are healthy with `docker-compose ps`

### Health Checks
```bash
# Check Elasticsearch
curl http://localhost:9200/_cluster/health

# Check Logstash
curl http://localhost:9600/_node/stats

# Check Kibana
curl http://localhost:5601/api/status
```

### Viewing Container Logs
```bash
# View all ELK logs
docker-compose logs -f elasticsearch logstash kibana

# View specific service logs
docker-compose logs -f elasticsearch
```

## Index Management

### Default Indices
- `todo-api-logs-YYYY.MM.DD`: Daily application logs
- `test-logs`: Test documents from integration tests

### Cleanup Old Indices
```bash
# Delete indices older than 30 days (example)
curl -X DELETE "localhost:9200/todo-api-logs-*" \
  -H "Content-Type: application/json" \
  -d '{"query":{"range":{"@timestamp":{"lt":"now-30d"}}}}'
```

## 🛡️ Threat Detection Capabilities

### 🔥 Real-time APT Detection

#### 1. Brute Force Attack Detection
- **Pattern**: Multiple failed logins (5+) followed by successful authentication
- **Time Window**: 15-minute sliding window
- **Risk Scoring**: 2x failure count (max 10)
- **Indicators**: External IP, multiple usernames, off-hours attempts

#### 2. Data Exfiltration Detection
- **Pattern**: Unusual outbound data transfers (>100MB/hour)
- **Monitoring**: Network traffic patterns and volume
- **Risk Scoring**: Based on data volume and destination
- **Alerts**: Real-time notifications for large transfers

#### 3. PowerShell Attack Detection
- **Suspicious Patterns**: Encoded commands, download strings, bypass techniques
- **Monitoring**: PowerShell execution logs and command-line parameters
- **Risk Score**: 7/10 for suspicious patterns
- **Coverage**: `Invoke-Expression`, `IEX`, `DownloadString`, `EncodedCommand`

#### 4. APT Kill-Chain Correlation
- **Cross-System Analysis**: Correlates events across multiple data sources
- **Kill-Chain Stages**: Execution → Persistence → Exfiltration
- **Risk Score**: 9/10 for confirmed kill-chain patterns
- **Response**: Automated alerting and threat hunting queries

### 📊 Risk Scoring System

| Score | Level | Response | Examples |
|-------|--------|----------|----------|
| 1-2 | **Low** | Log only | Normal login, routine processes |
| 3-4 | **Medium** | Monitor | Failed login, blocked connection |
| 5-6 | **High** | Alert | Multiple failures, privilege escalation |
| 7-8 | **Critical** | Immediate response | External admin access, suspicious scripts |
| 9-10 | **Emergency** | Incident response | Confirmed APT activity, active breach |

### 🙨 Alerting & Response

#### Alert Channels
- **Slack Integration**: Real-time threat notifications
- **Email Alerts**: Detailed threat summaries
- **Elasticsearch Alerts**: Stored for tracking and analysis
- **Dashboard Alerts**: Visual notifications in Kibana

#### Response Actions
- **Automated**: Log correlation, risk scoring, initial triage
- **Semi-Automated**: Alert generation, dashboard updates
- **Manual**: Threat investigation, incident response, remediation

## 🔒 Security Configuration

### Development Environment
- Elasticsearch security disabled for ease of development
- Default passwords in .env file (change for production)
- HTTP connections (upgrade to HTTPS for production)
- Open network access (restrict for production)

### Production Hardening
- Enable Elasticsearch security and authentication
- Configure SSL/TLS for all communications
- Set up role-based access control (RBAC)
- Implement network segmentation
- Enable audit logging
- Configure proper firewall rules
- Use strong encryption keys for Kibana saved objects

## 📊 Monitoring & Metrics

### System Health Monitoring
- **Application Metrics**: Request rates, response times, error rates
- **Infrastructure Metrics**: CPU, memory, disk usage
- **ELK Stack Health**: Cluster status, index health, ingestion rates
- **Security Metrics**: Threat detection rates, alert volumes, investigation times

### Performance Monitoring
- **Elasticsearch**: Query performance, index optimization, cluster performance
- **Logstash**: Processing rates, pipeline performance, error rates
- **Kibana**: Dashboard load times, user activity, visualization performance
- **Application**: Database connections, cache hit rates, authentication performance

### Dashboards Available
1. **Security Overview**: Real-time threat landscape
2. **Geographic Threat Map**: Attack sources by location
3. **Authentication Monitoring**: Login patterns and failures
4. **Network Security**: Traffic analysis and blocks
5. **System Performance**: Infrastructure health metrics
6. **Investigation Dashboard**: Detailed threat analysis tools

## 🚀 Getting Started Guide

### Quick Deployment
```bash
# 1. Clone the repository
git clone https://github.com/rohansen856/elk-stack-monitoring
cd elk-stack-monitoring

# 2. Configure environment
cp .env.example .env
# Edit .env with your settings

# 3. Deploy the complete security stack
docker-compose up -d

# 4. Wait for services to initialize (2-3 minutes)
docker-compose ps

# 5. Access the security dashboard
open http://localhost:5601
```

### First-Time Setup
1. **Verify ELK Health**: Check all services are running
2. **Create Index Patterns**: Set up security index patterns in Kibana
3. **Import Dashboards**: Load security visualization dashboards
4. **Configure Alerts**: Set up Slack/email notification channels
5. **Test Detection**: Run threat detection tests
6. **Review Logs**: Ensure log collection is working properly

## 🌐 Production Deployment

### Infrastructure Requirements
- **Minimum**: 8GB RAM, 4 CPU cores, 50GB storage
- **Recommended**: 16GB RAM, 8 CPU cores, 200GB SSD storage
- **Enterprise**: 32GB+ RAM, 16+ CPU cores, 1TB+ SSD storage

### Scaling Considerations
- **Elasticsearch**: Use multiple nodes for high availability
- **Logstash**: Scale horizontally for high log volumes
- **Application**: Deploy multiple instances behind load balancer
- **Storage**: Implement index lifecycle management for log retention

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for security features
5. Submit a pull request

## Support

For support, please create an issue in the repository or contact [rohansen856@gmail.com]

### Documentation
- **Security Guide**: `ENHANCED_SECURITY_SUMMARY.md`
- **API Documentation**: `http://localhost:8000/docs`
- **Threat Detection**: `/app/services/threat_detection.py`
- **Alerting System**: `/app/services/alerting.py`