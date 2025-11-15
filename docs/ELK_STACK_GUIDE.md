# ELK Stack Components Guide

## 🎯 What is the ELK Stack?

ELK stands for **Elasticsearch**, **Logstash**, and **Kibana**. Think of it like a team of three friends who work together to help you understand what's happening in your computer systems:

- **Elasticsearch** = The librarian who organizes and stores millions of books (logs)
- **Logstash** = The translator who makes sure all books are written in the same language
- **Kibana** = The artist who draws pictures to help you understand the books

## 📚 Elasticsearch - The Data Storage Expert

### What is Elasticsearch?

Elasticsearch is like a **super-smart filing cabinet** that can store millions of documents (logs) and find exactly what you're looking for in seconds.

### How Does it Work?

```
Think of it like Google for your logs:

1. Store millions of security events
2. Search through them instantly
3. Find patterns and connections
4. Answer questions like:
   - "Show me all failed logins from China"
   - "Find suspicious PowerShell commands"
   - "What happened between 2 AM and 4 AM?"
```

### Key Features

| Feature | What it Does | Example |
|---------|--------------|---------|
| **Indexing** | Organizes data for fast searching | Like a library catalog system |
| **Full-Text Search** | Find any word in millions of logs | Search for "failed password" |
| **Aggregations** | Count and summarize data | "How many attacks per country?" |
| **Real-time** | Shows data as it happens | Live threat detection |

### Configuration in Our System

```yaml
# From docker-compose.yml
elasticsearch:
  image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
  ports:
    - "9200:9200"  # Main API port
    - "9300:9300"  # Internal cluster communication
  environment:
    - discovery.type=single-node
    - xpack.security.enabled=false
    - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
```

### Data Structure (Indices)

Our system creates these "filing cabinets":

```
security-auth-logs-*      → Login/logout events
security-network-logs-*   → Network traffic and firewall
security-audit-logs-*     → File access and system changes
security-alerts-*         → Detected threats and alerts
windows-security-logs-*   → Windows-specific events
application-logs-*        → Our FastAPI application logs
```

### Example Data in Elasticsearch

```json
{
  "@timestamp": "2024-01-15T10:30:00Z",
  "security_event": "authentication_failure",
  "src_ip": "203.0.113.42",
  "user_name": "admin",
  "geo": {
    "country": "China",
    "city": "Beijing"
  },
  "risk_score": 8,
  "threat_indicators": ["external_ip", "privileged_account"]
}
```

## ⚙️ Logstash - The Data Processor

### What is Logstash?

Logstash is like a **smart factory worker** who takes messy, different-formatted logs from various sources and cleans them up into a standard format that Elasticsearch can understand.

### How Does it Work?

```
INPUT → FILTER → OUTPUT

1. INPUT:  Receives raw logs from Filebeat, Metricbeat, etc.
2. FILTER: Cleans, parses, and enriches the data
3. OUTPUT: Sends processed data to Elasticsearch
```

### The Pipeline Process

```
Raw Log: "Jan 15 10:30:00 server1 sshd: Failed password for admin from 203.0.113.42"

After Logstash Processing:
{
  "timestamp": "2024-01-15T10:30:00Z",
  "host": "server1",
  "service": "sshd",
  "event_type": "authentication_failure",
  "username": "admin",
  "source_ip": "203.0.113.42",
  "geo_location": "China",
  "risk_score": 7
}
```

### Configuration Ports

| Port | Purpose | Who Connects |
|------|---------|--------------|
| 5044 | Beats input | Filebeat, Metricbeat, Winlogbeat |
| 5000 | TCP input | Application logs, custom systems |
| 9600 | API/Monitoring | Health checks, statistics |
| 514 | Syslog UDP/TCP | Network devices, routers, firewalls |
| 12201 | GELF | Docker container logs |

### Processing Pipeline Example

```ruby
# Logstash configuration snippet
input {
  beats {
    port => 5044
  }
  tcp {
    port => 5000
    codec => json
  }
}

filter {
  # Add geographic information
  geoip {
    source => "src_ip"
    target => "geo"
  }

  # Calculate risk score
  if [failed_attempts] > 5 {
    mutate {
      add_field => { "risk_score" => 8 }
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "security-logs-%{+YYYY.MM.dd}"
  }
}
```

## 📊 Kibana - The Visualization Dashboard

### What is Kibana?

Kibana is like an **artist and detective combined** - it takes all the data from Elasticsearch and creates beautiful, easy-to-understand charts, graphs, and dashboards.

### How Does it Work?

```
1. Connects to Elasticsearch
2. Reads the stored data
3. Creates visualizations:
   - Pie charts showing attack sources by country
   - Line graphs showing attacks over time
   - Heat maps of suspicious activity
   - Tables of top threats
```

### Key Features

| Feature | What it Does | Example Use |
|---------|--------------|-------------|
| **Discover** | Search and explore raw data | Find specific security events |
| **Visualize** | Create charts and graphs | Show attacks by country |
| **Dashboard** | Combine multiple visualizations | Security operations center view |
| **Canvas** | Create infographic-style reports | Executive summary presentations |
| **Maps** | Show geographic data | World map of attack sources |

### Dashboard Examples

#### 🛡️ Security Operations Dashboard
```
┌──────────────────┬─────────────────┬─────────────────┐
│   Total Alerts   │  High Risk      │   Countries     │
│      1,247       │     23          │      15         │
├──────────────────┼─────────────────┴─────────────────┤
│  ⚠️ Failed Login │                                   │
│  Attempts        │     📊 Attacks by Time            │
│                  │     (Last 24 Hours)               │
│  🇨🇳 China: 45    │                                   │
│  🇷🇺 Russia: 32   │     ▄▄   ▄▄▄    ▄                 │
│  🇺🇸 USA: 28      │   ▄▄██ ▄▄███  ▄▄█ ▄▄              │
│                  │ ▄▄████▄██████▄███▄██▄▄            │
└──────────────────┴───────────────────────────────────┘
```

#### 🌍 Geographic Threat Map
```
World Map showing:
🔴 Red dots = High-risk attack sources
🟡 Yellow dots = Medium-risk sources
🟢 Green dots = Low-risk sources

Hover over any dot to see:
- Number of attacks
- Attack types
- Risk level
- Blocked/Allowed ratio
```

### Configuration

```yaml
# From docker-compose.yml
kibana:
  image: docker.elastic.co/kibana/kibana:8.11.0
  ports:
    - "5601:5601"  # Web interface
  environment:
    - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
  depends_on:
    - elasticsearch
```

### Creating Security Index Patterns

When you first set up Kibana, create these index patterns:

1. **security-*** - All security-related logs
2. **security-auth-logs-*** - Authentication events only
3. **windows-security-logs-*** - Windows-specific events
4. **security-alerts-*** - Detected threats and alerts

## 🔄 How ELK Components Work Together

### Data Flow Example: Detecting a Brute Force Attack

```
Step 1: EVENT OCCURS
Someone tries to log in with wrong password 5 times

Step 2: FILEBEAT COLLECTS
Filebeat sees the authentication failure in /var/log/auth.log

Step 3: LOGSTASH PROCESSES
- Parses the log format
- Extracts IP address, username, timestamp
- Adds geographic location (GeoIP lookup)
- Calculates risk score (5 failures = high risk)
- Adds threat indicators

Step 4: ELASTICSEARCH STORES
Stores the processed event in security-auth-logs-2024.01.15 index

Step 5: KIBANA VISUALIZES
- Updates "Failed Logins" counter on dashboard
- Adds red dot to world map
- Triggers alert visualization
- Updates attack timeline graph

Step 6: THREAT DETECTION ENGINE
- Queries Elasticsearch for similar events
- Detects brute force pattern
- Sends alerts to Slack and email
```

## 🛠️ Common Operations

### Check ELK Health
```bash
# Elasticsearch health
curl http://localhost:9200/_cluster/health

# Logstash health
curl http://localhost:9600/_node/stats

# Kibana health
curl http://localhost:5601/api/status
```

### View Indices
```bash
# List all indices
curl "http://localhost:9200/_cat/indices?v"

# Search specific index
curl "http://localhost:9200/security-logs-*/_search?q=failed_login"
```

### Logstash Monitoring
```bash
# View Logstash logs
docker-compose logs logstash

# Check pipeline stats
curl http://localhost:9600/_node/stats/pipelines
```

## 🔧 Configuration Files

### Logstash Pipeline
Located in: `./logstash/pipeline/logstash.conf`
- Input configurations for different data sources
- Filter rules for data processing
- Output configurations for Elasticsearch

### Beats Configuration
- **Filebeat**: `./filebeat/filebeat.yml`
- **Metricbeat**: `./metricbeat/metricbeat.yml`
- **Winlogbeat**: `./winlogbeat/winlogbeat.yml`

## 🚨 Monitoring and Alerts

The ELK stack provides multiple ways to monitor system health:

1. **Built-in Monitoring**: Track cluster health, index sizes, query performance
2. **Custom Metrics**: Application-specific metrics and KPIs
3. **Log-based Alerts**: Trigger alerts based on log patterns
4. **Threshold Alerts**: Alert when values exceed certain limits

## 💡 Best Practices

### Performance Optimization
- Use appropriate index patterns for different log types
- Configure index lifecycle management for automatic cleanup
- Set proper JVM heap sizes for Elasticsearch
- Use filters to reduce unnecessary data processing

### Security
- Enable authentication in production environments
- Use SSL/TLS for communication between components
- Implement proper access controls for Kibana dashboards
- Regularly update ELK stack versions

### Data Management
- Set up index templates for consistent field mappings
- Use aliases for easier index management
- Implement data retention policies
- Monitor disk space usage regularly

This ELK stack configuration provides a robust foundation for real-time threat detection and security monitoring, capable of processing thousands of events per second while maintaining fast search and visualization capabilities.