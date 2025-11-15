# Component Interactions and Data Flow

## 🌊 Complete Data Flow Diagrams

This document shows exactly how data moves between all components in our Advanced Threat Detection System. Think of it as a **detailed map** showing how information travels from one place to another.

## 📡 Data Collection Flow

### From Computer Events to Security Alerts

```
🖥️ COMPUTER EVENTS
    │
    ▼
🎯 BEATS COLLECTION
    │
    ▼
⚙️ LOGSTASH PROCESSING
    │
    ▼
🗃️ ELASTICSEARCH STORAGE
    │
    ▼
🔍 THREAT DETECTION
    │
    ▼
🚨 ALERTS & RESPONSES
```

## 🔄 Detailed Component Interactions

### 1. User Authentication Flow

```
👤 User Attempts Login
    │
    ▼
🌐 FastAPI receives request
    │
    ├─→ 🚀 Redis: Check session cache
    │   └─→ Cache Miss
    │
    └─→ 🏛️ PostgreSQL: Verify credentials
        │
        ├─→ ✅ Valid: Create session
        │   └─→ 🚀 Redis: Store session token
        │
        └─→ ❌ Invalid: Log failed attempt
            └─→ 📋 Filebeat: Collect auth log
                └─→ ⚙️ Logstash: Process event
                    └─→ 🗃️ Elasticsearch: Store for analysis
                        └─→ 🔍 Threat Detection: Check for brute force
                            └─→ 🚨 Alert if suspicious
```

#### Detailed Steps with Data Examples

```python
# Step 1: User login request
POST /api/v1/users/login
{
    "email": "user@example.com",
    "password": "userpassword"
}

# Step 2: FastAPI processes request
async def login(credentials):
    # Check PostgreSQL for user
    user = db.query(User).filter(User.email == credentials.email).first()

    if user and verify_password(credentials.password, user.hashed_password):
        # Success: Create session in Redis
        session_token = generate_jwt_token(user.id)
        redis_client.setex(f"session:{session_token}", 1800, user.id)
        return {"token": session_token}
    else:
        # Failure: Log attempt (will be picked up by Filebeat)
        logger.warning(f"Failed login attempt for {credentials.email}")
        raise HTTPException(401, "Invalid credentials")

# Step 3: System log entry (if login fails)
# /var/log/auth.log:
# Jan 15 10:30:00 server1 todo-api: Failed login attempt for user@example.com from 203.0.113.42

# Step 4: Filebeat collects the log
# Sends to Logstash on port 5044

# Step 5: Logstash processes
{
    "@timestamp": "2024-01-15T10:30:00Z",
    "service": "todo-api",
    "event_type": "authentication_failure",
    "email": "user@example.com",
    "src_ip": "203.0.113.42",
    "geo": {"country": "Unknown"},
    "risk_score": 3
}

# Step 6: Stored in Elasticsearch index security-auth-logs-*
```

### 2. Todo CRUD Operations Flow

```
👤 User Request (Create Todo)
    │
    ▼
🌐 FastAPI validates JWT token
    │
    ├─→ 🚀 Redis: Check session validity
    │   ├─→ ✅ Valid session
    │   └─→ ❌ Invalid: Return 401 Unauthorized
    │
    ▼ (if valid)
🏛️ PostgreSQL: Insert new todo
    │
    ├─→ ✅ Success
    │   ├─→ 🚀 Redis: Clear user's todo cache
    │   └─→ 📊 Response: Return created todo
    │
    └─→ ❌ Error
        └─→ 📋 System log: Database error
            └─→ ⚙️ Logstash: Process error log
                └─→ 🗃️ Elasticsearch: Store for monitoring
```

#### Example Todo Creation

```python
# Step 1: User request
POST /api/v1/todos/
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
{
    "title": "Buy groceries",
    "description": "Milk, bread, eggs",
    "priority": "medium",
    "due_date": "2024-01-16T10:00:00Z"
}

# Step 2: FastAPI processes
async def create_todo(todo_data, current_user):
    # Create in PostgreSQL
    new_todo = Todo(
        title=todo_data.title,
        description=todo_data.description,
        priority=todo_data.priority,
        due_date=todo_data.due_date,
        owner_id=current_user.id
    )
    db.add(new_todo)
    db.commit()
    db.refresh(new_todo)

    # Clear cache in Redis
    cache_key = f"todos:user_{current_user.id}"
    redis_client.delete(cache_key)

    # Log successful creation
    logger.info(f"Todo created: {new_todo.id} for user {current_user.id}")

    return new_todo

# Step 3: System metrics (collected by Metricbeat)
{
    "timestamp": "2024-01-15T10:30:00Z",
    "service": "todo-api",
    "operation": "todo_create",
    "user_id": 123,
    "duration_ms": 45,
    "status": "success"
}
```

### 3. Security Threat Detection Flow

```
🚨 THREAT DETECTION PIPELINE

📋 Logs Collected (Filebeat/Metricbeat/Winlogbeat)
    │
    ▼
⚙️ Logstash Processing
    │ ├─→ Parse log format
    │ ├─→ Add geographic data (GeoIP)
    │ ├─→ Calculate initial risk score
    │ └─→ Add threat indicators
    │
    ▼
🗃️ Elasticsearch Storage
    │ └─→ Index: security-*-logs-YYYY.MM.DD
    │
    ▼
🔍 Threat Detection Engine (Every 30 seconds)
    │ ├─→ Query: Brute force patterns
    │ ├─→ Query: Data exfiltration patterns
    │ ├─→ Query: PowerShell attacks
    │ └─→ Query: APT correlation
    │
    ▼ (if threats detected)
🚨 Alerting System
    │ ├─→ 💬 Slack notification
    │ ├─→ 📧 Email alert
    │ └─→ 🗃️ Store alert in Elasticsearch
    │
    ▼
📊 Kibana Dashboard Updates
    │ ├─→ Update threat counters
    │ ├─→ Add to geographic map
    │ └─→ Update timeline charts
```

#### Brute Force Detection Example

```python
# Step 1: Multiple failed login attempts generate logs
# 10:30:00 - Failed password for admin from 203.0.113.42
# 10:30:15 - Failed password for admin from 203.0.113.42
# 10:30:30 - Failed password for admin from 203.0.113.42
# 10:30:45 - Failed password for admin from 203.0.113.42
# 10:31:00 - Failed password for admin from 203.0.113.42
# 10:31:15 - Accepted password for admin from 203.0.113.42

# Step 2: Threat Detection Engine queries Elasticsearch
query = {
    "query": {
        "bool": {
            "must": [
                {"range": {"@timestamp": {"gte": "now-15m"}}},
                {"term": {"src_ip.keyword": "203.0.113.42"}},
                {"terms": {"security_event.keyword": ["authentication_failure", "authentication_success"]}}
            ]
        }
    },
    "aggs": {
        "events": {
            "terms": {"field": "security_event.keyword"}
        }
    }
}

# Step 3: Analysis results
{
    "src_ip": "203.0.113.42",
    "failed_attempts": 5,
    "successful_attempts": 1,
    "pattern": "brute_force_attack",
    "risk_score": 10,
    "time_window": "15_minutes"
}

# Step 4: Alert generated and sent
alert = {
    "alert_type": "brute_force_attack",
    "severity": "critical",
    "src_ip": "203.0.113.42",
    "target_user": "admin",
    "geo_location": "China",
    "risk_score": 10,
    "evidence": {
        "failed_attempts": 5,
        "successful_breach": True,
        "time_to_success": "45_seconds"
    },
    "recommended_actions": [
        "Block source IP immediately",
        "Force password reset for admin account",
        "Review admin account activity"
    ]
}
```

## 🔗 Component Communication Matrix

### Service-to-Service Communication

| From Component | To Component | Protocol/Port | Data Type | Purpose |
|----------------|--------------|---------------|-----------|---------|
| **FastAPI** | PostgreSQL | TCP/5432 | SQL queries | User/todo data operations |
| **FastAPI** | Redis | TCP/6379 | Redis protocol | Session/cache operations |
| **FastAPI** | Elasticsearch | HTTP/9200 | REST API | Threat queries |
| **Filebeat** | Logstash | TCP/5044 | Beats protocol | Log transmission |
| **Metricbeat** | Logstash | TCP/5044 | Beats protocol | Metrics transmission |
| **Winlogbeat** | Logstash | TCP/5044 | Beats protocol | Windows events |
| **Logstash** | Elasticsearch | HTTP/9200 | REST API | Processed data storage |
| **Kibana** | Elasticsearch | HTTP/9200 | REST API | Data visualization |
| **Threat Engine** | Elasticsearch | HTTP/9200 | REST API | Security queries |
| **Alerting** | Slack API | HTTPS/443 | Webhook | Alert notifications |
| **Alerting** | SMTP Server | TCP/587 | SMTP | Email notifications |

### Data Format Transformations

```
RAW LOG FORMAT (from system):
Jan 15 10:30:00 server1 sshd[1234]: Failed password for admin from 203.0.113.42 port 22 ssh2

↓ Filebeat Collection

BEATS FORMAT (to Logstash):
{
    "@timestamp": "2024-01-15T10:30:00Z",
    "message": "Failed password for admin from 203.0.113.42 port 22 ssh2",
    "host": {"name": "server1"},
    "log": {"file": {"path": "/var/log/auth.log"}},
    "agent": {"type": "filebeat"}
}

↓ Logstash Processing

PROCESSED FORMAT (to Elasticsearch):
{
    "@timestamp": "2024-01-15T10:30:00Z",
    "security_event": "authentication_failure",
    "service": "sshd",
    "user_name": "admin",
    "src_ip": "203.0.113.42",
    "src_port": 22,
    "protocol": "ssh2",
    "geo": {
        "country_name": "China",
        "city_name": "Beijing",
        "location": {"lat": 39.9042, "lon": 116.4074}
    },
    "risk_score": 7,
    "threat_indicators": ["external_ip", "privileged_account"],
    "host": {"name": "server1"},
    "log_category": "authentication",
    "processed_by": "logstash"
}
```

## 🔄 Real-time Processing Workflows

### Workflow 1: User Session Management

```
1. USER LOGIN REQUEST
   ├─ FastAPI → PostgreSQL: Verify credentials
   ├─ FastAPI → Redis: Create session cache
   └─ FastAPI → User: Return JWT token

2. SUBSEQUENT API REQUESTS
   ├─ FastAPI → Redis: Validate session (fast!)
   ├─ If valid → Continue to business logic
   └─ If invalid → Return 401 Unauthorized

3. SESSION EXPIRY
   ├─ Redis: Auto-delete expired sessions (TTL)
   └─ User: Must login again

4. USER LOGOUT
   ├─ FastAPI → Redis: Delete session
   └─ FastAPI → User: Confirm logout
```

### Workflow 2: Security Event Processing

```
1. SECURITY EVENT OCCURS
   └─ System generates log entry

2. LOG COLLECTION
   ├─ Filebeat: Detects new log line
   ├─ Reads file content
   └─ Sends to Logstash

3. LOG PROCESSING
   ├─ Logstash: Receives raw log
   ├─ Parses fields (IP, username, timestamp)
   ├─ Enriches with GeoIP data
   ├─ Calculates risk score
   └─ Sends to Elasticsearch

4. STORAGE & INDEXING
   ├─ Elasticsearch: Stores processed event
   ├─ Indexes for fast searching
   └─ Available for queries

5. THREAT ANALYSIS (every 30 seconds)
   ├─ Threat Engine: Queries Elasticsearch
   ├─ Analyzes patterns across events
   ├─ Calculates threat scores
   └─ Triggers alerts if needed

6. ALERT PROCESSING
   ├─ Alerting Service: Receives threat data
   ├─ Formats notifications
   ├─ Sends to Slack/Email
   └─ Stores alert in Elasticsearch

7. VISUALIZATION UPDATE
   ├─ Kibana: Queries updated data
   ├─ Updates dashboards in real-time
   └─ Shows new threats on maps/charts
```

## ⚡ Performance Optimization Points

### Critical Performance Paths

```
🔥 HOT PATH (High Frequency):
User API Requests → FastAPI → Redis (Cache Hit)
└─ Optimized with: Connection pooling, Redis clustering

🌡️ WARM PATH (Medium Frequency):
User API Requests → FastAPI → PostgreSQL → Redis (Cache Update)
└─ Optimized with: Database indexing, connection pools

❄️ COLD PATH (Low Frequency):
Security Analysis → Elasticsearch → Complex Queries
└─ Optimized with: Index optimization, query caching
```

### Load Balancing Strategy

```
INTERNET
    │
    ▼
🌐 LOAD BALANCER
    │
    ├─→ FastAPI Instance 1 ┬─→ PostgreSQL (Primary)
    ├─→ FastAPI Instance 2 ├─→ Redis (Cluster)
    └─→ FastAPI Instance 3 └─→ Elasticsearch (Cluster)
```

## 🛡️ Error Handling and Resilience

### Component Failure Scenarios

```
SCENARIO 1: PostgreSQL Unavailable
├─ FastAPI: Detects database error
├─ Returns 503 Service Unavailable
├─ Health check: Reports database down
└─ Monitoring: Alerts administrators

SCENARIO 2: Redis Unavailable
├─ FastAPI: Falls back to direct database queries
├─ Performance degrades but system continues
├─ Session validation uses JWT validation
└─ Cache writes are skipped gracefully

SCENARIO 3: Elasticsearch Unavailable
├─ Threat detection: Switches to degraded mode
├─ Basic pattern matching continues
├─ Complex correlation analysis paused
└─ Alerts: Basic threshold alerts only

SCENARIO 4: Logstash Unavailable
├─ Beats: Queue events locally
├─ Automatic retry with backoff
├─ No data loss (local buffering)
└─ Resume processing when available
```

### Health Check Integration

```python
@app.get("/health/detailed")
async def detailed_health():
    return {
        "overall_status": "healthy",
        "components": {
            "fastapi": check_fastapi_health(),
            "postgresql": check_postgresql_health(),
            "redis": check_redis_health(),
            "elasticsearch": check_elasticsearch_health(),
            "threat_detection": check_threat_engine_health()
        },
        "performance": {
            "avg_response_time_ms": 45,
            "requests_per_second": 150,
            "error_rate_percent": 0.1
        }
    }
```

This comprehensive interaction diagram shows how all components work together to provide a robust, scalable threat detection system with multiple layers of redundancy and optimization.