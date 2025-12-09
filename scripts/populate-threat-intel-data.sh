#!/bin/bash

# Populate threat intel indices with known malicious indicators

ES_URL="http://localhost:9200"
ES_USER="elastic"
ES_PASS="elastic123"
CURRENT_DATE=$(date -u +"%Y.%m.%d")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo "Populating threat intel data..."

# APT29 (SolarWinds) IPs
curl -X POST "$ES_URL/threat-intel-ips-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"ip\": \"13.59.205.66\",
      \"type\": \"malicious\",
      \"confidence\": 98,
      \"provider\": \"solarwinds\",
      \"description\": \"APT29 SUNBURST C2 server\",
      \"first_seen\": \"2020-12-01T00:00:00.000Z\",
      \"last_seen\": \"$TIMESTAMP\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added APT29 C2 IP: 13.59.205.66"

curl -X POST "$ES_URL/threat-intel-ips-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"ip\": \"54.193.127.66\",
      \"type\": \"malicious\",
      \"confidence\": 95,
      \"provider\": \"apt29\",
      \"description\": \"APT29 Cozy Bear C2 infrastructure\",
      \"first_seen\": \"2020-11-15T00:00:00.000Z\",
      \"last_seen\": \"$TIMESTAMP\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added APT29 IP: 54.193.127.66"

# APT28 (Fancy Bear) IPs
curl -X POST "$ES_URL/threat-intel-ips-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"ip\": \"176.31.112.10\",
      \"type\": \"malicious\",
      \"confidence\": 92,
      \"provider\": \"apt28\",
      \"description\": \"APT28 Fancy Bear DNC hack infrastructure\",
      \"first_seen\": \"2016-06-01T00:00:00.000Z\",
      \"last_seen\": \"$TIMESTAMP\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added APT28 IP: 176.31.112.10"

# Lazarus Group IPs
curl -X POST "$ES_URL/threat-intel-ips-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"ip\": \"103.224.80.44\",
      \"type\": \"malicious\",
      \"confidence\": 97,
      \"provider\": \"lazarus\",
      \"description\": \"Lazarus Group WannaCry infrastructure\",
      \"first_seen\": \"2017-05-12T00:00:00.000Z\",
      \"last_seen\": \"$TIMESTAMP\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added Lazarus IP: 103.224.80.44"

# Port scanner IP
curl -X POST "$ES_URL/threat-intel-ips-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"ip\": \"203.0.113.66\",
      \"type\": \"malicious\",
      \"confidence\": 80,
      \"provider\": \"honeypot\",
      \"description\": \"Known port scanner - persistent scanning activity\",
      \"first_seen\": \"2024-01-01T00:00:00.000Z\",
      \"last_seen\": \"$TIMESTAMP\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added scanner IP: 203.0.113.66"

# Malicious domains
curl -X POST "$ES_URL/threat-intel-domains-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"domain\": \"avsvmcloud.com\",
      \"type\": \"malicious\",
      \"confidence\": 98,
      \"category\": \"c2\",
      \"provider\": \"APT29\",
      \"description\": \"SolarWinds SUNBURST C2 domain\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added APT29 domain: avsvmcloud.com"

curl -X POST "$ES_URL/threat-intel-domains-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"domain\": \"freescanonline.com\",
      \"type\": \"malicious\",
      \"confidence\": 96,
      \"category\": \"c2\",
      \"provider\": \"APT28\",
      \"description\": \"APT28 Fancy Bear C2 infrastructure\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added APT28 domain: freescanonline.com"

curl -X POST "$ES_URL/threat-intel-domains-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"domain\": \"secure-paypal-login.com\",
      \"type\": \"malicious\",
      \"confidence\": 88,
      \"category\": \"phishing\",
      \"provider\": \"Phishing Campaign\",
      \"description\": \"PayPal credential phishing site\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added phishing domain: secure-paypal-login.com"

curl -X POST "$ES_URL/threat-intel-domains-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"domain\": \"malware-download.xyz\",
      \"type\": \"malicious\",
      \"confidence\": 90,
      \"category\": \"malware\",
      \"provider\": \"Malware Distribution\",
      \"description\": \"Drive-by download malware distribution site\"
    }
  }
}" > /dev/null 2>&1
echo "✓ Added malware domain: malware-download.xyz"

# Malicious hashes - WannaCry
curl -X POST "$ES_URL/threat-intel-hashes-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"hash\": {
        \"md5\": \"84c82835a5d21bbcf75a61706d8ab549\",
        \"sha256\": \"ed01ebfbc9eb5bbea545af4d01bf5f1071661840480439c6e5babe8e080e41aa\"
      },
      \"malware_family\": \"WannaCry\",
      \"type\": \"malicious_file\",
      \"ransomware\": true,
      \"provider\": \"Lazarus Group\"
    }
  },
  \"file\": {
    \"name\": \"wcry.exe\"
  }
}" > /dev/null 2>&1
echo "✓ Added WannaCry hash: 84c82835a5d21bbcf75a61706d8ab549"

# Mimikatz hash
curl -X POST "$ES_URL/threat-intel-hashes-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"hash\": {
        \"md5\": \"7c4fe364c1f3e3738a75a2b736b0c958\"
      },
      \"malware_family\": \"Mimikatz\",
      \"type\": \"malicious_file\",
      \"ransomware\": false,
      \"provider\": \"Various APTs\"
    }
  },
  \"file\": {
    \"name\": \"mimikatz.exe\"
  }
}" > /dev/null 2>&1
echo "✓ Added Mimikatz hash: 7c4fe364c1f3e3738a75a2b736b0c958"

# NotPetya hash
curl -X POST "$ES_URL/threat-intel-hashes-$CURRENT_DATE/_doc" -u "$ES_USER:$ES_PASS" -H 'Content-Type: application/json' -d "{
  \"@timestamp\": \"$TIMESTAMP\",
  \"threat\": {
    \"indicator\": {
      \"hash\": {
        \"md5\": \"027cc450ef5f8c5f653329641ec1fed9\",
        \"sha256\": \"64b0b58a2c030c77fdb2b537b2fcc4af432bc55ffb36599a31d418c7c69e94b1\"
      },
      \"malware_family\": \"NotPetya\",
      \"type\": \"malicious_file\",
      \"ransomware\": true,
      \"provider\": \"APT28\"
    }
  },
  \"file\": {
    \"name\": \"notpetya.exe\"
  }
}" > /dev/null 2>&1
echo "✓ Added NotPetya hash: 027cc450ef5f8c5f653329641ec1fed9"

echo ""
echo "Threat intel data populated successfully!"
echo ""
echo "Verification:"
curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-ips-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | cut -d: -f2 | xargs echo "  IPs:"
curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-domains-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | cut -d: -f2 | xargs echo "  Domains:"
curl -s -u "$ES_USER:$ES_PASS" "$ES_URL/threat-intel-hashes-$CURRENT_DATE/_count" | grep -o '"count":[0-9]*' | cut -d: -f2 | xargs echo "  Hashes:"
