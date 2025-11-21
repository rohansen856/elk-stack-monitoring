# Advanced Threat Detection System

**Enterprise-grade security monitoring solution with real-time APT detection using ELK Stack**

<!-- ![System Architecture](../assets/images/poster.png) -->

## Overview

The Advanced Threat Detection System is a comprehensive cybersecurity platform that combines task management with advanced threat detection capabilities, powered by the ELK Stack (Elasticsearch, Logstash, Kibana) for real-time security monitoring and APT (Advanced Persistent Threat) detection.

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

1. **Clone the repository**
   ```bash
   git clone https://github.com/rohansen856/elk-stack-monitoring
   cd elk-stack-monitoring
   ```

2. **Configure environment**
   ```bash
   cp .env.example .env
   ```

3. **Start all services**
   ```bash
   docker-compose up -d
   ```

4. **Access the applications**
   - **Frontend Dashboard**: http://localhost:3000
   - **API Documentation**: http://localhost:8000/docs
   - **Kibana Security Dashboard**: http://localhost:5601

## 📊 Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Frontend** | Next.js 16, TypeScript, Tailwind CSS | User interface and dashboards |
| **Backend** | FastAPI, Python 3.11+, Pydantic | API server and business logic |
| **Database** | PostgreSQL, Redis, SQLAlchemy | Data persistence and caching |
| **Security** | Elasticsearch, Logstash, Kibana | Security monitoring and analytics |
| **Monitoring** | Filebeat, Metricbeat, Prometheus | System and security metrics |
| **Deployment** | Docker, Docker Compose | Containerized deployment |

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

## 📚 Navigation

Use the navigation menu to explore:

- **Getting Started** - Installation and setup guides
- **ELK Stack** - Detailed component documentation
- **Security** - APT detection rules and simulations
- **Development** - API and architecture documentation
- **Deployment** - Production deployment guides

---

**🚀 Ready to enhance your security posture? Get started with the Advanced Threat Detection System today!**