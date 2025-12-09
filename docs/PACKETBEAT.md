# Quick Start: Browser Traffic Monitoring

## 1-Minute Setup

```bash
# Start browser traffic monitoring
./scripts/setup-browser-monitoring.sh
```

That's it! Now when you browse to malicious IPs, alerts will be generated.

---

## What Just Happened?

✅ **Packetbeat** is now running in Docker
✅ **Monitoring** all network traffic on this machine
✅ **Sending** events to Logstash for OTX threat enrichment
✅ **Detection rules** will trigger alerts for malicious IPs

---

## Test It (Safe Method)

```bash
# Send a test "browser" event
printf '{"@timestamp":"%s","source":{"ip":"192.168.1.100","port":54321},"destination":{"ip":"194.11.246.101","port":80},"message":"Simulated browser request","event_type":"http_request"}\n' "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')" | nc -w1 localhost 5000

# Wait 2 minutes for alert
sleep 120

# Open Kibana alerts
xdg-open http://localhost:5601/app/security/alerts 2>/dev/null || open http://localhost:5601/app/security/alerts 2>/dev/null || echo "Open: http://localhost:5601/app/security/alerts"
```

---

## Verify It's Working

```bash
# Check Packetbeat is running
docker ps | grep packetbeat

# View captured traffic
curl -s -u elastic:elastic123 \
  "http://localhost:9200/packetbeat-*/_search?size=5&sort=@timestamp:desc&pretty" \
  | grep -A10 "destination"

# Check for OTX alerts
curl -s -u elastic:elastic123 \
  "http://localhost:9200/.internal.alerts-*/_search?q=194.11.246.101&size=1&pretty" \
  | grep "kibana.alert.rule.name"
```

---

## ⚠️ CRITICAL SECURITY WARNING

**DO NOT ACTUALLY BROWSE TO 194.11.246.101!**

This IP is malicious and could:
- Install malware on your system
- Steal credentials
- Exploit browser vulnerabilities
- Compromise your machine

**Use the test scripts instead** - they simulate browser traffic safely!

---

## What Triggers Alerts?

| Traffic Type | Alert? | Why? |
|--------------|--------|------|
| `google.com` | ❌ No | Not in OTX threat feed |
| `facebook.com` | ❌ No | Legitimate domain |
| `194.11.246.101` | ✅ **YES** | OTX Malicious IP (Snakes by riverbank) |
| `avsvmcloud.com` | ✅ **YES** | APT29 C2 domain |
| `secure-paypal-login.com` | ✅ **YES** | Phishing domain |

---

## Stop/Start Commands

```bash
# Stop monitoring
docker stop packetbeat

# Start monitoring
docker restart packetbeat

# View logs
docker logs -f packetbeat

# Remove completely
docker stop packetbeat && docker rm packetbeat
```

---

## Troubleshooting

### Packetbeat Not Starting?

```bash
# Check logs
docker logs packetbeat

# Restart
docker restart packetbeat

# Check permissions
ls -l packetbeat/packetbeat.yml
```

### No Events Captured?

```bash
# Generate test traffic
curl http://example.com

# Wait 10 seconds
sleep 10

# Check if captured
curl -s -u elastic:elastic123 "http://localhost:9200/packetbeat-*/_count"
```

### No Alerts Appearing?

1. **Check events are enriched**:
   ```bash
   curl -s -u elastic:elastic123 \
     "http://localhost:9200/security-*/_search?q=194.11.246.101&size=1&pretty" \
     | grep "threat.intel"
   ```

2. **Check rules are enabled**:
   - Open: http://localhost:5601/app/management/insightsAndAlerting/rules
   - Find "OTX" rules
   - Ensure "Enabled" column shows green toggle

3. **Wait 2-3 minutes** after event generation (rules run every 1 minute)

---

## Documentation

- **Full Setup Guide**: [docs/MONITOR_WORKSTATION_TRAFFIC.md](docs/MONITOR_WORKSTATION_TRAFFIC.md)
- **OTX Detection Rules**: [docs/OTX_SECURITY_RULES_SETUP.md](docs/OTX_SECURITY_RULES_SETUP.md)
- **Main README**: [OTX_DETECTION_README.md](OTX_DETECTION_README.md)

---

## Summary

✅ **Setup Command**: `./scripts/setup-browser-monitoring.sh`
✅ **Test Command**: `./scripts/test-detection-rules.sh`
✅ **View Alerts**: http://localhost:5601/app/security/alerts
✅ **Status**: `docker ps | grep packetbeat`

**Your browser traffic is now monitored for OTX threats!** 🎉

(But please use test scripts instead of actually browsing to malicious IPs!)
