#!/bin/bash

# APT Simulation: Persistence Mechanisms
# MITRE ATT&CK: T1078 - Valid Accounts, T1136 - Create Account

API_BASE="${API_BASE:-http://localhost:8000}"
ACCOUNT_COUNT="${ACCOUNT_COUNT:-20}"

echo "🔒 APT Simulation: Persistence Mechanisms"
echo "========================================="
echo "Simulating various persistence techniques"
echo ""

# APT group naming patterns for stealth accounts
declare -a apt_prefixes=(
    "apt"
    "backup"
    "service"
    "admin"
    "update"
    "system"
    "security"
    "temp"
    "test"
    "support"
)

declare -a apt_suffixes=(
    "svc"
    "adm"
    "usr"
    "acc"
    "tmp"
    "sys"
    "mgr"
    "bot"
    "app"
    "dev"
)

# Stealth domains for email addresses
declare -a stealth_domains=(
    "corp-internal.com"
    "backup-services.org"
    "security-updates.net"
    "system-admin.info"
    "maintenance.local"
    "enterprise.internal"
)

# Common weak passwords used for persistence accounts
declare -a weak_passwords=(
    "Password123"
    "CompanyName2023"
    "Welcome123"
    "Admin2023"
    "Backup123"
    "Service2023"
    "Temp123"
    "Change123"
    "Default123"
    "System123"
)

echo "🚀 Starting persistence simulation..."
start_time=$(date)

echo "👤 Creating stealth user accounts..."

# Rapid account creation phase
for i in $(seq 1 $ACCOUNT_COUNT); do
    prefix="${apt_prefixes[$((RANDOM % ${#apt_prefixes[@]}))]}"
    suffix="${apt_suffixes[$((RANDOM % ${#apt_suffixes[@]}))]}"
    domain="${stealth_domains[$((RANDOM % ${#stealth_domains[@]}))]}"
    password="${weak_passwords[$((RANDOM % ${#weak_passwords[@]}))]}"

    username="${prefix}${suffix}${i}"
    email="${username}@${domain}"

    echo "  [$i/$ACCOUNT_COUNT] Creating stealth account: $username"
    echo "    Email: $email"
    echo "    Domain: $domain"

    # Attempt to create account
    response=$(curl -s -X POST "$API_BASE/api/v1/users/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$email\",
            \"username\": \"$username\",
            \"password\": \"$password\"
        }")

    if echo "$response" | grep -q "\"id\""; then
        echo "    ✅ Account created successfully"
    elif echo "$response" | grep -q "already"; then
        echo "    ⚠️  Account already exists (expected behavior)"
    else
        echo "    ❌ Failed to create account"
    fi

    # Small delay to avoid rate limiting but simulate rapid creation
    sleep 0.3
done

echo ""
echo "🔐 Simulating registry persistence mechanisms..."

# Registry persistence simulation
registry_persistence=(
    "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'SecurityUpdate' -Value 'C:\\Windows\\Temp\\update.exe'"
    "New-ItemProperty -Path 'HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'UserUpdate' -Value 'C:\\Users\\Public\\Documents\\client.exe'"
    "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon' -Name 'Shell' -Value 'explorer.exe,C:\\Windows\\System32\\backdoor.exe'"
    "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\RunOnce' -Name 'Install' -Value 'powershell.exe -WindowStyle Hidden -File C:\\temp\\install.ps1'"
)

for i in "${!registry_persistence[@]}"; do
    command="${registry_persistence[$i]}"

    echo "  [$(($i + 1))/${#registry_persistence[@]}] Registry persistence"
    echo "    Command: ${command:0:50}..."

    # Log as PowerShell execution
    curl -s -X POST "$API_BASE/api/v1/security/simulate/powershell" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"$command\",
            \"user\": \"persistence_agent\",
            \"host\": \"workstation01.corp.local\",
            \"process_id\": $((3000 + RANDOM % 1000)),
            \"source_ip\": \"192.168.1.100\"
        }" > /dev/null

    echo "    ✅ Registry modification logged"
    sleep 2
done

echo ""
echo "🕒 Simulating scheduled task persistence..."

# Scheduled task persistence
scheduled_tasks=(
    "schtasks /create /tn 'SystemUpdate' /tr 'C:\\Windows\\Temp\\update.exe' /sc daily /st 03:00 /ru SYSTEM"
    "schtasks /create /tn 'BackupTask' /tr 'powershell.exe -WindowStyle Hidden -File C:\\temp\\backup.ps1' /sc hourly"
    "Register-ScheduledTask -TaskName 'SecurityScan' -Action (New-ScheduledTaskAction -Execute 'C:\\Windows\\System32\\scan.exe')"
    "New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -File C:\\temp\\monitor.ps1'"
)

for i in "${!scheduled_tasks[@]}"; do
    command="${scheduled_tasks[$i]}"

    echo "  [$(($i + 1))/${#scheduled_tasks[@]}] Scheduled task creation"
    echo "    Task: ${command:0:40}..."

    # Log as PowerShell execution
    curl -s -X POST "$API_BASE/api/v1/security/simulate/powershell" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"$command\",
            \"user\": \"task_scheduler\",
            \"host\": \"server01.corp.local\",
            \"process_id\": $((4000 + RANDOM % 1000)),
            \"source_ip\": \"10.0.1.50\"
        }" > /dev/null

    echo "    ✅ Scheduled task logged"
    sleep 2
done

echo ""
echo "🌐 Simulating WMI persistence..."

# WMI persistence techniques
wmi_persistence=(
    "Register-WmiEvent -Query 'SELECT * FROM Win32_VolumeChangeEvent WHERE EventType = 2' -Action {Start-Process 'C:\\temp\\usb.exe'}"
    "Set-WmiInstance -Class __EventFilter -NameSpace 'root\\subscription' -Arguments @{Name='USBFilter'; EventNameSpace='root\\cimv2'; QueryLanguage='WQL'; Query='SELECT * FROM Win32_VolumeChangeEvent'}"
    "New-CimInstance -ClassName __EventFilter -Namespace root\\subscription -Property @{Name='SystemMonitor'; EventNamespace='root\\cimv2'; QueryLanguage='WQL'}"
)

for i in "${!wmi_persistence[@]}"; do
    command="${wmi_persistence[$i]}"

    echo "  [$(($i + 1))/${#wmi_persistence[@]}] WMI persistence"
    echo "    WMI: ${command:0:40}..."

    # Log as PowerShell execution
    curl -s -X POST "$API_BASE/api/v1/security/simulate/powershell" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"$command\",
            \"user\": \"wmi_agent\",
            \"host\": \"mgmt01.corp.local\",
            \"process_id\": $((5000 + RANDOM % 1000)),
            \"source_ip\": \"172.16.1.25\"
        }" > /dev/null

    echo "    ✅ WMI event logged"
    sleep 2
done

end_time=$(date)

echo ""
echo "✅ Persistence simulation completed!"
echo "📊 Attack Summary:"
echo "   Stealth Accounts Created: $ACCOUNT_COUNT"
echo "   Registry Persistence: ${#registry_persistence[@]} entries"
echo "   Scheduled Tasks: ${#scheduled_tasks[@]} tasks"
echo "   WMI Persistence: ${#wmi_persistence[@]} events"
echo "   Unique Domains Used: ${#stealth_domains[@]}"
echo "   Start Time: $start_time"
echo "   End Time: $end_time"
echo ""
echo "🔍 Check detection results:"
echo "   # Account creation analysis"
echo "   curl '$API_BASE/api/v1/users/me' -H 'Authorization: Bearer <token>'"
echo ""
echo "   # PowerShell persistence analysis"
echo "   curl '$API_BASE/api/v1/security/threats/powershell'"
echo ""
echo "📊 View in Kibana:"
echo "   # Account creation events"
echo "   http://localhost:5601/app/discover#/?_g=(filters:!(),query:(language:kuery,query:'message:*register*'))"
echo ""
echo "   # Persistence PowerShell commands"
echo "   http://localhost:5601/app/discover#/?_g=(filters:!(),query:(language:kuery,query:'process.command_line:*Run* OR process.command_line:*schtasks* OR process.command_line:*WMI*'))"
echo ""
echo "💡 Expected Detections:"
echo "   • Rapid account creation burst"
echo "   • Suspicious registry modifications"
echo "   • Unusual scheduled task creation"
echo "   • WMI event subscription abuse"
echo "   • Non-corporate email domains"