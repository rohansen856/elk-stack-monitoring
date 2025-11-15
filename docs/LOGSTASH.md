# Logstash Deep Dive Guide

## ⚙️ What is Logstash?

Logstash is like a **smart factory worker** who takes raw materials (messy log files) from different suppliers (various systems) and transforms them into finished products (clean, structured data) that can be stored in a warehouse (Elasticsearch).

Think of Logstash as a **universal translator and data cleaner** that:
- Speaks every log format language
- Cleans up messy data
- Adds valuable context (like geographic location)
- Routes data to the right destination
- Works 24/7 without getting tired

## 🏭 Logstash Pipeline Architecture

### The Three-Stage Pipeline

```
INPUT → FILTER → OUTPUT

📥 INPUT STAGE
├── Filebeat (port 5044)
├── Metricbeat (port 5044)
├── TCP input (port 5000)
├── Syslog (port 514)
├── GELF (port 12201)
└── HTTP input (port 8080)
    │
    ▼
🔧 FILTER STAGE
├── Parse log formats (grok)
├── Add geographic data (geoip)
├── Calculate risk scores
├── Extract fields
├── Data validation
└── Enrichment
    │
    ▼
📤 OUTPUT STAGE
├── Elasticsearch (primary)
├── File output (backup)
├── Stdout (debugging)
└── Dead letter queue (errors)
```

### Real-World Data Transformation Example

```
🔍 RAW INPUT:
"Jan 15 14:30:00 web-server-01 sshd[1234]: Failed password for admin from 203.0.113.42 port 22 ssh2"

⚙️ LOGSTASH PROCESSING:
1. Parse timestamp: "Jan 15 14:30:00" → "2024-01-15T14:30:00Z"
2. Extract service: "sshd[1234]" → service="sshd", pid=1234
3. Parse event: "Failed password" → event_type="authentication_failure"
4. Extract IP: "203.0.113.42" → src_ip="203.0.113.42"
5. GeoIP lookup: "203.0.113.42" → country="China", city="Beijing"
6. Risk calculation: external_ip + privileged_account → risk_score=8

📊 CLEAN OUTPUT:
{
  "@timestamp": "2024-01-15T14:30:00Z",
  "host": {"name": "web-server-01"},
  "service": "sshd",
  "process": {"pid": 1234},
  "event_type": "authentication_failure",
  "user_name": "admin",
  "src_ip": "203.0.113.42",
  "src_port": 22,
  "protocol": "ssh2",
  "geo": {
    "country_name": "China",
    "city_name": "Beijing",
    "location": {"lat": 39.9042, "lon": 116.4074}
  },
  "risk_score": 8,
  "threat_indicators": ["external_ip", "privileged_account"],
  "message": "Failed password for admin from 203.0.113.42 port 22 ssh2"
}
```

## 🔧 Configuration in Our System

### Docker Configuration
```yaml
# From docker-compose.yml
logstash:
  image: docker.elastic.co/logstash/logstash:8.11.0
  container_name: logstash
  environment:
    # Java heap size (adjust based on available RAM)
    - "LS_JAVA_OPTS=-Xmx256m -Xms256m"

    # Monitoring settings
    - "XPACK_MONITORING_ELASTICSEARCH_HOSTS=http://elasticsearch:9200"

    # Logging level
    - "LOG_LEVEL=info"

  # Input ports for different data sources
  ports:
    - "5044:5044"   # Beats input (Filebeat, Metricbeat, Winlogbeat)
    - "5000:5000"   # TCP input (application logs)
    - "9600:9600"   # API/monitoring endpoint
    - "514:514/udp" # Syslog UDP (network devices)
    - "514:514/tcp" # Syslog TCP (network devices)
    - "12201:12201" # GELF input (Docker logs)

  # Pipeline configuration
  volumes:
    - ./logstash/pipeline:/usr/share/logstash/pipeline:ro

  # Dependencies
  depends_on:
    elasticsearch:
      condition: service_healthy

  # Health check
  healthcheck:
    test: ["CMD-SHELL", "curl -f http://localhost:9600/_node/stats || exit 1"]
    interval: 30s
    timeout: 10s
    retries: 5
```

### Main Pipeline Configuration
```ruby
# ./logstash/pipeline/logstash.conf

# ========================================
# INPUT SECTION - Data Collection
# ========================================

input {
  # Beats input - Receives data from Filebeat, Metricbeat, Winlogbeat
  beats {
    port => 5044
    host => "0.0.0.0"
  }

  # TCP input - Application logs in JSON format
  tcp {
    port => 5000
    host => "0.0.0.0"
    codec => json_lines
    type => "application_log"
  }

  # Syslog input - Network devices, firewalls, routers
  syslog {
    port => 514
    type => "syslog"
  }

  # GELF input - Docker container logs
  gelf {
    port => 12201
    type => "docker_log"
  }

  # HTTP input - For webhook-based log delivery
  http {
    port => 8080
    type => "http_log"
  }
}

# ========================================
# FILTER SECTION - Data Processing
# ========================================

filter {
  # Add common fields to all events
  mutate {
    add_field => {
      "[@metadata][processed_by]" => "logstash"
      "[@metadata][processed_at]" => "%{+yyyy-MM-dd'T'HH:mm:ss.SSSZ}"
    }
  }

  # Process different log types based on tags or type
  if [fields][log_type] == "auth_log" or "auth" in [tags] {
    # SSH Authentication logs
    if [message] =~ /sshd/ {
      grok {
        match => {
          "message" => "%{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:host_name} %{WORD:service}\[%{POSINT:pid}\]: %{GREEDYDATA:ssh_message}"
        }
      }

      # Parse different SSH events
      if [ssh_message] =~ /Failed password/ {
        grok {
          match => {
            "ssh_message" => "Failed password for %{USER:user_name} from %{IP:src_ip} port %{POSINT:src_port} %{WORD:protocol}"
          }
        }
        mutate {
          add_field => { "event_type" => "authentication_failure" }
          add_field => { "security_event" => "authentication_failure" }
        }
      }

      else if [ssh_message] =~ /Accepted password/ {
        grok {
          match => {
            "ssh_message" => "Accepted password for %{USER:user_name} from %{IP:src_ip} port %{POSINT:src_port} %{WORD:protocol}"
          }
        }
        mutate {
          add_field => { "event_type" => "authentication_success" }
          add_field => { "security_event" => "authentication_success" }
        }
      }
    }

    # Sudo logs
    if [message] =~ /sudo/ {
      grok {
        match => {
          "message" => "%{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:host_name} sudo: %{USER:user_name} : TTY=%{TTY:tty} ; PWD=%{PATH:pwd} ; USER=%{USER:target_user} ; COMMAND=%{GREEDYDATA:command}"
        }
      }
      mutate {
        add_field => { "event_type" => "privilege_escalation" }
        add_field => { "security_event" => "privilege_escalation" }
      }
    }
  }

  # Process network/firewall logs
  if [fields][log_type] == "firewall" or "firewall" in [tags] {
    # UFW firewall logs
    if [message] =~ /\[UFW BLOCK\]/ {
      grok {
        match => {
          "message" => "\[UFW BLOCK\] IN=%{WORD:interface} OUT= MAC=%{MAC:mac} SRC=%{IP:src_ip} DST=%{IP:dst_ip} LEN=%{INT:packet_length} TOS=%{BASE16NUM:tos} PREC=%{BASE16NUM:prec} TTL=%{INT:ttl} ID=%{INT:id} PROTO=%{WORD:protocol} SPT=%{INT:src_port} DPT=%{INT:dst_port}"
        }
      }
      mutate {
        add_field => { "event_type" => "firewall_block" }
        add_field => { "security_event" => "network_block" }
        add_field => { "action" => "DENY" }
      }
    }
  }

  # Process application logs from our FastAPI app
  if [type] == "application_log" {
    # Parse structured JSON logs
    if [level] == "ERROR" {
      mutate {
        add_field => { "event_type" => "application_error" }
        add_field => { "security_event" => "application_error" }
      }
    }

    if [message] =~ /Failed login attempt/ {
      mutate {
        add_field => { "event_type" => "authentication_failure" }
        add_field => { "security_event" => "authentication_failure" }
      }
    }
  }

  # Add geographic information for IP addresses
  if [src_ip] {
    geoip {
      source => "src_ip"
      target => "geo"
      database => "/usr/share/logstash/vendor/geoip/GeoLite2-City.mmdb"
    }
  }

  # Calculate risk scores based on various factors
  if [security_event] {
    ruby {
      code => "
        risk_score = 1
        threat_indicators = []

        # External IP increases risk
        src_ip = event.get('src_ip')
        if src_ip && !src_ip.start_with?('192.168.', '10.', '172.')
          risk_score += 3
          threat_indicators << 'external_ip'
        end

        # Privileged accounts increase risk
        user = event.get('user_name')
        if user && ['admin', 'root', 'administrator'].include?(user.downcase)
          risk_score += 2
          threat_indicators << 'privileged_account'
        end

        # Off-hours access increases risk (example: 10 PM to 6 AM UTC)
        hour = Time.now.hour
        if hour >= 22 || hour <= 6
          risk_score += 1
          threat_indicators << 'off_hours'
        end

        # Suspicious commands increase risk
        command = event.get('command')
        if command
          suspicious_patterns = ['cat /etc/passwd', 'cat /etc/shadow', 'nc -', 'wget', 'curl']
          suspicious_patterns.each do |pattern|
            if command.include?(pattern)
              risk_score += 3
              threat_indicators << 'suspicious_command'
              break
            end
          end
        end

        # Failed authentication gets base risk
        if event.get('security_event') == 'authentication_failure'
          risk_score += 1
        end

        # Cap risk score at 10
        risk_score = [risk_score, 10].min

        event.set('risk_score', risk_score)
        event.set('threat_indicators', threat_indicators) unless threat_indicators.empty?
      "
    }
  }

  # Parse timestamp
  if [timestamp] {
    date {
      match => [ "timestamp", "MMM dd HH:mm:ss", "MMM  d HH:mm:ss" ]
      target => "@timestamp"
    }
  }

  # Clean up fields
  mutate {
    remove_field => [ "message", "host" ]
    convert => {
      "src_port" => "integer"
      "dst_port" => "integer"
      "pid" => "integer"
      "risk_score" => "integer"
    }
  }

  # Add log category for better organization
  if [security_event] {
    if [security_event] =~ /authentication/ {
      mutate { add_field => { "log_category" => "authentication" } }
    }
    else if [security_event] =~ /network/ {
      mutate { add_field => { "log_category" => "network" } }
    }
    else if [security_event] =~ /privilege/ {
      mutate { add_field => { "log_category" => "privilege_escalation" } }
    }
    else {
      mutate { add_field => { "log_category" => "general_security" } }
    }
  }
}

# ========================================
# OUTPUT SECTION - Data Routing
# ========================================

output {
  # Primary output - Send to Elasticsearch
  elasticsearch {
    hosts => ["elasticsearch:9200"]

    # Route to different indices based on log type
    index => "security-%{[log_category]}-logs-%{+yyyy.MM.dd}"

    # Use document ID to prevent duplicates
    document_id => "%{[@metadata][fingerprint]}"

    # Template for index settings
    template_name => "security-logs"
    template => "/usr/share/logstash/templates/security-logs.json"
    template_overwrite => true
  }

  # High-risk events get special handling
  if [risk_score] >= 8 {
    elasticsearch {
      hosts => ["elasticsearch:9200"]
      index => "security-alerts-%{+yyyy.MM.dd}"
    }
  }

  # Debug output (remove in production)
  if [log_level] == "debug" {
    stdout {
      codec => rubydebug
    }
  }

  # Backup to file for critical events
  if [risk_score] >= 9 {
    file {
      path => "/usr/share/logstash/logs/critical-events-%{+yyyy-MM-dd}.log"
      codec => json_lines
    }
  }
}
```

## 📊 Advanced Processing Patterns

### Pattern 1: Multi-line Log Processing
```ruby
# Handle Java stack traces and multi-line logs
input {
  file {
    path => "/var/log/application.log"
    codec => multiline {
      pattern => "^%{TIMESTAMP_ISO8601}"
      negate => true
      what => "previous"
    }
  }
}

filter {
  if [message] =~ /Exception|Error/ {
    mutate {
      add_field => { "event_type" => "application_error" }
      add_field => { "severity" => "high" }
    }
  }
}
```

### Pattern 2: Data Enrichment
```ruby
# Enrich events with threat intelligence
filter {
  # Check against known malicious IPs
  translate {
    field => "src_ip"
    destination => "threat_intel"
    dictionary_path => "/usr/share/logstash/config/malicious_ips.yml"
    fallback => "clean"
  }

  if [threat_intel] != "clean" {
    mutate {
      add_field => { "threat_detected" => "true" }
      replace => { "risk_score" => "10" }
    }
  }

  # Add asset information
  translate {
    field => "dst_ip"
    destination => "asset_info"
    dictionary => {
      "192.168.1.100" => "web-server"
      "192.168.1.200" => "database-server"
      "192.168.1.50"  => "domain-controller"
    }
    fallback => "unknown"
  }
}
```

### Pattern 3: Correlation and State Tracking
```ruby
# Track failed login attempts per IP
filter {
  if [security_event] == "authentication_failure" {
    aggregate {
      task_id => "%{src_ip}"
      code => "
        map['failed_attempts'] ||= 0
        map['failed_attempts'] += 1
        map['first_seen'] ||= event.get('@timestamp')
        map['last_seen'] = event.get('@timestamp')
        map['users_targeted'] ||= []
        map['users_targeted'] << event.get('user_name')
        map['users_targeted'].uniq!
      "
      push_map_as_event_on_timeout => true
      timeout_task_id_field => "src_ip"
      timeout => 300  # 5 minutes
      timeout_tags => ['brute_force_analysis']
    }
  }

  if "brute_force_analysis" in [tags] {
    if [failed_attempts] >= 5 {
      mutate {
        add_field => { "attack_type" => "brute_force" }
        add_field => { "severity" => "high" }
        replace => { "risk_score" => "10" }
      }
    }
  }
}
```

## 🔍 Input Plugin Details

### Beats Input (Primary)
```ruby
input {
  beats {
    port => 5044
    host => "0.0.0.0"

    # Client authentication (production)
    ssl => true
    ssl_certificate_authorities => ["/path/to/ca.crt"]
    ssl_certificate => "/path/to/server.crt"
    ssl_key => "/path/to/server.key"
    ssl_verify_mode => "peer"

    # Connection limits
    congestion_threshold => 40
    target_field_for_codec => "message"
  }
}
```

### TCP Input for Application Logs
```ruby
input {
  tcp {
    port => 5000
    host => "0.0.0.0"
    codec => json_lines
    type => "application_log"

    # Add metadata
    add_field => {
      "[@metadata][input_type]" => "tcp"
      "[@metadata][received_at]" => "%{+yyyy-MM-dd'T'HH:mm:ss.SSSZ}"
    }
  }
}
```

### Syslog Input for Network Devices
```ruby
input {
  syslog {
    port => 514
    host => "0.0.0.0"
    type => "syslog"

    # Syslog parsing
    use_labels => true
    facility_labels => [
      "kern", "user", "mail", "daemon", "auth", "syslog",
      "lpr", "news", "uucp", "cron", "authpriv", "ftp",
      "ntp", "audit", "alert", "clock", "local0", "local1",
      "local2", "local3", "local4", "local5", "local6", "local7"
    ]
  }
}
```

## 🛠️ Filter Plugin Masterclass

### Grok Patterns for Security Logs
```ruby
# Custom grok patterns for our security logs
filter {
  # SSH login patterns
  grok {
    patterns_dir => "/usr/share/logstash/patterns"
    match => {
      "message" => [
        "%{SSH_FAILED_LOGIN}",
        "%{SSH_SUCCESSFUL_LOGIN}",
        "%{SSH_DISCONNECT}",
        "%{SUDO_COMMAND}"
      ]
    }
  }
}

# Custom patterns file (/usr/share/logstash/patterns/security)
SSH_FAILED_LOGIN %{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:host} sshd\[%{POSINT:pid}\]: Failed password for (?<user_name>invalid user )?%{USERNAME:target_user} from %{IP:src_ip} port %{POSINT:src_port} %{WORD:protocol}

SSH_SUCCESSFUL_LOGIN %{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:host} sshd\[%{POSINT:pid}\]: Accepted password for %{USERNAME:user_name} from %{IP:src_ip} port %{POSINT:src_port} %{WORD:protocol}

SUDO_COMMAND %{SYSLOGTIMESTAMP:timestamp} %{HOSTNAME:host} sudo: %{USERNAME:user_name} : TTY=%{TTY:tty} ; PWD=%{PATH:pwd} ; USER=%{USERNAME:target_user} ; COMMAND=%{GREEDYDATA:command}
```

### Conditional Processing
```ruby
filter {
  # Process based on source system
  if [beat][hostname] == "web-server-01" {
    mutate { add_field => { "asset_type" => "web_server" } }
    mutate { add_field => { "criticality" => "high" } }
  }
  else if [beat][hostname] =~ /^db-/ {
    mutate { add_field => { "asset_type" => "database" } }
    mutate { add_field => { "criticality" => "critical" } }
  }

  # Process based on event type
  if [event_type] == "authentication_failure" {
    # Check if this is a known bad actor
    cidr {
      address => [ "%{src_ip}" ]
      network => [ "192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12" ]
      add_tag => [ "internal_network" ]
    }

    if "internal_network" not in [tags] {
      mutate {
        add_field => { "threat_level" => "medium" }
        add_tag => [ "external_threat" ]
      }
    }
  }
}
```

### Data Validation and Cleaning
```ruby
filter {
  # Validate required fields
  if ![src_ip] {
    drop { }
  }

  # Clean up IP addresses
  if [src_ip] {
    mutate {
      gsub => [ "src_ip", "\.0+", "." ]  # Remove leading zeros
    }
  }

  # Normalize usernames
  if [user_name] {
    mutate {
      lowercase => [ "user_name" ]
      strip => [ "user_name" ]
    }
  }

  # Remove sensitive data
  mutate {
    remove_field => [ "password", "token", "secret" ]
  }

  # Convert data types
  mutate {
    convert => {
      "src_port" => "integer"
      "dst_port" => "integer"
      "bytes" => "integer"
      "duration" => "float"
    }
  }
}
```

## 📤 Output Plugin Configuration

### Elasticsearch Output with Advanced Features
```ruby
output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]

    # Dynamic index routing
    index => "security-%{[log_category]}-%{+yyyy.MM.dd}"

    # Document routing for better performance
    routing => "%{host}"

    # Handle failures
    manage_template => true
    template_name => "security"
    template_pattern => "security-*"
    template_overwrite => true

    # Retry logic
    retry_on_conflict => 3
    retry_on_failure => 5
    retry_max_interval => 5

    # Performance tuning
    flush_size => 1000
    idle_flush_time => 1
  }
}
```

### Conditional Outputs
```ruby
output {
  # Regular security events go to main index
  if [log_category] {
    elasticsearch {
      hosts => ["elasticsearch:9200"]
      index => "security-%{[log_category]}-logs-%{+yyyy.MM.dd}"
    }
  }

  # High-risk events get special treatment
  if [risk_score] >= 8 {
    elasticsearch {
      hosts => ["elasticsearch:9200"]
      index => "security-alerts-%{+yyyy.MM.dd}"
    }

    # Also send to external SIEM
    tcp {
      host => "siem.company.com"
      port => 514
      codec => json_lines
    }
  }

  # Critical events get immediate backup
  if [risk_score] >= 9 {
    file {
      path => "/usr/share/logstash/logs/critical-%{+yyyy-MM-dd}.log"
      codec => json_lines
    }
  }

  # Dead letter queue for failed events
  if "_grokparsefailure" in [tags] {
    elasticsearch {
      hosts => ["elasticsearch:9200"]
      index => "logstash-failures-%{+yyyy.MM.dd}"
    }
  }
}
```

## 📊 Monitoring and Performance

### Pipeline Monitoring
```bash
# Check pipeline stats
curl "http://localhost:9600/_node/stats/pipelines?pretty"

# Check JVM stats
curl "http://localhost:9600/_node/stats/jvm?pretty"

# Check process stats
curl "http://localhost:9600/_node/stats/process?pretty"

# Check events stats
curl "http://localhost:9600/_node/stats/events?pretty"
```

### Performance Tuning
```ruby
# logstash.yml configuration
pipeline:
  workers: 4  # Number of worker threads
  batch:
    size: 1000  # Events per batch
    delay: 50   # Batch timeout in ms

queue:
  type: persisted
  path: /usr/share/logstash/data/queue
  max_bytes: 1gb

config:
  reload:
    automatic: true
    interval: 3s
```

### Memory Management
```yaml
# In docker-compose.yml
environment:
  # Heap size should be 50% of container memory
  - "LS_JAVA_OPTS=-Xmx2g -Xms2g"

  # Use G1GC for better performance
  - "LS_JAVA_OPTS=-XX:+UseG1GC"
```

## 🚨 Troubleshooting Common Issues

### Issue 1: Pipeline Not Starting
```bash
# Check configuration syntax
docker-compose exec logstash bin/logstash --config.test_and_exit

# Check logs
docker-compose logs logstash

# Common problems:
# 1. Syntax errors in configuration
# 2. Port conflicts
# 3. Insufficient memory
# 4. Missing dependencies
```

### Issue 2: Events Not Processing
```bash
# Check input statistics
curl "localhost:9600/_node/stats/pipelines" | jq '.pipelines.main.plugins.inputs'

# Check filter statistics
curl "localhost:9600/_node/stats/pipelines" | jq '.pipelines.main.plugins.filters'

# Enable debug logging
# In logstash.yml:
log.level: debug
```

### Issue 3: High Memory Usage
```bash
# Check memory usage
curl "localhost:9600/_node/stats/jvm" | jq '.jvm.mem'

# Solutions:
# 1. Increase heap size
# 2. Reduce batch size
# 3. Add more workers
# 4. Optimize filters

# Monitor garbage collection
curl "localhost:9600/_node/stats/jvm" | jq '.jvm.gc'
```

### Issue 4: Parsing Failures
```ruby
# Add error handling to filters
filter {
  grok {
    match => { "message" => "%{SYSLOGLINE}" }
    tag_on_failure => ["_grokparsefailure"]
  }

  if "_grokparsefailure" in [tags] {
    mutate {
      add_field => { "parsing_error" => "true" }
      add_field => { "original_message" => "%{message}" }
    }
  }
}
```

## 🎯 Real-World Processing Examples

### Example 1: Brute Force Detection Pipeline
```ruby
filter {
  # Track failed attempts
  if [event_type] == "authentication_failure" {
    aggregate {
      task_id => "%{src_ip}"
      code => "
        map['attempts'] ||= 0
        map['attempts'] += 1
        map['start_time'] ||= event.get('@timestamp')

        # Check if this qualifies as brute force
        time_diff = (Time.parse(event.get('@timestamp')) - Time.parse(map['start_time'])) / 60

        if map['attempts'] >= 5 && time_diff <= 15
          event.set('brute_force_detected', true)
          event.set('attack_duration_minutes', time_diff)
          event.set('total_attempts', map['attempts'])
        end
      "
      timeout => 900  # 15 minutes
      timeout_tags => ['attack_analysis_complete']
    }
  }
}
```

### Example 2: PowerShell Attack Detection
```ruby
filter {
  if [log_type] == "powershell" {
    # Check for suspicious patterns
    if [command_line] {
      ruby {
        code => "
          command = event.get('command_line').downcase
          suspicious_indicators = []

          # Check for encoding
          if command.include?('-encodedcommand') || command.include?('-enc')
            suspicious_indicators << 'encoded_command'
          end

          # Check for download attempts
          if command.include?('downloadstring') || command.include?('webclient')
            suspicious_indicators << 'download_attempt'
          end

          # Check for bypass attempts
          if command.include?('-bypass') || command.include?('-unrestricted')
            suspicious_indicators << 'policy_bypass'
          end

          if !suspicious_indicators.empty?
            event.set('powershell_indicators', suspicious_indicators)
            event.set('risk_score', 9)
            event.set('event_type', 'powershell_attack')
          end
        "
      }
    }
  }
}
```

Logstash serves as the intelligent data processing engine of our threat detection system, transforming raw logs into actionable security intelligence. Its flexible pipeline architecture and powerful processing capabilities make it essential for real-time threat detection and security monitoring.