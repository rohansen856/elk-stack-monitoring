# Monitor Real Workstation Traffic for OTX Detection

## Overview

This guide shows how to monitor **actual network traffic** from your workstation (laptop/PC) so that when you access malicious IPs like `194.11.246.101` in your browser, it will trigger alerts in your ELK stack.

## Architecture

```
Your Workstation Browser
    ↓ (makes connection to 194.11.246.101)
Packetbeat (monitors network traffic)
    ↓ (sends events to)
Logstash (TCP port 5000)
    ↓ (enriches with OTX threat intel)
Elasticsearch (security-* indices)
    ↓ (scanned by)
Detection Rules
    ↓ (generates)
Security Alerts in Kibana
```

---

## Method 1: Packetbeat (Network Traffic Monitoring)

### Installation

**On Ubuntu/Debian**:
```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
sudo apt-get install apt-transport-https
echo "deb https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list
sudo apt-get update
sudo apt-get install packetbeat
```

**On macOS**:
```bash
brew tap elastic/tap
brew install elastic/tap/packetbeat-full
```

**On Windows**:
Download from: https://www.elastic.co/downloads/beats/packetbeat

### Configuration

Edit `/etc/packetbeat/packetbeat.yml`:

```yaml
# ===================================================================
# Packetbeat Configuration - Monitor Browser Traffic for OTX IPs
# ===================================================================

packetbeat.interfaces.device: any

# Monitor HTTP/HTTPS traffic (browser connections)
packetbeat.protocols.http:
  ports: [80, 8080, 8000, 5000, 8002]
  send_request: true
  send_response: true
  include_body_for: ["text/html", "application/json"]

packetbeat.protocols.tls:
  ports: [443, 8443]
  send_certificates: true

# Monitor DNS queries
packetbeat.protocols.dns:
  ports: [53]
  include_authorities: true
  include_additionals: true

# Add workstation metadata
processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_cloud_metadata: ~
  - add_docker_metadata: ~

  # Add custom fields
  - add_fields:
      target: ''
      fields:
        source_system: workstation
        monitored_by: packetbeat

# Output to Logstash (for threat enrichment)
output.logstash:
  hosts: ["localhost:5044"]  # Or your ELK server IP

  # If Logstash is on different machine:
  # hosts: ["192.168.1.10:5044"]

# Logging
logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/packetbeat
  name: packetbeat
  keepfiles: 7
  permissions: 0644
```

### Start Packetbeat

```bash
# Ubuntu/Debian
sudo systemctl start packetbeat
sudo systemctl enable packetbeat
sudo systemctl status packetbeat

# macOS
sudo packetbeat -e -c /usr/local/etc/packetbeat/packetbeat.yml

# Windows (as Administrator)
.\packetbeat.exe -e -c packetbeat.yml
```

### Test It

```bash
# 1. Open browser and navigate to the OTX malicious IP
# http://194.11.246.101
# (This will likely timeout/fail, but Packetbeat will log the attempt)

# 2. Check if event was captured
curl -s -u elastic:elastic123 \
  "http://localhost:9200/security-*/_search?q=destination.ip:194.11.246.101&size=1&sort=@timestamp:desc&pretty" \
  | grep -A20 "destination"

# 3. Wait 2 minutes for rule to execute
sleep 120

# 4. Check for alert
curl -s -u elastic:elastic123 \
  "http://localhost:9200/.internal.alerts-*/_search?q=194.11.246.101&size=1&pretty" \
  | grep "kibana.alert.rule.name"
```

---

## Method 2: Browser Extension + Webhook (Simpler)

### Use a Browser Extension to Log Requests

**Chrome Extension: Network Logger**
1. Install extension that logs network requests
2. Configure webhook to send to: `http://localhost:5000`
3. Format as JSON matching Logstash expectations

**Example webhook payload**:
```json
{
  "@timestamp": "2025-12-09T10:30:00Z",
  "source": {
    "ip": "YOUR_WORKSTATION_IP",
    "port": 54321
  },
  "destination": {
    "ip": "194.11.246.101",
    "port": 443
  },
  "message": "Browser navigated to http://194.11.246.101",
  "event_type": "http_request",
  "user_agent": "Mozilla/5.0...",
  "url": "http://194.11.246.101/"
}
```

---

## Method 3: Proxy-Based Monitoring

### Configure System Proxy to Log Traffic

**Step 1: Set up mitmproxy**

```bash
# Install mitmproxy
pip install mitmproxy

# Create script to forward to Logstash
cat > mitm_to_logstash.py << 'EOF'
import json
import socket
from datetime import datetime
from mitmproxy import http

LOGSTASH_HOST = "localhost"
LOGSTASH_PORT = 5000

def request(flow: http.HTTPFlow) -> None:
    event = {
        "@timestamp": datetime.utcnow().isoformat() + "Z",
        "source": {
            "ip": flow.client_conn.peername[0],
            "port": flow.client_conn.peername[1]
        },
        "destination": {
            "ip": flow.server_conn.address[0] if flow.server_conn.address else "unknown",
            "port": flow.server_conn.address[1] if flow.server_conn.address else 0
        },
        "message": f"Browser request to {flow.request.pretty_url}",
        "event_type": "http_request",
        "method": flow.request.method,
        "url": flow.request.pretty_url,
        "user_agent": flow.request.headers.get("User-Agent", "")
    }

    # Send to Logstash
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.connect((LOGSTASH_HOST, LOGSTASH_PORT))
        sock.sendall((json.dumps(event) + "\n").encode())
        sock.close()
    except Exception as e:
        print(f"Error sending to Logstash: {e}")
EOF

# Start mitmproxy with the script
mitmproxy -s mitm_to_logstash.py
```

**Step 2: Configure browser to use proxy**

```
Proxy: localhost:8080
```

**Step 3: Access the malicious IP**

Navigate to `http://194.11.246.101` in your browser - the request will be logged and sent to Logstash.

---

## Method 4: DNS Monitoring (Detect Domain Lookups)

### Monitor DNS Queries for Malicious Domains

**Install and Configure dnstap**

```bash
# On Linux with systemd-resolved
sudo apt-get install dnstap
sudo systemctl start dnstap
```

**Configure to send to Logstash**:

```yaml
# dnstap-to-logstash config
input:
  type: dnstap
  socket: /var/run/dnstap.sock

output:
  type: logstash
  host: localhost
  port: 5044
```

---

## Recommended Approach for Testing

**Don't actually browse to the malicious IP!** Instead:

### Safe Testing Method

```bash
# Simulate the browser request without actually connecting
printf '{"@timestamp":"%s","source":{"ip":"'$(hostname -I | awk '{print $1}')'","port":54321},"destination":{"ip":"194.11.246.101","port":443},"message":"Simulated browser request to OTX malicious IP","event_type":"http_request","method":"GET","url":"http://194.11.246.101/","user_agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"}\n' "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')" | nc -w1 localhost 5000

echo "✓ Simulated browser event sent to Logstash"
echo "⏳ Waiting 2 minutes for detection rule to execute..."
sleep 120

echo "🔍 Checking for alert..."
curl -s -u elastic:elastic123 \
  "http://localhost:9200/.internal.alerts-*/_search?pretty" \
  -H 'Content-Type: application/json' -d '{
  "query": {
    "bool": {
      "must": [
        {"term": {"destination.ip": "194.11.246.101"}},
        {"range": {"@timestamp": {"gte": "now-5m"}}}
      ]
    }
  },
  "size": 1,
  "sort": [{"@timestamp": "desc"}]
}' | grep -E "kibana.alert.rule.name|destination.ip|kibana.alert.reason"
```

---

## Security Considerations

⚠️ **WARNING**: Do NOT actually browse to malicious IPs!

- **194.11.246.101** is flagged by AlienVault OTX as malicious
- Visiting it could expose your system to:
  - Malware downloads
  - Exploit kits
  - Drive-by downloads
  - Phishing attacks

**For testing purposes**:
1. ✅ Use the test script: `./scripts/test-detection-rules.sh`
2. ✅ Send simulated events via netcat
3. ❌ Don't actually connect to malicious IPs
4. ❌ Don't disable browser security features

---

## Summary

| Method | Detects Real Traffic | Complexity | Safe for Testing |
|--------|---------------------|------------|------------------|
| **Test Script** | ❌ No (simulated) | ⭐ Easy | ✅ Yes |
| **Packetbeat** | ✅ Yes | ⭐⭐⭐ Medium | ⚠️ Use in isolated network |
| **Browser Extension** | ✅ Yes | ⭐⭐ Easy-Medium | ⚠️ Limited |
| **Proxy (mitmproxy)** | ✅ Yes | ⭐⭐⭐⭐ Advanced | ⚠️ Requires SSL cert |
| **DNS Monitoring** | ✅ Yes (DNS only) | ⭐⭐⭐ Medium | ✅ Safe |

**Recommended for Production**: Packetbeat + DNS monitoring
**Recommended for Testing**: Test script (`./scripts/test-detection-rules.sh`)

---

## Quick Test Right Now

```bash
# Send a simulated browser connection event
printf '{"@timestamp":"%s","source":{"ip":"192.168.1.100","port":54321},"destination":{"ip":"194.11.246.101","port":80},"message":"Browser GET request to http://194.11.246.101/","event_type":"http_request","method":"GET","url":"http://194.11.246.101/"}\n' "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')" | nc -w1 localhost 5000 && echo "✓ Event sent - check Kibana in 2 minutes"
```

Then open: http://localhost:5601/app/security/alerts and wait 1-2 minutes for the alert to appear!
