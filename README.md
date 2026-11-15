# Advanced Threat Detection System

<p align="center">
  <a href="./assets/images/poster.png" target="_blank" rel="noopener">
    <img src="./assets/images/poster.png" alt="Advanced Threat Detection System poster" style="max-width:100%;height:auto;">
  </a>
</p>

*Enterprise-grade security monitoring solution with real-time threat detection*

A comprehensive cybersecurity platform that combines task management with advanced threat detection capabilities, powered by the ELK Stack (Elasticsearch, Logstash, Kibana) for real-time security monitoring and APT (Advanced Persistent Threat) detection.

## 🛡️ Key Features

### Security Monitoring
- **Real-time Threat Detection** - Automated detection of brute force attacks, data exfiltration, and APT activities
- **PowerShell Attack Monitoring** - Detection of suspicious command execution and encoded scripts
- **Risk-based Alerting** - Intelligent threat scoring and prioritized notifications
- **Cross-system Correlation** - APT kill-chain analysis across multiple data sources

### Integrated Platform
- **Todo Management** - Secure task management with priority levels and due dates
- **User Authentication** - JWT-based secure authentication system
- **Real-time Dashboard** - Live security monitoring and analytics
- **API Integration** - RESTful API for seamless frontend-backend communication

### ELK Stack Powered
- **Elasticsearch** - High-performance search and analytics for security data
- **Logstash** - Real-time log processing and threat enrichment
- **Kibana** - Interactive security dashboards and visualizations

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose
- 8GB+ RAM recommended
- 50GB+ storage space

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/rohansen856/elk-stack-monitoring
   cd elk-stack-monitoring
   ```

2. **Configure environment**
   ```bash
   cp .env.example .env
   cp website/.env.example website/.env
   ```
   The example files contain working, randomly generated development
   credentials, so the stack starts as-is. **Regenerate every secret before
   exposing this anywhere** - see the header of `.env.example`. There are no
   fallback defaults: if a value is missing the stack refuses to start rather
   than using a known password.

3. **Start all services**
   ```bash
   docker compose up -d
   ```
   Database migrations run automatically, and a self-signed TLS certificate is
   generated on first run.

4. **Wait for services to become healthy**
   ```bash
   docker compose ps
   ```
   All of `db`, `redis`, `elasticsearch`, `logstash`, `kibana`, `app`,
   `frontend` and `nginx` should report `(healthy)`. Elasticsearch and Kibana
   take the longest, typically under two minutes.

5. **Access the application**

   Everything is served through nginx over HTTPS. The certificate is
   self-signed, so your browser will warn once, and `curl` needs `-k`.

   | Service | URL |
   |---|---|
   | Frontend dashboard | https://localhost/frontend |
   | Backend API | https://localhost/backend/api/v1/ |
   | API health | https://localhost/backend/health |
   | API docs (non-production only) | https://localhost/backend/docs |
   | Kibana | https://localhost/monitoring |

   ```bash
   curl -k https://localhost/backend/health
   # {"status":"healthy","database":"ok","redis":"ok"}
   ```

   Ports bind to `127.0.0.1` by default so a local stack is not exposed to your
   network. Set `NGINX_BIND=0.0.0.0` in `.env` to publish it deliberately.

## 🎯 What's Included

### Frontend Application
- **Next.js 16 Dashboard** - Responsive task dashboard built with TypeScript
- **Todo Management** - Full-featured task management with priority levels (low/medium/high) and due dates
- **User Authentication** - Registration, login, logout and email-OTP password reset; the session lives in an httpOnly cookie
- **Responsive Design** - Tailwind CSS and shadcn/ui component library

> The web UI does not (yet) include security views. Threat detection is
> exposed through the authenticated `/api/v1/security/*` API and through
> Kibana (dashboards, Discover and the bundled detection rules).

### Backend API
- **FastAPI Framework** - High-performance Python API
- **PostgreSQL Database** - Reliable data storage with SQLAlchemy ORM
- **Redis Caching** - Enhanced performance for frequent queries
- **JWT Authentication** - Secure user management

### Security Stack
- **Threat Detection Engine** - Real-time analysis of security events
- **ELK Stack Integration** - Professional-grade log analysis platform
- **Alerting System** - Multi-channel notifications for security incidents
- **Prometheus Metrics** - System performance monitoring

## 📊 Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Frontend** | Next.js 16, TypeScript, Tailwind CSS, shadcn/ui | User interface and dashboards |
| **Backend** | FastAPI, Python 3.12, Pydantic | API server and business logic |
| **Database** | PostgreSQL, Redis, SQLAlchemy | Data persistence and caching |
| **Security** | Elasticsearch, Logstash, Kibana | Security monitoring and analytics |
| **Monitoring** | Filebeat, Metricbeat, Prometheus | System and security metrics |
| **Deployment** | Docker, Docker Compose, Multi-stage builds | Containerized deployment |
| **State Management** | Zustand, React Hook Form | Frontend state and form handling |

## 🔒 Security Features

### Threat Detection Capabilities
- **Brute Force Detection** - Multiple failed login attempts monitoring
- **Data Exfiltration Monitoring** - Unusual data transfer pattern detection
- **PowerShell Attack Detection** - Malicious script execution monitoring
- **APT Kill-chain Analysis** - Advanced persistent threat correlation

### Risk Scoring System
| Risk Level | Score | Response |
|------------|-------|----------|
| **Low** | 1-2 | Log and monitor |
| **Medium** | 3-4 | Alert notifications |
| **High** | 5-6 | Immediate attention |
| **Critical** | 7-8 | Incident response |
| **Emergency** | 9-10 | Full incident response |

## 📈 Getting Started Guide

### For End Users
1. Open the frontend at https://localhost/frontend
2. Register a new account with username, email, and a password of at least 12 characters
3. Use the todo system with priority levels and due dates
4. Manage tasks with filtering, search, and organization features

### For Security Teams
1. Access Kibana at https://localhost/monitoring and sign in as `elastic`
   (password: `ELASTIC_PASSWORD` in `.env`)
2. Import the bundled detection rules: Stack Management -> Saved Objects ->
   Import `kibana/export.ndjson` and `kibana/otx-detection-rules.ndjson`
3. Generate test activity with `scripts/apt-simulations-test/*.sh`
4. Query detections through the API, e.g. `GET /backend/api/v1/security/threats/scan`
   (requires a bearer token from `/backend/api/v1/users/login`)

### For Developers
1. Check API documentation at https://localhost/backend/docs
2. Review the [CONTRIBUTING.md](CONTRIBUTING.md) for technical details
3. Explore the codebase and security implementations
4. Run tests and contribute improvements

## 📚 Documentation

- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Technical documentation for developers
- **[docs/](docs/)** - Comprehensive system documentation
- **API Docs** - Available at https://localhost/backend/docs when running (non-production)

## 🛠️ System Requirements

### Development Environment
- **Memory**: 8GB RAM minimum, 16GB recommended
- **CPU**: 4 cores minimum, 8 cores recommended
- **Storage**: 50GB available space
- **OS**: Linux, macOS, or Windows with WSL2

### Production Environment
- **Memory**: 16GB RAM minimum, 32GB recommended
- **CPU**: 8 cores minimum, 16 cores recommended
- **Storage**: 200GB SSD minimum, 1TB recommended
- **Network**: High-bandwidth connection for log processing

## 🔧 Service Management

### Check System Status
```bash
# View all services
docker compose ps

# Check service health
curl -k https://localhost/backend/health
set -a; . ./.env; set +a   # load ELASTIC_PASSWORD into this shell
curl -u "elastic:$ELASTIC_PASSWORD" http://localhost:9200/_cluster/health
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f app
docker compose logs -f elasticsearch
```

### Stop Services
```bash
# Stop all services
docker compose down

# Stop and remove volumes (deletes all data)
docker compose down -v
```

## 🌟 Use Cases

### Security Operations Centers (SOC)
- Real-time threat monitoring and alerting
- Incident response coordination through task management
- Historical security analysis and reporting

### Enterprise IT Teams
- Centralized security event collection and analysis
- Automated threat detection and response
- Compliance monitoring and audit trails

### Development Teams
- Secure application development practices
- API security testing and validation
- Integration with existing security tools

## ⚡ Performance

- **Real-time Processing** - Sub-second threat detection
- **Scalable Architecture** - Horizontal scaling support
- **High Availability** - Redundant service design
- **Efficient Storage** - Optimized data retention policies

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development setup and guidelines
- API documentation and examples
- Testing procedures
- Code quality standards
- Security implementation details

## 📞 Support

- **Issues**: Create a GitHub issue for bugs or feature requests
- **Security**: Report security vulnerabilities through responsible disclosure
- **Documentation**: Check [CONTRIBUTING.md](CONTRIBUTING.md) for technical details
- **Community**: Join discussions in GitHub Discussions

## 📄 License

This project is open source. Please check the LICENSE file for details.

---

**🚀 Ready to enhance your security posture? Get started with the Advanced Threat Detection System today!**