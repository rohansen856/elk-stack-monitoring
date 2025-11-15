# System Architecture Guide

## 🏗️ High-Level System Overview

Think of our Advanced Threat Detection System like a **smart security guard** for computers. Just like how a security guard watches multiple cameras, our system watches computer logs from many different sources to catch bad guys (hackers) trying to break in.

```
┌─────────────────────────────────────────────────────────────┐
│                   🛡️ THREAT DETECTION SYSTEM                │
│                                                             │
│  ┌─────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │  WEB    │    │   THREAT    │    │    ELK STACK        │  │
│  │  APP    │◄──►│ DETECTION   │◄──►│   (Log Analysis)    │  │
│  │(FastAPI)│    │  ENGINE     │    │                     │  │
│  └─────────┘    └─────────────┘    └─────────────────────┘  │
│       │                                       │             │
│       ▼                                       ▼             │
│  ┌─────────┐                          ┌─────────────┐       │
│  │DATABASE │                          │   BEATS     │       │
│  │CLUSTER  │                          │ (Data       │       │
│  │         │                          │ Collectors) │       │
│  └─────────┘                          └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

## 🎯 What Does Each Part Do?

### 1. **The Web App (FastAPI)** 📱
- **What it is**: The main application that users interact with
- **What it does**:
  - Manages user accounts and login
  - Handles todo lists (the main app feature)
  - Shows security alerts and threat information
  - Provides API endpoints for other systems
- **Like in real life**: The reception desk at a building where people check in

### 2. **Threat Detection Engine** 🔍
- **What it is**: Smart software that analyzes security data
- **What it does**:
  - Watches for suspicious login attempts
  - Detects when someone tries to steal data
  - Finds malicious PowerShell commands
  - Connects the dots between different attacks
- **Like in real life**: A detective who looks at clues and solves crimes

### 3. **ELK Stack (The Brain)** 🧠
- **What it is**: Three connected systems that store and analyze logs
- **What it does**: Collects, processes, and visualizes security data
- **Like in real life**: A security command center with monitors showing everything

### 4. **Database Cluster** 💾
- **What it is**: Where all the data is stored
- **What it does**: Keeps user accounts, todos, and cached data safe
- **Like in real life**: A filing cabinet system with different drawers

### 5. **Beats (Data Collectors)** 📡
- **What it is**: Tiny programs that collect data from computers
- **What it does**: Gathers logs from different sources and sends them to ELK
- **Like in real life**: Security cameras placed around a building

## 🔄 How Data Flows Through the System

```
Step 1: Data Collection
Computer Events → Beats → Logstash → Elasticsearch

Step 2: Analysis
Elasticsearch → Threat Detection Engine → Alerts

Step 3: User Interaction
User → FastAPI → Database/ELK → Response
```

### Detailed Data Flow

1. **🏠 Something happens on a computer** (login, file access, network traffic)
2. **📡 Beats collect the event** and send it to Logstash
3. **⚙️ Logstash processes the data** (cleans it up, adds extra info)
4. **🗄️ Elasticsearch stores the data** in searchable format
5. **🔍 Threat Detection Engine analyzes** the data for suspicious patterns
6. **🚨 If threats are found**, alerts are sent to administrators
7. **📊 Kibana shows visual dashboards** of what's happening
8. **👤 Users interact through FastAPI** to see alerts and manage settings

## 🏢 Physical Architecture (How Components Connect)

```
┌───────────────────────────────────────────────────────────────┐
│                        DOCKER NETWORK                         │
│                                                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │   FastAPI   │  │    Redis    │  │ PostgreSQL  │            │
│  │    :8000    │  │    :6379    │  │   :5432     │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│         │                │                │                   │
│         └────────────────┼────────────────┘                   │
│                          │                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│  │Elasticsearch│  │  Logstash   │  │   Kibana    │            │
│  │    :9200    │  │ :5044/:5000 │  │    :5601    │            │
│  └─────────────┘  └─────────────┘  └─────────────┘            │
│         │                │                │                   │
│         └────────────────┼────────────────┘                   │
│                          │                                    │
│  ┌─────────────┐  ┌─────────────┐                             │
│  │  Filebeat   │  │ Metricbeat  │                             │
│  │   (logs)    │  │  (metrics)  │                             │
│  └─────────────┘  └─────────────┘                             │
└───────────────────────────────────────────────────────────────┘
```

## 🎮 Component Responsibilities

| Component | Port | Main Job | Data Type |
|-----------|------|----------|-----------|
| **FastAPI** | 8000 | Handle user requests, manage authentication | HTTP requests/responses |
| **PostgreSQL** | 5432 | Store user accounts and todos permanently | Structured user data |
| **Redis** | 6379 | Cache frequently used data for speed | Temporary cached data |
| **Elasticsearch** | 9200 | Store and search through millions of log entries | Security logs and events |
| **Logstash** | 5044/5000 | Process and clean up incoming log data | Raw logs → Clean logs |
| **Kibana** | 5601 | Show dashboards and visualizations | Visual charts and graphs |
| **Filebeat** | - | Collect log files from the system | System log files |
| **Metricbeat** | - | Collect system performance metrics | CPU, memory, disk stats |

## 🔒 Security Data Flow

```
1. USER LOGS IN
   ↓
2. AUTHENTICATION EVENT CREATED
   ↓
3. FILEBEAT COLLECTS THE LOG
   ↓
4. LOGSTASH PROCESSES:
   - Adds timestamp
   - Identifies source IP
   - Adds geographic location
   - Calculates risk score
   ↓
5. ELASTICSEARCH STORES THE PROCESSED LOG
   ↓
6. THREAT DETECTION ENGINE CHECKS:
   - Is this a brute force attack?
   - Are there too many failed logins?
   - Is this from a suspicious location?
   ↓
7. IF THREAT DETECTED:
   - Send alert to Slack/Email
   - Store alert in database
   - Update Kibana dashboard
   - Notify security team
```

## 🧩 Component Integration Points

### FastAPI ↔ Databases
- **PostgreSQL**: Permanent storage for users and todos
- **Redis**: Fast temporary storage for sessions and cache
- **Elasticsearch**: Security data queries and threat detection

### ELK Stack Internal Communication
- **Logstash → Elasticsearch**: Processes and stores logs
- **Elasticsearch ↔ Kibana**: Data visualization and dashboards
- **Beats → Logstash**: Log collection and forwarding

### External Integrations
- **Slack API**: Real-time threat notifications
- **Email SMTP**: Detailed threat reports
- **System Logs**: File and system monitoring
- **Network Devices**: Firewall and network logs

## 📈 Scalability Design

The system is designed to grow:

- **Horizontal Scaling**: Add more Elasticsearch nodes for more data
- **Load Balancing**: Multiple FastAPI instances behind a load balancer
- **Data Partitioning**: Separate indices for different types of security data
- **Caching**: Redis reduces database load
- **Asynchronous Processing**: Non-blocking operations for better performance

This architecture ensures the system can handle growing amounts of security data while maintaining fast response times for users.