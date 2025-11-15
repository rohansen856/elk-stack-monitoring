# Elasticsearch Deep Dive Guide

## 🔍 What is Elasticsearch?

Elasticsearch is like a **super-intelligent librarian** who has memorized every book in a massive library and can instantly find any piece of information you're looking for. Unlike traditional databases that store data in tables and rows, Elasticsearch stores documents (like JSON files) and makes them searchable in milliseconds.

Think of it as **Google for your data** - you can search through millions of security events, logs, and documents using natural language queries and get results instantly.

## 🏗️ Core Architecture

### Document-Based Storage

```
Traditional Database (PostgreSQL):
┌─────────┬──────────────┬─────────────┬──────────────┐
│   ID    │    Event     │  Timestamp  │  Source_IP   │
├─────────┼──────────────┼─────────────┼──────────────┤
│   1     │ Failed Login │ 2024-01-15  │ 192.168.1.1  │
│   2     │ File Access  │ 2024-01-15  │ 192.168.1.2  │
└─────────┴──────────────┴─────────────┴──────────────┘

Elasticsearch (Document Store):
{
  "_index": "security-logs-2024.01.15",
  "_id": "abc123",
  "_source": {
    "@timestamp": "2024-01-15T10:30:00Z",
    "event_type": "authentication_failure",
    "user": "admin",
    "src_ip": "192.168.1.1",
    "geo": {
      "country": "United States",
      "coordinates": [40.7128, -74.0060]
    },
    "risk_score": 7,
    "threat_indicators": ["external_ip", "privileged_account"]
  }
}
```

### Index Structure (Our Filing System)

```
Elasticsearch Cluster
├── security-auth-logs-2024.01.15      (Authentication events)
├── security-network-logs-2024.01.15   (Network/firewall events)
├── security-audit-logs-2024.01.15     (File access events)
├── security-alerts-2024.01.15         (Detected threats)
├── windows-security-logs-2024.01.15   (Windows events)
├── application-logs-2024.01.15        (FastAPI logs)
└── metrics-2024.01.15                 (Performance metrics)
```

## 📚 Elasticsearch Concepts Explained

### 1. **Cluster** - The Entire Library System
```
🏢 Elasticsearch Cluster = The entire library building

Our cluster contains:
- 1 Master Node (librarian supervisor)
- Multiple Data Nodes (librarians)
- Coordinating Nodes (information desk)

In our setup:
- Single-node cluster (development)
- Production would have multiple nodes
```

### 2. **Indices** - Individual Library Sections
```
📚 Index = A section of the library (like "Science" or "History")

security-auth-logs-*     = Authentication section
security-network-logs-*  = Network security section
security-alerts-*        = Threat alerts section

Each index contains documents of the same type
Daily indices: security-auth-logs-2024.01.15
```

### 3. **Documents** - Individual Books/Records
```
📖 Document = A single book or record

Example security document:
{
  "_index": "security-auth-logs-2024.01.15",
  "_type": "_doc",
  "_id": "auth_123456",
  "_source": {
    "event": "authentication_failure",
    "user": "admin",
    "src_ip": "203.0.113.42",
    "timestamp": "2024-01-15T10:30:00Z",
    "details": "Failed SSH login attempt"
  }
}
```

### 4. **Fields** - Information Categories
```
🏷️ Fields = Categories of information in each book

Standard fields in our security documents:
- @timestamp: When the event happened
- event_type: What kind of security event
- src_ip: Source IP address
- dst_ip: Destination IP address
- user_name: Username involved
- risk_score: Threat level (1-10)
- geo.country: Geographic location
- threat_indicators: Array of threat markers
```

### 5. **Mappings** - The Catalog System
```
📋 Mapping = How the librarian catalogs each book

Example mapping for security events:
{
  "mappings": {
    "properties": {
      "@timestamp": {
        "type": "date"
      },
      "src_ip": {
        "type": "ip"
      },
      "risk_score": {
        "type": "integer",
        "index": true
      },
      "event_type": {
        "type": "keyword"
      },
      "message": {
        "type": "text",
        "analyzer": "standard"
      }
    }
  }
}
```

## 🔧 Configuration in Our System

### Docker Configuration
```yaml
# From docker-compose.yml
elasticsearch:
  image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
  container_name: elasticsearch
  environment:
    # Single-node setup for development
    - discovery.type=single-node

    # Disable security for easy development
    - xpack.security.enabled=false

    # Cluster name
    - cluster.name=docker-cluster

    # Memory settings
    - "ES_JAVA_OPTS=-Xms512m -Xmx512m"

    # Bootstrap memory lock
    - bootstrap.memory_lock=true

    # Auto-create indices
    - action.auto_create_index=true

    # Disable disk threshold (for development)
    - cluster.routing.allocation.disk.threshold_enabled=false

  # Memory limits
  ulimits:
    memlock:
      soft: -1
      hard: -1

  # Ports
  ports:
    - "9200:9200"  # HTTP API
    - "9300:9300"  # Transport (cluster communication)

  # Persistent storage
  volumes:
    - elasticsearch_data:/usr/share/elasticsearch/data

  # Health check
  healthcheck:
    test: ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
    interval: 30s
    timeout: 10s
    retries: 5
```

### Index Templates (Auto-Configuration)
```json
// Template for security logs
PUT _index_template/security-logs-template
{
  "index_patterns": ["security-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.refresh_interval": "1s",
      "index.max_result_window": 50000
    },
    "mappings": {
      "properties": {
        "@timestamp": {
          "type": "date"
        },
        "src_ip": {
          "type": "ip"
        },
        "dst_ip": {
          "type": "ip"
        },
        "event_type": {
          "type": "keyword"
        },
        "user_name": {
          "type": "keyword"
        },
        "risk_score": {
          "type": "integer"
        },
        "geo": {
          "properties": {
            "country": {"type": "keyword"},
            "city": {"type": "keyword"},
            "location": {"type": "geo_point"}
          }
        },
        "threat_indicators": {
          "type": "keyword"
        }
      }
    }
  }
}
```

## 🔍 Searching and Querying

### Basic Queries

#### 1. Simple Text Search
```bash
# Find all failed login attempts
curl -X GET "localhost:9200/security-*/_search" -H 'Content-Type: application/json' -d'
{
  "query": {
    "match": {
      "event_type": "authentication_failure"
    }
  }
}
'
```

#### 2. Time Range Query
```bash
# Events from the last hour
curl -X GET "localhost:9200/security-*/_search" -H 'Content-Type: application/json' -d'
{
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-1h"
      }
    }
  }
}
'
```

#### 3. Complex Boolean Query
```bash
# Failed logins from external IPs with high risk score
curl -X GET "localhost:9200/security-*/_search" -H 'Content-Type: application/json' -d'
{
  "query": {
    "bool": {
      "must": [
        {"term": {"event_type": "authentication_failure"}},
        {"range": {"risk_score": {"gte": 7}}}
      ],
      "must_not": [
        {"terms": {"src_ip": ["192.168.0.0/16", "10.0.0.0/8"]}}
      ],
      "filter": [
        {"range": {"@timestamp": {"gte": "now-24h"}}}
      ]
    }
  },
  "sort": [{"@timestamp": {"order": "desc"}}],
  "size": 100
}
'
```

### Aggregations (Analytics)

#### 1. Count Events by Country
```bash
curl -X GET "localhost:9200/security-*/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "aggs": {
    "attacks_by_country": {
      "terms": {
        "field": "geo.country",
        "size": 10
      }
    }
  }
}
'

# Response shows:
# {
#   "aggregations": {
#     "attacks_by_country": {
#       "buckets": [
#         {"key": "China", "doc_count": 1247},
#         {"key": "Russia", "doc_count": 892},
#         {"key": "United States", "doc_count": 234}
#       ]
#     }
#   }
# }
```

#### 2. Time-based Histogram
```bash
# Attacks per hour over last 24 hours
curl -X GET "localhost:9200/security-*/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-24h"
      }
    }
  },
  "aggs": {
    "attacks_over_time": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "1h"
      }
    }
  }
}
'
```

#### 3. Multi-level Aggregation
```bash
# Risk score distribution by country
curl -X GET "localhost:9200/security-*/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "aggs": {
    "by_country": {
      "terms": {"field": "geo.country"},
      "aggs": {
        "risk_levels": {
          "range": {
            "field": "risk_score",
            "ranges": [
              {"key": "low", "from": 1, "to": 4},
              {"key": "medium", "from": 4, "to": 7},
              {"key": "high", "from": 7, "to": 11}
            ]
          }
        },
        "avg_risk": {
          "avg": {"field": "risk_score"}
        }
      }
    }
  }
}
'
```

## 📊 Our Security Data Structure

### Authentication Events Index
```json
// security-auth-logs-2024.01.15
{
  "@timestamp": "2024-01-15T14:30:00Z",
  "event_type": "authentication_failure",
  "service": "sshd",
  "user_name": "admin",
  "src_ip": "203.0.113.42",
  "src_port": 22,
  "dst_ip": "192.168.1.100",
  "dst_port": 22,
  "protocol": "ssh",
  "geo": {
    "country": "China",
    "city": "Beijing",
    "coordinates": [39.9042, 116.4074]
  },
  "risk_score": 8,
  "threat_indicators": ["external_ip", "privileged_account", "off_hours"],
  "session_id": null,
  "failure_reason": "invalid_password",
  "host": {
    "name": "web-server-01",
    "ip": "192.168.1.100"
  }
}
```

### Network Security Events Index
```json
// security-network-logs-2024.01.15
{
  "@timestamp": "2024-01-15T14:35:00Z",
  "event_type": "firewall_block",
  "action": "DENY",
  "src_ip": "203.0.113.42",
  "src_port": 4444,
  "dst_ip": "192.168.1.100",
  "dst_port": 80,
  "protocol": "TCP",
  "bytes": 0,
  "packets": 1,
  "duration": 0,
  "geo": {
    "country": "China",
    "city": "Beijing"
  },
  "risk_score": 6,
  "threat_indicators": ["suspicious_port", "external_source"],
  "firewall_rule": "BLOCK_EXTERNAL_443",
  "interface": "eth0"
}
```

### Threat Alerts Index
```json
// security-alerts-2024.01.15
{
  "@timestamp": "2024-01-15T14:40:00Z",
  "alert_type": "brute_force_attack",
  "severity": "high",
  "confidence": 95,
  "src_ip": "203.0.113.42",
  "target_user": "admin",
  "geo": {
    "country": "China",
    "city": "Beijing"
  },
  "risk_score": 10,
  "evidence": {
    "failed_attempts": 15,
    "time_window_minutes": 5,
    "successful_breach": false,
    "targeted_accounts": ["admin", "root", "administrator"]
  },
  "mitre_attack": {
    "technique": "T1110.001",
    "tactic": "Credential Access",
    "description": "Password Guessing"
  },
  "recommended_actions": [
    "Block source IP immediately",
    "Force password reset for targeted accounts",
    "Review account activity logs"
  ],
  "investigated": false,
  "false_positive": false
}
```

## ⚡ Performance Optimization

### Index Lifecycle Management (ILM)
```json
// Automatic index management
PUT _ilm/policy/security-logs-policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "1GB",
            "max_age": "1d"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "allocate": {
            "number_of_replicas": 0
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "allocate": {
            "number_of_replicas": 0
          }
        }
      },
      "delete": {
        "min_age": "90d"
      }
    }
  }
}
```

### Query Optimization Tips
```bash
# 1. Use filters instead of queries when possible (faster)
{
  "query": {
    "bool": {
      "filter": [  # Filters are cached and faster
        {"term": {"event_type": "authentication_failure"}},
        {"range": {"@timestamp": {"gte": "now-1h"}}}
      ]
    }
  }
}

# 2. Limit field retrieval
{
  "query": {"match_all": {}},
  "_source": ["@timestamp", "src_ip", "event_type"]  # Only get needed fields
}

# 3. Use routing for better performance
PUT security-logs-2024.01.15/_doc/1?routing=web-server-01
{
  "host": "web-server-01",
  "event_type": "authentication_failure"
}
```

## 🔧 Administrative Operations

### Cluster Health and Monitoring
```bash
# Check cluster health
curl "localhost:9200/_cluster/health?pretty"

# Get cluster statistics
curl "localhost:9200/_cluster/stats?pretty"

# Check index health
curl "localhost:9200/_cat/indices?v&h=index,health,status,docs.count,store.size"

# Check node information
curl "localhost:9200/_cat/nodes?v"

# Monitor index sizes
curl "localhost:9200/_cat/indices/security-*?v&s=store.size:desc"
```

### Index Management
```bash
# Create index with specific settings
curl -X PUT "localhost:9200/security-test-logs" -H 'Content-Type: application/json' -d'
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "refresh_interval": "1s"
  }
}
'

# Delete old indices
curl -X DELETE "localhost:9200/security-*-2024.01.01"

# Reindex data (for schema changes)
curl -X POST "localhost:9200/_reindex" -H 'Content-Type: application/json' -d'
{
  "source": {
    "index": "security-old-logs"
  },
  "dest": {
    "index": "security-new-logs"
  }
}
'

# Force merge indices (optimize storage)
curl -X POST "localhost:9200/security-*/_forcemerge?max_num_segments=1"
```

### Backup and Restore
```bash
# Create snapshot repository
curl -X PUT "localhost:9200/_snapshot/backup_repo" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/usr/share/elasticsearch/backup"
  }
}
'

# Create snapshot
curl -X PUT "localhost:9200/_snapshot/backup_repo/snapshot_1" -H 'Content-Type: application/json' -d'
{
  "indices": "security-*",
  "ignore_unavailable": true,
  "include_global_state": false
}
'

# Restore snapshot
curl -X POST "localhost:9200/_snapshot/backup_repo/snapshot_1/_restore" -H 'Content-Type: application/json' -d'
{
  "indices": "security-*",
  "ignore_unavailable": true,
  "include_global_state": false
}
'
```

## 🚨 Troubleshooting Common Issues

### Issue 1: Cluster Status Red
```bash
# Check what's wrong
curl "localhost:9200/_cluster/health?level=indices&pretty"
curl "localhost:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason"

# Common solutions:
# 1. Disk space full
df -h
# Clean up old indices or add more storage

# 2. Memory issues
curl "localhost:9200/_nodes/stats/jvm?pretty"
# Increase heap size in docker-compose.yml

# 3. Unassigned shards
curl -X PUT "localhost:9200/problematic-index/_settings" -H 'Content-Type: application/json' -d'
{
  "index": {
    "number_of_replicas": 0
  }
}
'
```

### Issue 2: Search Performance Problems
```bash
# Check slow queries
curl "localhost:9200/_nodes/stats/indices/search?pretty"

# Enable slow query logging
curl -X PUT "localhost:9200/security-*/_settings" -H 'Content-Type: application/json' -d'
{
  "index.search.slowlog.threshold.query.warn": "2s",
  "index.search.slowlog.threshold.query.info": "1s"
}
'

# Optimize queries:
# - Use filters instead of queries
# - Add routing
# - Reduce result size
# - Use specific time ranges
```

### Issue 3: High Memory Usage
```bash
# Check field data usage
curl "localhost:9200/_nodes/stats/indices/fielddata?pretty"

# Check query cache
curl "localhost:9200/_nodes/stats/indices/query_cache?pretty"

# Clear caches
curl -X POST "localhost:9200/_cache/clear"

# Optimize field data
curl -X PUT "localhost:9200/security-*/_settings" -H 'Content-Type: application/json' -d'
{
  "index.fielddata.cache.size": "20%"
}
'
```

## 📈 Production Configuration

### Multi-Node Setup
```yaml
# For production environments
version: '3.8'
services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    environment:
      - node.name=es01
      - cluster.name=security-cluster
      - discovery.seed_hosts=es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    volumes:
      - es01_data:/usr/share/elasticsearch/data

  es02:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    environment:
      - node.name=es02
      - cluster.name=security-cluster
      - discovery.seed_hosts=es01,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    volumes:
      - es02_data:/usr/share/elasticsearch/data

  es03:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    environment:
      - node.name=es03
      - cluster.name=security-cluster
      - discovery.seed_hosts=es01,es02
      - cluster.initial_master_nodes=es01,es02,es03
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    volumes:
      - es03_data:/usr/share/elasticsearch/data
```

### Security Configuration (Production)
```yaml
environment:
  - xpack.security.enabled=true
  - xpack.security.http.ssl.enabled=true
  - xpack.security.transport.ssl.enabled=true
  - ELASTIC_PASSWORD=your-strong-password
```

## 🎯 Real-World Query Examples for Threat Detection

### Brute Force Attack Detection
```bash
curl -X GET "localhost:9200/security-auth-logs-*/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"range": {"@timestamp": {"gte": "now-15m"}}},
        {"term": {"event_type": "authentication_failure"}}
      ]
    }
  },
  "aggs": {
    "by_src_ip": {
      "terms": {"field": "src_ip", "size": 100},
      "aggs": {
        "failure_count": {"value_count": {"field": "src_ip"}},
        "users_targeted": {"cardinality": {"field": "user_name"}},
        "latest_attempt": {"max": {"field": "@timestamp"}}
      }
    }
  }
}
'
```

### Data Exfiltration Detection
```bash
curl -X GET "localhost:9200/security-network-logs-*/_search" -H 'Content-Type: application/json' -d'
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"range": {"@timestamp": {"gte": "now-1h"}}},
        {"range": {"bytes": {"gte": 104857600}}}  // 100MB
      ]
    }
  },
  "aggs": {
    "large_transfers": {
      "terms": {"field": "src_ip"},
      "aggs": {
        "total_bytes": {"sum": {"field": "bytes"}},
        "transfer_count": {"value_count": {"field": "bytes"}},
        "destinations": {"cardinality": {"field": "dst_ip"}}
      }
    }
  }
}
'
```

Elasticsearch serves as the central nervous system of our threat detection platform, providing lightning-fast search capabilities, real-time analytics, and scalable storage for security events. Understanding its architecture and capabilities is crucial for effective threat hunting and security monitoring.