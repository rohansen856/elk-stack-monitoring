# Beats Components Guide

## 🥁 What are Beats?

Beats are like **tiny robots** that sit on your computers and watch everything that happens. They collect different types of information and send it to Logstash for processing. Think of them as security guards with clipboards, writing down everything they see.

```
Computer System
    ↓
📋 Beats (watching and collecting)
    ↓
📨 Send data to Logstash
    ↓
⚙️ Logstash processes the data
    ↓
🗃️ Elasticsearch stores it
```

## 📄 Filebeat - The Log File Watcher

### What is Filebeat?

Filebeat is like a **librarian who reads books** (log files) and tells everyone about interesting stories (events) they find.

### What Does Filebeat Watch?

```
🔍 LINUX SYSTEMS:
/var/log/auth.log          → Login attempts, sudo usage
/var/log/syslog            → General system events
/var/log/kern.log          → Kernel and hardware events
/var/log/apache2/          → Web server logs
/var/log/nginx/            → Web server logs
/var/log/audit/audit.log   → Security audit events

🔍 WINDOWS SYSTEMS:
C:\Windows\System32\LogFiles\    → Various Windows logs
Application Event Logs           → Software events
Security Event Logs              → Security-related events
System Event Logs               → Operating system events
```

### Configuration Example

```yaml
# filebeat.yml
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/auth.log
    - /var/log/syslog
  fields:
    log_type: system_security
  fields_under_root: true

output.logstash:
  hosts: ["logstash:5044"]
```

### What Filebeat Collects for Threat Detection

| Log Type | What it Watches | Security Events Detected |
|----------|-----------------|--------------------------|
| **SSH Logs** | Authentication attempts | Brute force attacks, failed logins |
| **Sudo Logs** | Privilege escalation | Unauthorized admin access |
| **System Logs** | Process creation, file access | Malicious software, data theft |
| **Web Server Logs** | HTTP requests | Web attacks, injection attempts |
| **Audit Logs** | File system changes | Configuration tampering |

### Example Security Events Collected

```bash
# SSH Brute Force Attempt
Jan 15 10:30:15 server1 sshd[1234]: Failed password for admin from 203.0.113.42 port 22

# Sudo Usage (Privilege Escalation)
Jan 15 10:31:20 server1 sudo: username : TTY=pts/0 ; PWD=/home/user ; USER=root ; COMMAND=/bin/cat /etc/shadow

# File Access (Data Theft Attempt)
Jan 15 10:32:10 server1 kernel: audit: USER_TTY pid=1234 uid=0 auid=1000 ses=1 msg='op=PAM:session_open acct="root" exe="/usr/bin/sudo"'
```

## 📊 Metricbeat - The System Monitor

### What is Metricbeat?

Metricbeat is like a **health monitor** that constantly checks your computer's vital signs (CPU, memory, disk space) and reports if anything looks abnormal.

### What Does Metricbeat Monitor?

```
🖥️ SYSTEM METRICS:
CPU Usage              → High CPU might indicate malware
Memory Usage           → Memory spikes could show attacks
Disk Space             → Unusual disk activity
Network Traffic        → Data exfiltration detection
Process Information    → Suspicious processes running

🌐 NETWORK METRICS:
Incoming Connections   → External attack attempts
Outgoing Connections   → Data leaving your network
Bandwidth Usage        → Unusual data transfers
Protocol Statistics    → Abnormal network protocols
```

### Configuration Example

```yaml
# metricbeat.yml
metricbeat.modules:
- module: system
  metricsets:
    - cpu
    - memory
    - network
    - process
    - diskio
  enabled: true
  period: 10s

- module: docker
  metricsets:
    - container
    - cpu
    - diskio
    - memory
    - network
  enabled: true
  period: 10s

output.logstash:
  hosts: ["logstash:5044"]
```

### Security Monitoring with Metricbeat

| Metric Type | Normal Behavior | Suspicious Behavior | Possible Threat |
|-------------|-----------------|---------------------|-----------------|
| **CPU Usage** | 5-30% normal usage | Sudden spikes to 90%+ | Cryptocurrency mining, DDoS |
| **Memory Usage** | Gradual changes | Rapid memory consumption | Memory-based attacks |
| **Network Traffic** | Predictable patterns | Large unexpected transfers | Data exfiltration |
| **Process Count** | Stable number | Many new processes | Malware spreading |
| **Disk I/O** | Regular patterns | Excessive read/write | Data staging, encryption |

### Example Metrics for Threat Detection

```json
{
  "@timestamp": "2024-01-15T10:30:00Z",
  "metricset": {
    "name": "process"
  },
  "process": {
    "name": "powershell.exe",
    "cpu": {
      "pct": 95.5
    },
    "memory": {
      "size": 524288000
    },
    "cmd": "powershell.exe -EncodedCommand JABzAD0ATgBlAHcALQBPAGI..."
  },
  "threat_score": 8
}
```

## 🪟 Winlogbeat - The Windows Expert

### What is Winlogbeat?

Winlogbeat is a **Windows specialist** that understands Windows Event Logs and translates them into useful security information. It's like having a Windows expert who knows exactly what each cryptic Windows error message really means.

### Key Windows Events for Security

| Event ID | Event Type | Security Significance |
|----------|------------|----------------------|
| **4624** | Successful logon | Track who logs in and when |
| **4625** | Failed logon | Brute force detection |
| **4648** | Logon with explicit credentials | Privilege escalation attempts |
| **4672** | Admin privileges assigned | Privilege escalation |
| **4688** | Process creation | Track malicious software |
| **4103/4104** | PowerShell execution | PowerShell-based attacks |
| **4656** | File/object access | Data theft attempts |
| **4657** | Registry modification | System tampering |

### Configuration Example

```yaml
# winlogbeat.yml
winlogbeat.event_logs:
  - name: Security
    event_id: 4624,4625,4648,4672,4688
    level: information,warning,error
  - name: System
    level: error,warning
  - name: Microsoft-Windows-PowerShell/Operational
    event_id: 4103,4104
  - name: Application
    level: error

output.logstash:
  hosts: ["logstash:5044"]
```

### PowerShell Attack Detection

```xml
<!-- Windows Event Log Entry -->
<Event>
  <EventData>
    <Data Name="CommandLine">
      powershell.exe -EncodedCommand JABzAD0ATgBlAHcALQBPAGIAagBlAGMAdA...
    </Data>
    <Data Name="ProcessId">2847</Data>
    <Data Name="User">DOMAIN\attacker</Data>
  </EventData>
</Event>
```

## 🔄 How Beats Work Together

### Data Collection Pipeline

```
STEP 1: COLLECTION
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Filebeat   │  │ Metricbeat  │  │ Winlogbeat  │
│   (Logs)    │  │ (Metrics)   │  │ (Windows)   │
└─────┬───────┘  └─────┬───────┘  └─────┬───────┘
      │                │                │
      └────────────────┼────────────────┘
                       ▼
STEP 2: FORWARDING
              ┌─────────────┐
              │  Logstash   │
              │   :5044     │
              └─────┬───────┘
                    ▼
STEP 3: PROCESSING & STORAGE
              ┌─────────────┐
              │Elasticsearch│
              │   :9200     │
              └─────────────┘
```

### Example: Detecting a Multi-Stage Attack

```
ATTACK SCENARIO: Hacker tries to break in and steal data

STEP 1: INITIAL ACCESS
Filebeat detects: Multiple failed SSH login attempts
→ Event: "Failed password for admin from 203.0.113.42"

STEP 2: PRIVILEGE ESCALATION
Winlogbeat detects: PowerShell execution with admin privileges
→ Event: "Process created: powershell.exe -EncodedCommand ..."

STEP 3: DATA EXFILTRATION
Metricbeat detects: Unusual network traffic spike
→ Metric: "network.bytes_out: 157286400 (150MB in 5 minutes)"

STEP 4: CORRELATION
Threat Detection Engine connects all three events:
→ Alert: "Multi-stage APT attack detected - Risk Score: 10/10"
```

## 🛠️ Installation and Setup

### Linux Installation

```bash
# Install Filebeat
curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.11.0-linux-x86_64.tar.gz
tar xzvf filebeat-8.11.0-linux-x86_64.tar.gz
sudo mv filebeat-8.11.0-linux-x86_64 /opt/filebeat

# Install Metricbeat
curl -L -O https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-8.11.0-linux-x86_64.tar.gz
tar xzvf metricbeat-8.11.0-linux-x86_64.tar.gz
sudo mv metricbeat-8.11.0-linux-x86_64 /opt/metricbeat

# Configure and start
sudo /opt/filebeat/filebeat setup
sudo systemctl start filebeat
sudo systemctl enable filebeat
```

### Windows Installation

```powershell
# Download and install Winlogbeat
Invoke-WebRequest -Uri "https://artifacts.elastic.co/downloads/beats/winlogbeat/winlogbeat-8.11.0-windows-x86_64.zip" -OutFile "winlogbeat.zip"
Expand-Archive .\winlogbeat.zip -DestinationPath C:\ProgramData\Elastic\Beats\

# Setup and start service
.\winlogbeat.exe setup
.\winlogbeat.exe install
Start-Service winlogbeat
```

### Docker Configuration (Current Setup)

```yaml
# From docker-compose.yml
filebeat:
  image: docker.elastic.co/beats/filebeat:8.11.0
  user: root
  volumes:
    - ./filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
    - /var/log:/hostfs/var/log:ro
  depends_on:
    - logstash
  command: filebeat -e -strict.perms=false

metricbeat:
  image: docker.elastic.co/beats/metricbeat:8.11.0
  user: root
  volumes:
    - ./metricbeat/metricbeat.yml:/usr/share/metricbeat/metricbeat.yml:ro
    - /proc:/hostfs/proc:ro
    - /sys/fs/cgroup:/hostfs/sys/fs/cgroup:ro
  depends_on:
    - logstash
  command: metricbeat -e -strict.perms=false
```

## 📈 Performance and Monitoring

### Beat Performance Metrics

```bash
# Check Filebeat status
sudo filebeat test output
sudo filebeat test config

# Monitor Metricbeat
curl http://localhost:5066/stats  # If monitoring enabled

# View beat logs
sudo tail -f /var/log/filebeat/filebeat.log
sudo tail -f /var/log/metricbeat/metricbeat.log
```

### Tuning for High-Volume Environments

```yaml
# High-performance configuration
filebeat.inputs:
- type: log
  paths: ["/var/log/*.log"]
  harvester_buffer_size: 16384
  max_bytes: 10485760

queue.mem:
  events: 8192
  flush.min_events: 2048

output.logstash:
  hosts: ["logstash:5044"]
  bulk_max_size: 2048
  compression_level: 3
```

## 🔐 Security Considerations

### Beat Security Best Practices

1. **Run with minimal privileges**: Only grant necessary file access
2. **Secure communication**: Use TLS for Beat → Logstash communication
3. **Access control**: Limit which logs beats can access
4. **Regular updates**: Keep beats updated for security patches
5. **Monitor beat health**: Ensure beats are running and sending data

### Example Secure Configuration

```yaml
# Secure Filebeat configuration
output.logstash:
  hosts: ["logstash:5044"]
  ssl.enabled: true
  ssl.certificate_authorities: ["/etc/ssl/certs/ca.crt"]
  ssl.certificate: "/etc/ssl/certs/filebeat.crt"
  ssl.key: "/etc/ssl/private/filebeat.key"

logging.level: warning
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  rotateeverybytes: 10485760
  keepfiles: 7
```

## 🚨 Troubleshooting Common Issues

### Filebeat Not Collecting Logs
```bash
# Check file permissions
ls -la /var/log/auth.log
# Ensure filebeat user can read the file

# Check configuration
sudo filebeat test config
sudo filebeat test output

# Verify connectivity to Logstash
telnet logstash-host 5044
```

### Metricbeat High CPU Usage
```yaml
# Reduce collection frequency
metricbeat.modules:
- module: system
  period: 30s  # Instead of 10s
  metricsets: ["cpu", "memory"]  # Collect only essential metrics
```

### Winlogbeat Missing Events
```powershell
# Check Windows Event Log service
Get-Service EventLog
Restart-Service EventLog

# Verify event log access
Get-WinEvent -ListLog Security
Get-WinEvent -LogName Security -MaxEvents 5
```

The Beats components provide comprehensive data collection capabilities, enabling our threat detection system to have full visibility into system activities, performance metrics, and security events across both Linux and Windows environments.