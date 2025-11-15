# APT Detection and Monitoring Guide

## Overview

This enhanced ELK stack configuration provides comprehensive Advanced Persistent Threat (APT) detection capabilities through centralized log collection and analysis.

## Log Sources Covered

### 1. Authentication Logs 🔐
**Sources**: SSH, System login, Windows Security Events
**Detection**:
- Failed login attempts from unusual locations
- Off-hours authentication
- Privileged account usage
- Multiple failed attempts (brute force)

**Key Events**:
- SSH failures: `Failed password for user from IP`
- Windows logon events: Event IDs 4624, 4625
- Sudo usage and privilege escalation

### 2. Network Traffic Logs 🌐
**Sources**: Firewall logs, Syslog from network devices
**Detection**:
- Blocked connections from suspicious IPs
- Unusual outbound connections
- Geographic anomalies in traffic

**Key Events**:
- UFW/iptables blocks
- Cisco ASA deny logs
- pfSense firewall events

### 3. Process Creation Logs ⚙️
**Sources**: System logs, Sysmon, Windows Security Events
**Detection**:
- Unusual process executions
- PowerShell script execution
- Service creation/modification
- Scheduled task creation

**Key Events**:
- Windows Event ID 4688 (Process Creation)
- Sysmon Event ID 1 (Process Creation)
- Task Scheduler events

### 4. File Access Logs 📁
**Sources**: Audit logs, Windows Security Events
**Detection**:
- Access to sensitive files
- File modification tracking
- Registry changes
- Executable file creation

**Key Events**:
- Linux auditd logs
- Windows Event IDs 4656, 4657, 4663 (File Access)

## Index Structure

The ELK stack routes logs to specialized indices for optimal search and analysis:

- `security-auth-logs-*` - Authentication and login events
- `security-network-logs-*` - Network and firewall events
- `security-audit-logs-*` - File access and audit events
- `windows-security-logs-*` - Windows Event Log data
- `application-logs-*` - Application-specific logs
- `system-logs-*` - General system events

## Risk Scoring

Events are automatically assigned risk scores:

- **1-2**: Normal activity (successful logins, routine processes)
- **3-4**: Moderate risk (blocked connections, failed logins)
- **5-6**: High risk (multiple failures, privilege escalation)
- **7-8**: Critical risk (external admin access, suspicious processes)
- **9-10**: Emergency (confirmed malicious activity)

## APT Detection Scenarios

### Scenario 1: Credential Stuffing Attack
**Detection Pattern**:
```
security_event: "authentication_failure"
AND risk_score: >= 5
AND src_ip: external
```

**Indicators**:
- Multiple authentication failures from same IP
- Attempts against multiple usernames
- Geographic anomalies (login from unusual countries)

### Scenario 2: Lateral Movement
**Detection Pattern**:
```
security_event: "authentication_success"
AND logon_type: "3" (Network)
AND privileged_account: true
AND time: 02:00-06:00
```

**Indicators**:
- Successful network logins with admin accounts
- Off-hours activity
- Movement between systems

### Scenario 3: Persistence Mechanisms
**Detection Pattern**:
```
security_event: "scheduled_task"
OR security_event: "service_creation"
AND risk_score: >= 4
```

**Indicators**:
- New scheduled tasks created
- Service installations
- Registry modifications for persistence

### Scenario 4: Data Exfiltration
**Detection Pattern**:
```
log_category: "network_security"
AND protocol: "HTTPS"
AND data_size: > 100MB
AND time: off_hours
```

**Indicators**:
- Large data transfers
- Unusual outbound connections
- Access to file shares outside normal patterns

## Kibana Dashboards

### APT Detection Overview
- **Authentication Failures Map**: Geographic view of failed logins
- **High Risk Events Timeline**: Temporal analysis of security events
- **Security Events Table**: Detailed investigation view

### Key Visualizations
1. **Geographic Risk Map**: Shows authentication attempts by country
2. **Timeline Analysis**: Security events over time with risk scoring
3. **User Behavior Analysis**: Tracks user activity patterns
4. **Network Traffic Analysis**: Monitors unusual network activity
5. **Process Execution Monitoring**: Tracks suspicious process creation

## Configuration Files

### Filebeat Configuration
- **Location**: `./filebeat/filebeat.yml`
- **Purpose**: Collects system logs, SSH logs, audit logs
- **Covers**: Authentication, system processes, file access

### Logstash Pipeline
- **Location**: `./logstash/pipeline/logstash.conf`
- **Purpose**: Processes and enriches logs with GeoIP and risk scoring
- **Features**: Pattern matching, field extraction, categorization

### Winlogbeat Configuration (Windows)
- **Location**: `./winlogbeat/winlogbeat.yml`
- **Purpose**: Collects Windows Event Logs
- **Covers**: Security events, PowerShell logs, Sysmon data

## Deployment Instructions

### 1. Start the Enhanced ELK Stack
```bash
# Start all services
docker-compose up -d

# Verify services are healthy
docker-compose ps
```

### 2. Configure Log Shipping

#### For Linux Systems:
```bash
# Install and configure Filebeat on target systems
sudo filebeat modules enable system
sudo filebeat setup
sudo systemctl start filebeat
```

#### For Windows Systems:
```powershell
# Install and configure Winlogbeat
& "C:\Program Files\Winlogbeat\winlogbeat.exe" setup
Start-Service winlogbeat
```

#### For Network Devices:
Configure syslog forwarding to your ELK server:
```
# Cisco ASA example
logging host 192.168.1.100
logging trap informational

# pfSense example
System > Advanced > Remote Logging
Remote log servers: 192.168.1.100:514
```

### 3. Import Dashboards
```bash
# Import security dashboards
curl -X POST "localhost:5601/api/saved_objects/_import" \
  -H "kbn-xsrf: true" \
  -F "file=@kibana/dashboards/apt-detection-dashboard.json"
```

## Monitoring and Alerting

### High-Priority Alerts
1. **Multiple Authentication Failures** (>10 in 5 minutes)
2. **External Admin Login** (Admin account from external IP)
3. **Off-Hours Activity** (Activity during 2-6 AM)
4. **Privilege Escalation** (sudo/runas events)
5. **Suspicious Process Creation** (PowerShell, cmd.exe with scripts)

### Alert Configuration
Create Watcher alerts in Elasticsearch:
```json
{
  "trigger": {
    "schedule": {
      "interval": "5m"
    }
  },
  "input": {
    "search": {
      "request": {
        "indices": ["security-*"],
        "body": {
          "query": {
            "bool": {
              "must": [
                {"range": {"@timestamp": {"gte": "now-5m"}}},
                {"range": {"risk_score": {"gte": 6}}}
              ]
            }
          }
        }
      }
    }
  },
  "condition": {
    "compare": {
      "ctx.payload.hits.total": {
        "gt": 0
      }
    }
  },
  "actions": {
    "send_email": {
      "email": {
        "to": ["security@company.com"],
        "subject": "High-Risk Security Event Detected",
        "body": "{{ctx.payload.hits.total}} high-risk security events detected in the last 5 minutes."
      }
    }
  }
}
```

## Threat Hunting Queries

### Hunt for APT Activity
```
# Unusual authentication patterns
security_event:"authentication_failure" AND geoip.country_name:(China OR Russia OR Iran)

# PowerShell execution monitoring
log_category:"powershell_execution" AND (encoded OR -enc OR bypass)

# Persistence mechanisms
security_event:"scheduled_task" OR security_event:"service_creation"

# Lateral movement indicators
logon_type:"3" AND successful_user:admin* AND @timestamp:[now-1h TO now]
```

## Performance Optimization

### Index Management
- **Hot indices**: Last 7 days (high-performance SSD)
- **Warm indices**: 8-30 days (standard storage)
- **Cold indices**: 31-365 days (cheap storage)
- **Frozen indices**: >365 days (archive storage)

### Resource Requirements
- **Elasticsearch**: 8GB RAM minimum, 16GB recommended
- **Logstash**: 4GB RAM minimum
- **Kibana**: 2GB RAM minimum
- **Storage**: 1TB minimum for 30 days retention

## Security Best Practices

1. **Enable Authentication**: Configure Elasticsearch security
2. **Use HTTPS**: Enable TLS for all communications
3. **Network Segmentation**: Isolate ELK stack in secure network
4. **Regular Updates**: Keep ELK stack updated
5. **Access Control**: Implement role-based access control
6. **Log Integrity**: Consider log signing/encryption
7. **Backup Strategy**: Regular snapshots of indices

## Troubleshooting

### Common Issues
1. **High CPU Usage**: Reduce Logstash workers or add more nodes
2. **Memory Issues**: Increase JVM heap size
3. **Disk Space**: Implement index lifecycle management
4. **Network Latency**: Optimize network between components

### Debug Commands
```bash
# Check Elasticsearch cluster health
curl "localhost:9200/_cluster/health?pretty"

# View Logstash processing stats
curl "localhost:9600/_node/stats?pretty"

# Check index sizes
curl "localhost:9200/_cat/indices?v&s=store.size:desc"
```

This comprehensive setup provides enterprise-grade APT detection capabilities, enabling security teams to identify and respond to advanced threats across their infrastructure.