#!/bin/bash

# ===================================================================
# THREAT INTELLIGENCE ENRICHMENT TEST SCRIPT
# ===================================================================
# Generates security events that will match threat intel indicators
# Tests real-time enrichment pipeline
# ===================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

LOGSTASH_HOST="${LOGSTASH_HOST:-localhost}"
LOGSTASH_PORT="${LOGSTASH_PORT:-5000}"

# Check if nc is available
if ! command -v nc &> /dev/null; then
  echo "Error: netcat (nc) is not installed"
  exit 1
fi

# Event counter
EVENT_COUNT=0

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}  THREAT INTELLIGENCE ENRICHMENT TEST${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""
echo -e "Target: ${CYAN}$LOGSTASH_HOST:$LOGSTASH_PORT${NC}"
echo ""

# ===================================================================
# Helper Function: Send Event to Logstash
# ===================================================================

send_event() {
  local event_json="$1"
  echo "$event_json" | nc -w1 "$LOGSTASH_HOST" "$LOGSTASH_PORT" > /dev/null 2>&1
  ((EVENT_COUNT++))
}

# ===================================================================
# TEST 1: Malicious IP Detection (APT29 - SolarWinds)
# ===================================================================

echo -e "${YELLOW}[Test 1/5]${NC} APT29 SolarWinds C2 Communication"

# Outbound connection to known APT29 C2 server
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "network",
  "event_type": "connection",
  "source": {
    "ip": "192.168.1.100",
    "port": 54321,
    "hostname": "WKS-FINANCE01.corp.local"
  },
  "destination": {
    "ip": "13.59.205.66",
    "port": 443,
    "domain": "avsvmcloud.com"
  },
  "network": {
    "protocol": "tcp",
    "bytes_sent": 45678,
    "bytes_received": 123456
  },
  "user": {
    "name": "john.smith"
  },
  "message": "Outbound HTTPS connection to 13.59.205.66:443"
}'

echo -e "  ${GREEN}✓${NC} Simulated connection to APT29 C2 (13.59.205.66)"

# Multiple suspicious connections
for i in {1..5}; do
  send_event '{
    "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
    "log_category": "network",
    "event_type": "connection",
    "source": {
      "ip": "192.168.1.100",
      "hostname": "WKS-FINANCE01.corp.local"
    },
    "destination": {
      "ip": "13.59.205.66",
      "port": 443
    },
    "network": {
      "protocol": "tcp"
    },
    "message": "Repeated connection to suspicious IP"
  }'
  sleep 0.2
done

echo -e "  ${GREEN}✓${NC} Simulated 5 repeated connections (beaconing pattern)"
echo ""

# ===================================================================
# TEST 2: Malicious Domain Access (APT28 - DNC Hack)
# ===================================================================

echo -e "${YELLOW}[Test 2/5]${NC} APT28 Fancy Bear C2 Domain Access"

# DNS query for known APT28 domain
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "dns",
  "event_type": "query",
  "source": {
    "ip": "192.168.2.50",
    "hostname": "SRV-WEB01.corp.local"
  },
  "dns": {
    "question": {
      "name": "freescanonline.com",
      "type": "A"
    },
    "response": {
      "ip": ["176.31.112.10"]
    }
  },
  "user": {
    "name": "web_service"
  },
  "message": "DNS query for freescanonline.com"
}'

echo -e "  ${GREEN}✓${NC} Simulated DNS query for APT28 domain (freescanonline.com)"

# HTTP connection to malicious domain
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "web",
  "event_type": "http_request",
  "source": {
    "ip": "192.168.2.50",
    "hostname": "SRV-WEB01.corp.local"
  },
  "url": {
    "domain": "freescanonline.com",
    "path": "/api/update",
    "full": "http://freescanonline.com/api/update"
  },
  "http": {
    "request": {
      "method": "POST",
      "bytes": 2048
    },
    "response": {
      "status_code": 200,
      "bytes": 512
    }
  },
  "message": "HTTP POST to freescanonline.com/api/update"
}'

echo -e "  ${GREEN}✓${NC} Simulated HTTP POST to malicious domain"
echo ""

# ===================================================================
# TEST 3: Phishing Domain Access
# ===================================================================

echo -e "${YELLOW}[Test 3/5]${NC} Phishing Domain Detection"

# User accessing phishing site
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "web",
  "event_type": "http_request",
  "source": {
    "ip": "192.168.1.45",
    "hostname": "WKS-HR02.corp.local"
  },
  "url": {
    "domain": "secure-paypal-login.com",
    "path": "/signin",
    "full": "https://secure-paypal-login.com/signin"
  },
  "http": {
    "request": {
      "method": "GET",
      "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }
  },
  "user": {
    "name": "sarah.jones"
  },
  "message": "User accessed phishing site: secure-paypal-login.com"
}'

echo -e "  ${GREEN}✓${NC} Simulated access to PayPal phishing domain"

# Credential submission to phishing site
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "web",
  "event_type": "http_request",
  "source": {
    "ip": "192.168.1.45",
    "hostname": "WKS-HR02.corp.local"
  },
  "url": {
    "domain": "secure-paypal-login.com",
    "path": "/login",
    "full": "https://secure-paypal-login.com/login"
  },
  "http": {
    "request": {
      "method": "POST",
      "bytes": 256
    },
    "response": {
      "status_code": 302
    }
  },
  "user": {
    "name": "sarah.jones"
  },
  "message": "Credentials submitted to phishing site"
}'

echo -e "  ${GREEN}✓${NC} Simulated credential submission to phishing site"
echo ""

# ===================================================================
# TEST 4: Malware Hash Detection (WannaCry)
# ===================================================================

echo -e "${YELLOW}[Test 4/5]${NC} WannaCry Ransomware Hash Detection"

# File download with known WannaCry hash
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "file",
  "event_type": "file_creation",
  "source": {
    "ip": "192.168.3.10",
    "hostname": "WKS-SALES05.corp.local"
  },
  "file": {
    "name": "wcry.exe",
    "path": "C:\\Users\\mike.wilson\\Downloads\\wcry.exe",
    "size": 3723264,
    "hash": {
      "md5": "84c82835a5d21bbcf75a61706d8ab549",
      "sha256": "ed01ebfbc9eb5bbea545af4d01bf5f1071661840480439c6e5babe8e080e41aa"
    }
  },
  "user": {
    "name": "mike.wilson"
  },
  "message": "Suspicious file downloaded: wcry.exe"
}'

echo -e "  ${GREEN}✓${NC} Simulated WannaCry executable download (known hash match)"

# File execution
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "process",
  "event_type": "process_start",
  "event_id": "4688",
  "source": {
    "ip": "192.168.3.10",
    "hostname": "WKS-SALES05.corp.local"
  },
  "process": {
    "name": "wcry.exe",
    "executable": "C:\\Users\\mike.wilson\\Downloads\\wcry.exe",
    "pid": 5432,
    "command_line": "wcry.exe"
  },
  "file": {
    "hash": {
      "md5": "84c82835a5d21bbcf75a61706d8ab549"
    }
  },
  "user": {
    "name": "mike.wilson"
  },
  "message": "Process started: wcry.exe"
}'

echo -e "  ${GREEN}✓${NC} Simulated WannaCry execution"
echo ""

# ===================================================================
# TEST 5: Mimikatz Hash Detection
# ===================================================================

echo -e "${YELLOW}[Test 5/5]${NC} Mimikatz Credential Theft Tool Detection"

# Mimikatz execution with known hash
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "process",
  "event_type": "process_start",
  "event_id": "4688",
  "source": {
    "ip": "192.168.1.200",
    "hostname": "WKS-ADMIN01.corp.local"
  },
  "process": {
    "name": "mimikatz.exe",
    "executable": "C:\\Temp\\mimikatz.exe",
    "pid": 7890,
    "command_line": "mimikatz.exe privilege::debug sekurlsa::logonpasswords"
  },
  "file": {
    "hash": {
      "md5": "7c4fe364c1f3e3738a75a2b736b0c958"
    }
  },
  "user": {
    "name": "admin_user"
  },
  "message": "Credential theft tool executed: mimikatz.exe"
}'

echo -e "  ${GREEN}✓${NC} Simulated Mimikatz execution (known hash match)"

# LSASS memory dump (Mimikatz activity)
send_event '{
  "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
  "log_category": "process",
  "event_type": "process_access",
  "event_id": "10",
  "source": {
    "ip": "192.168.1.200",
    "hostname": "WKS-ADMIN01.corp.local"
  },
  "process": {
    "name": "mimikatz.exe",
    "pid": 7890
  },
  "target": {
    "process": {
      "name": "lsass.exe",
      "pid": 624
    }
  },
  "file": {
    "hash": {
      "md5": "7c4fe364c1f3e3738a75a2b736b0c958"
    }
  },
  "user": {
    "name": "admin_user"
  },
  "message": "mimikatz.exe accessed lsass.exe memory"
}'

echo -e "  ${GREEN}✓${NC} Simulated LSASS memory access by Mimikatz"
echo ""

# ===================================================================
# TEST 6: Port Scan from Known Malicious IP
# ===================================================================

echo -e "${YELLOW}[Test 6/6]${NC} Inbound Attack from Known Malicious IP"

# Port scan from known scanner IP
for port in 22 80 443 3389 445 1433; do
  send_event '{
    "@timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
    "log_category": "firewall",
    "event_type": "connection_blocked",
    "source": {
      "ip": "203.0.113.66",
      "port": '$((RANDOM + 10000))'
    },
    "destination": {
      "ip": "203.0.113.1",
      "port": '$port'
    },
    "network": {
      "protocol": "tcp"
    },
    "action": "deny",
    "message": "Inbound connection from 203.0.113.66 to port '$port' blocked"
  }'
  sleep 0.1
done

echo -e "  ${GREEN}✓${NC} Simulated port scan from known malicious IP (203.0.113.66)"
echo ""

# ===================================================================
# Summary
# ===================================================================

sleep 1

echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}  TEST COMPLETE${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo -e "Total events sent: ${CYAN}$EVENT_COUNT${NC}"
echo ""
echo -e "Expected Threat Intel Matches:"
echo -e "  ${YELLOW}•${NC} APT29 C2 IP: 13.59.205.66 (confidence: 98%)"
echo -e "  ${YELLOW}•${NC} APT28 C2 Domain: freescanonline.com (confidence: 96%)"
echo -e "  ${YELLOW}•${NC} Phishing Domain: secure-paypal-login.com (confidence: 88%)"
echo -e "  ${YELLOW}•${NC} WannaCry Hash: 84c82835a5d21bbcf75a61706d8ab549"
echo -e "  ${YELLOW}•${NC} Mimikatz Hash: 7c4fe364c1f3e3738a75a2b736b0c958"
echo -e "  ${YELLOW}•${NC} Port Scanner IP: 203.0.113.66 (confidence: 80%)"
echo ""
echo -e "Verification Commands:"
echo -e "  ${BLUE}# Check threat intel matches index${NC}"
echo -e "  curl -u elastic:elastic123 'http://localhost:9200/threat-intel-matches-*/_search?size=50&pretty'"
echo ""
echo -e "  ${BLUE}# Check security threats index${NC}"
echo -e "  curl -u elastic:elastic123 'http://localhost:9200/security-threats-*/_search?size=50&pretty'"
echo ""
echo -e "  ${BLUE}# Search for specific threat${NC}"
echo -e "  curl -u elastic:elastic123 'http://localhost:9200/threat-intel-matches-*/_search?q=threat.apt_group:APT29&pretty'"
echo ""
echo -e "Wait 5-10 seconds for Logstash processing, then check Kibana:"
echo -e "  ${CYAN}http://localhost:5601/app/discover${NC}"
echo -e "  Filter by index: ${YELLOW}threat-intel-matches-*${NC}"
echo ""
