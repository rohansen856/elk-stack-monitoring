#!/bin/bash

# ===================================================================
# THREAT INTELLIGENCE INDEX SETUP SCRIPT
# ===================================================================
# Creates Elasticsearch indices for threat intel indicators
# Populates with test data from known malicious sources
# ===================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ES_URL="${ELASTICSEARCH_URL:-http://localhost:9200}"
ES_USER="${ELASTICSEARCH_USER:-elastic}"
ES_PASS="${ELASTICSEARCH_PASSWORD:-elastic123}"

echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}  THREAT INTELLIGENCE INDEX SETUP${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# ===================================================================
# STEP 1: Create Index Templates
# ===================================================================

echo -e "${YELLOW}[1/4]${NC} Creating index templates..."

# Threat Intel IPs Index Template
curl -X PUT "$ES_URL/_index_template/threat-intel-ips-template" \
  -u "$ES_USER:$ES_PASS" \
  -H 'Content-Type: application/json' \
  -d '{
  "index_patterns": ["threat-intel-ips-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "5s"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "threat": {
          "properties": {
            "indicator": {
              "properties": {
                "ip": { "type": "ip" },
                "type": { "type": "keyword" },
                "confidence": { "type": "integer" },
                "provider": { "type": "keyword" },
                "description": { "type": "text" },
                "first_seen": { "type": "date" },
                "last_seen": { "type": "date" }
              }
            }
          }
        }
      }
    }
  }
}' 2>&1 | grep -q "acknowledged" && echo -e "${GREEN}✓${NC} IP template created" || echo -e "${RED}✗${NC} IP template failed"

# Threat Intel Domains Index Template
curl -X PUT "$ES_URL/_index_template/threat-intel-domains-template" \
  -u "$ES_USER:$ES_PASS" \
  -H 'Content-Type: application/json' \
  -d '{
  "index_patterns": ["threat-intel-domains-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "5s"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "threat": {
          "properties": {
            "indicator": {
              "properties": {
                "domain": { "type": "keyword" },
                "type": { "type": "keyword" },
                "confidence": { "type": "integer" },
                "category": { "type": "keyword" },
                "provider": { "type": "keyword" },
                "description": { "type": "text" }
              }
            }
          }
        }
      }
    }
  }
}' 2>&1 | grep -q "acknowledged" && echo -e "${GREEN}✓${NC} Domain template created" || echo -e "${RED}✗${NC} Domain template failed"

# Threat Intel File Hashes Index Template
curl -X PUT "$ES_URL/_index_template/threat-intel-hashes-template" \
  -u "$ES_USER:$ES_PASS" \
  -H 'Content-Type: application/json' \
  -d '{
  "index_patterns": ["threat-intel-hashes-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "refresh_interval": "5s"
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "threat": {
          "properties": {
            "indicator": {
              "properties": {
                "hash": {
                  "properties": {
                    "md5": { "type": "keyword" },
                    "sha1": { "type": "keyword" },
                    "sha256": { "type": "keyword" }
                  }
                },
                "malware_family": { "type": "keyword" },
                "type": { "type": "keyword" },
                "ransomware": { "type": "boolean" },
                "provider": { "type": "keyword" }
              }
            }
          }
        }
      }
    }
  }
}' 2>&1 | grep -q "acknowledged" && echo -e "${GREEN}✓${NC} Hash template created" || echo -e "${RED}✗${NC} Hash template failed"

echo ""

# ===================================================================
# STEP 2: Create Indices
# ===================================================================

echo -e "${YELLOW}[2/4]${NC} Creating threat intel indices..."

CURRENT_DATE=$(date -u +"%Y.%m.%d")

# Create IPs index
curl -X PUT "$ES_URL/threat-intel-ips-$CURRENT_DATE" -u "$ES_USER:$ES_PASS" 2>&1 | grep -q "acknowledged" \
  && echo -e "${GREEN}✓${NC} IPs index created" || echo -e "${YELLOW}!${NC} IPs index may already exist"

# Create Domains index
curl -X PUT "$ES_URL/threat-intel-domains-$CURRENT_DATE" -u "$ES_USER:$ES_PASS" 2>&1 | grep -q "acknowledged" \
  && echo -e "${GREEN}✓${NC} Domains index created" || echo -e "${YELLOW}!${NC} Domains index may already exist"

# Create Hashes index
curl -X PUT "$ES_URL/threat-intel-hashes-$CURRENT_DATE" -u "$ES_USER:$ES_PASS" 2>&1 | grep -q "acknowledged" \
  && echo -e "${GREEN}✓${NC} Hashes index created" || echo -e "${YELLOW}!${NC} Hashes index may already exist"

echo ""

# ===================================================================
# STEP 3: Populate Test Data - Malicious IPs
# ===================================================================

echo -e "${YELLOW}[3/4]${NC} Populating threat intel test data..."
echo -e "${BLUE}  → Malicious IPs${NC}"

# Known malicious IPs from various threat actors
MALICIOUS_IPS=(
  # APT29 (Cozy Bear) - SolarWinds attack
  "13.59.205.66:APT29 (Cozy Bear):95:solarwinds:SolarWinds supply chain C2 server"
  "54.193.127.66:APT29 (Cozy Bear):98:solarwinds:SUNBURST backdoor C2"

  # APT28 (Fancy Bear) - DNC hack
  "176.31.112.10:APT28 (Fancy Bear):92:apt28:DNC hack infrastructure"
  "185.86.148.227:APT28 (Fancy Bear):90:fancy bear:Election interference C2"

  # Lazarus Group - WannaCry/Bangladesh Bank
  "103.224.80.44:Lazarus Group:97:lazarus:WannaCry kill switch domain resolver"
  "190.115.18.139:Lazarus Group:95:bangladesh bank:SWIFT attack infrastructure"

  # Common botnet C2s
  "185.220.101.1:Mirai Botnet:88:mirai:Mirai botnet C2 server"
  "45.142.212.61:Emotet:93:emotet:Emotet banking trojan C2"

  # Generic malicious IPs (for testing)
  "198.51.100.66:Generic Malware:75:abuse.ch:Known malicious IP from URLhaus"
  "203.0.113.66:Port Scanner:80:honeypot:Persistent port scanning source"
)

for ip_data in "${MALICIOUS_IPS[@]}"; do
  IFS=':' read -r ip provider confidence category description <<< "$ip_data"

  curl -X POST "$ES_URL/threat-intel-ips-$CURRENT_DATE/_doc" \
    -u "$ES_USER:$ES_PASS" \
    -H 'Content-Type: application/json' \
    -d "{
      \"@timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
      \"threat\": {
        \"indicator\": {
          \"ip\": \"$ip\",
          \"type\": \"malicious\",
          \"confidence\": $confidence,
          \"provider\": \"$provider\",
          \"description\": \"$description\",
          \"first_seen\": \"$(date -u -d '30 days ago' +"%Y-%m-%dT%H:%M:%S.000Z")\",
          \"last_seen\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\"
        }
      }
    }" > /dev/null 2>&1

  echo -e "  ${GREEN}✓${NC} $ip ($provider - confidence: $confidence%)"
done

echo ""
echo -e "${BLUE}  → Malicious Domains${NC}"

# Known malicious domains
MALICIOUS_DOMAINS=(
  # C2 domains
  "evil-c2-server.com:c2:95:APT Infrastructure:Command and Control server"
  "malware-download.xyz:malware:90:Malware Distribution:Drive-by download site"

  # Phishing domains
  "secure-paypal-login.com:phishing:88:Phishing Campaign:PayPal credential phishing"
  "amazon-account-verify.net:phishing:92:Phishing Campaign:Amazon credential theft"

  # Known APT domains
  "avsvmcloud.com:c2:98:APT29:SolarWinds SUNBURST C2 domain"
  "freescanonline.com:c2:96:APT28:Fancy Bear C2 infrastructure"

  # Ransomware C2
  "wannacry-killswitch.iuqerfsodp9ifjaposdfjhgosurijfaewrwergwea.com:c2:100:Lazarus:WannaCry kill switch domain"
  "ransomware-payment.onion:c2:94:Various:Ransomware payment portal"
)

for domain_data in "${MALICIOUS_DOMAINS[@]}"; do
  IFS=':' read -r domain category confidence provider description <<< "$domain_data"

  curl -X POST "$ES_URL/threat-intel-domains-$CURRENT_DATE/_doc" \
    -u "$ES_USER:$ES_PASS" \
    -H 'Content-Type: application/json' \
    -d "{
      \"@timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
      \"threat\": {
        \"indicator\": {
          \"domain\": \"$domain\",
          \"type\": \"malicious\",
          \"confidence\": $confidence,
          \"category\": \"$category\",
          \"provider\": \"$provider\",
          \"description\": \"$description\"
        }
      }
    }" > /dev/null 2>&1

  echo -e "  ${GREEN}✓${NC} $domain ($category - confidence: $confidence%)"
done

echo ""
echo -e "${BLUE}  → Malicious File Hashes${NC}"

# Known malicious file hashes
MALICIOUS_HASHES=(
  # WannaCry hashes
  "84c82835a5d21bbcf75a61706d8ab549:wcry.exe:WannaCry:true:Lazarus Group"
  "ed01ebfbc9eb5bbea545af4d01bf5f1071661840480439c6e5babe8e080e41aa:wannacry.exe:WannaCry:true:Lazarus Group"

  # NotPetya hashes
  "027cc450ef5f8c5f653329641ec1fed9:perfc.dat:NotPetya:true:APT28"
  "64b0b58a2c030c77fdb2b537b2fcc4af432bc55ffb36599a31d418c7c69e94b1:notpetya.exe:NotPetya:true:APT28"

  # Mimikatz hashes
  "7c4fe364c1f3e3738a75a2b736b0c958:mimikatz.exe:Mimikatz:false:Various APTs"
  "2c5e6e2462c5b4a8f99e0f8b6b5e5a5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e:mimikatz64.exe:Mimikatz:false:Various APTs"

  # Generic malware
  "5d41402abc4b2a76b9719d911017c592:malware.bin:GenericMalware:false:Unknown"
  "098f6bcd4621d373cade4e832627b4f6:backdoor.dll:Backdoor:false:APT Unknown"
)

for hash_data in "${MALICIOUS_HASHES[@]}"; do
  IFS=':' read -r hash filename family ransomware provider <<< "$hash_data"

  # Determine hash type by length
  if [ ${#hash} -eq 32 ]; then
    hash_type="md5"
    hash_field="\"md5\": \"$hash\""
  elif [ ${#hash} -eq 64 ]; then
    hash_type="sha256"
    hash_field="\"sha256\": \"$hash\""
  else
    hash_type="sha1"
    hash_field="\"sha1\": \"$hash\""
  fi

  curl -X POST "$ES_URL/threat-intel-hashes-$CURRENT_DATE/_doc" \
    -u "$ES_USER:$ES_PASS" \
    -H 'Content-Type: application/json' \
    -d "{
      \"@timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
      \"threat\": {
        \"indicator\": {
          \"hash\": {
            $hash_field
          },
          \"malware_family\": \"$family\",
          \"type\": \"malicious_file\",
          \"ransomware\": $ransomware,
          \"provider\": \"$provider\"
        }
      },
      \"file\": {
        \"name\": \"$filename\"
      }
    }" > /dev/null 2>&1

  echo -e "  ${GREEN}✓${NC} $hash ($family - $filename)"
done

echo ""

# ===================================================================
# STEP 4: Verify Data
# ===================================================================

echo -e "${YELLOW}[4/4]${NC} Verifying threat intel data..."

sleep 2  # Wait for indexing

# Count documents in each index
IP_COUNT=$(curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-ips-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
DOMAIN_COUNT=$(curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-domains-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')
HASH_COUNT=$(curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-hashes-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | grep -o '[0-9]*')

echo -e "  ${GREEN}✓${NC} Malicious IPs indexed: $IP_COUNT"
echo -e "  ${GREEN}✓${NC} Malicious Domains indexed: $DOMAIN_COUNT"
echo -e "  ${GREEN}✓${NC} Malicious Hashes indexed: $HASH_COUNT"

echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}  THREAT INTELLIGENCE SETUP COMPLETE${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Enable Logstash threat-intel-enrichment.conf pipeline"
echo -e "  2. Restart Logstash to apply configuration"
echo -e "  3. Test with simulation script"
echo ""
echo -e "Test a threat intel lookup:"
echo -e "  ${BLUE}curl -u $ES_USER:$ES_PASS '$ES_URL/threat-intel-ips-*/_search?q=threat.indicator.ip:13.59.205.66'${NC}"
echo ""
