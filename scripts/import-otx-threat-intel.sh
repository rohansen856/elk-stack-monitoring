#!/bin/bash

# Import real threat intelligence from AlienVault OTX into Elasticsearch

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OTX_API_KEY="${ALIENVAULT_OTX_API_KEY:-}"
ES_URL="http://localhost:9200"
ES_USER="elastic"
ES_PASS="elastic123"

# Check if API key is set
if [ -z "$OTX_API_KEY" ]; then
    echo "Error: ALIENVAULT_OTX_API_KEY environment variable is not set"
    echo "Please set it with: export ALIENVAULT_OTX_API_KEY='your_api_key_here'"
    exit 1
fi
CURRENT_DATE=$(date -u +"%Y.%m.%d")

echo -e "${BLUE}Fetching real threat intelligence from AlienVault OTX...${NC}"

# Fetch recent threat pulses
curl -s "https://otx.alienvault.com/api/v1/pulses/activity?limit=20" \
  -H "X-OTX-API-KEY: $OTX_API_KEY" > /tmp/otx_data.json

# Extract and import indicators using Python
python3 << 'PYTHON_SCRIPT'
import json
import subprocess
from datetime import datetime

with open('/tmp/otx_data.json', 'r') as f:
    data = json.load(f)

ES_URL = "http://localhost:9200"
ES_USER = "elastic"
ES_PASS = "elastic123"
CURRENT_DATE = datetime.utcnow().strftime("%Y.%m.%d")
timestamp = datetime.utcnow().isoformat() + "Z"

ip_count = 0
domain_count = 0
hash_count = 0

for pulse in data.get('results', [])[:20]:
    pulse_name = pulse.get('name', 'Unknown')
    pulse_tags = ','.join(pulse.get('tags', [])[:3])

    for indicator in pulse.get('indicators', []):
        ind_type = indicator.get('type')
        ind_value = indicator.get('indicator')

        # Import IPs
        if ind_type == 'IPv4' and ip_count < 50:
            doc = {
                "@timestamp": timestamp,
                "threat": {
                    "indicator": {
                        "ip": ind_value,
                        "type": "malicious",
                        "confidence": 90,
                        "provider": "AlienVault OTX",
                        "description": pulse_name,
                        "tags": pulse_tags,
                        "first_seen": timestamp,
                        "last_seen": timestamp
                    }
                }
            }
            subprocess.run([
                'curl', '-s', '-X', 'POST',
                f'{ES_URL}/threat-intel-ips-{CURRENT_DATE}/_doc',
                '-u', f'{ES_USER}:{ES_PASS}',
                '-H', 'Content-Type: application/json',
                '-d', json.dumps(doc)
            ], capture_output=True)
            ip_count += 1

        # Import domains
        elif ind_type in ['domain', 'hostname'] and domain_count < 50:
            category = "malware"
            if "phishing" in pulse_tags.lower():
                category = "phishing"
            elif "c2" in pulse_tags.lower() or "c&c" in pulse_tags.lower():
                category = "c2"

            doc = {
                "@timestamp": timestamp,
                "threat": {
                    "indicator": {
                        "domain": ind_value,
                        "type": "malicious",
                        "confidence": 90,
                        "category": category,
                        "provider": "AlienVault OTX",
                        "description": pulse_name,
                        "tags": pulse_tags
                    }
                }
            }
            subprocess.run([
                'curl', '-s', '-X', 'POST',
                f'{ES_URL}/threat-intel-domains-{CURRENT_DATE}/_doc',
                '-u', f'{ES_USER}:{ES_PASS}',
                '-H', 'Content-Type: application/json',
                '-d', json.dumps(doc)
            ], capture_output=True)
            domain_count += 1

        # Import file hashes
        elif ind_type in ['FileHash-MD5', 'MD5', 'FileHash-SHA256', 'SHA256'] and hash_count < 50:
            hash_type = 'md5' if 'MD5' in ind_type else 'sha256'
            is_ransomware = 'ransomware' in pulse_name.lower()

            doc = {
                "@timestamp": timestamp,
                "threat": {
                    "indicator": {
                        "hash": {
                            hash_type: ind_value
                        },
                        "malware_family": pulse_name[:50],
                        "type": "malicious_file",
                        "ransomware": is_ransomware,
                        "provider": "AlienVault OTX"
                    }
                },
                "file": {
                    "name": pulse_name[:100]
                }
            }
            subprocess.run([
                'curl', '-s', '-X', 'POST',
                f'{ES_URL}/threat-intel-hashes-{CURRENT_DATE}/_doc',
                '-u', f'{ES_USER}:{ES_PASS}',
                '-H', 'Content-Type: application/json',
                '-d', json.dumps(doc)
            ], capture_output=True)
            hash_count += 1

print(f"✓ Imported {ip_count} malicious IPs")
print(f"✓ Imported {domain_count} malicious domains")
print(f"✓ Imported {hash_count} malicious file hashes")
print(f"Total: {ip_count + domain_count + hash_count} threat indicators")
PYTHON_SCRIPT

echo ""
echo -e "${GREEN}Verifying imported data...${NC}"
sleep 2

TOTAL_IPS=$(curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-ips-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
TOTAL_DOMAINS=$(curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-domains-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
TOTAL_HASHES=$(curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-hashes-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')

echo -e "${BLUE}Database Status:${NC}"
echo -e "  IPs: $TOTAL_IPS"
echo -e "  Domains: $TOTAL_DOMAINS"
echo -e "  Hashes: $TOTAL_HASHES"
echo -e "  ${GREEN}Total: $((TOTAL_IPS + TOTAL_DOMAINS + TOTAL_HASHES)) indicators${NC}"
echo ""
echo -e "${YELLOW}AlienVault OTX import complete!${NC}"
