from fastapi import APIRouter, BackgroundTasks
from typing import List, Dict
from app.services.threat_detection import threat_detector
from app.services.alerting import alerting_service
from app.services.security_logger import security_logger
from pydantic import BaseModel
import structlog

logger = structlog.get_logger()
router = APIRouter()

class PowerShellSimulation(BaseModel):
    command: str
    user: str
    host: str
    process_id: int
    source_ip: str = "127.0.0.1"

class PrivilegeEscalationSimulation(BaseModel):
    command: str
    user: str
    host: str
    process: str
    event_action: str = "privilege_use"
    source_ip: str = "127.0.0.1"

@router.get("/threats/scan")
async def run_threat_scan(background_tasks: BackgroundTasks):
    """Run comprehensive threat detection scan"""
    
    #  detection methods
    brute_force_threats = await threat_detector.detect_brute_force_attacks()
    data_exfil_threats = await threat_detector.detect_data_exfiltration()
    powershell_threats = await threat_detector.detect_powershell_attacks()
    apt_threats = await threat_detector.correlate_apt_indicators()
    
    all_threats = brute_force_threats + data_exfil_threats + powershell_threats + apt_threats
    
    # Send alerts for high-risk threats
    for threat in all_threats:
        if threat.get('risk_score', 0) >= 7:
            background_tasks.add_task(alerting_service.send_slack_alert, threat)
            background_tasks.add_task(alerting_service.create_elasticsearch_alert, threat)
    
    return {
        "total_threats": len(all_threats),
        "high_risk_threats": len([t for t in all_threats if t.get('risk_score', 0) >= 7]),
        "threats": all_threats
    }

@router.get("/threats/brute-force")
async def detect_brute_force():
    """Detect brute force attacks"""
    threats = await threat_detector.detect_brute_force_attacks()
    return {"threats": threats, "count": len(threats)}

@router.get("/threats/data-exfiltration")
async def detect_data_exfiltration():
    """Detect data exfiltration attempts"""
    threats = await threat_detector.detect_data_exfiltration()
    return {"threats": threats, "count": len(threats)}

@router.get("/threats/powershell")
async def detect_powershell_attacks():
    """Detect suspicious PowerShell activity"""
    threats = await threat_detector.detect_powershell_attacks()
    return {"threats": threats, "count": len(threats)}

@router.get("/threats/apt-correlation")
async def detect_apt_correlation():
    """Detect correlated APT indicators"""
    threats = await threat_detector.correlate_apt_indicators()
    return {"threats": threats, "count": len(threats)}

@router.get("/hunt/powershell-external")
async def hunt_powershell_external():
    """Hunt for PowerShell execution from external IPs"""
    threats = await threat_detector.hunt_ecs_powershell_external()
    return {"threats": threats, "count": len(threats)}

@router.get("/hunt/apt-kill-chain")
async def hunt_apt_kill_chain():
    """Hunt for complete APT kill chain"""
    threats = await threat_detector.hunt_apt_kill_chain_ecs()
    return {"threats": threats, "count": len(threats)}

@router.get("/hunt/lateral-movement")
async def hunt_lateral_movement():
    """Hunt for lateral movement patterns"""
    threats = await threat_detector.hunt_lateral_movement_ecs()
    return {"threats": threats, "count": len(threats)}

@router.get("/hunt/privilege-escalation")
async def hunt_privilege_escalation():
    """Hunt for privilege escalation attempts"""
    threats = await threat_detector.hunt_privilege_escalation_ecs()
    return {"threats": threats, "count": len(threats)}

@router.get("/hunt/comprehensive")
async def comprehensive_threat_hunt():
    """Run comprehensive threat hunting across all patterns"""
    results = {
        "powershell_external": await threat_detector.hunt_ecs_powershell_external(),
        "apt_kill_chain": await threat_detector.hunt_apt_kill_chain_ecs(),
        "lateral_movement": await threat_detector.hunt_lateral_movement_ecs(),
        "privilege_escalation": await threat_detector.hunt_privilege_escalation_ecs()
    }
    
    total_threats = sum(len(threats) for threats in results.values())
    
    return {
        "total_threats": total_threats,
        "hunt_results": results,
        "hunt_queries_used": [
            "event.action:process_start AND process.command_line:*powershell* AND source.ip:!10.0.0.0/8",
            "event.action:authentication_success AND logon.type:3",
            "process.command_line:*runas* OR process.command_line:*sudo*"
        ]
    }

@router.post("/simulate/powershell")
async def simulate_powershell_execution(simulation: PowerShellSimulation):
    """Simulate PowerShell execution for testing threat detection"""
    await security_logger.log_powershell_event(
        command=simulation.command,
        user=simulation.user,
        host=simulation.host,
        process_id=simulation.process_id,
        source_ip=simulation.source_ip
    )

    return {
        "status": "success",
        "message": f"PowerShell event logged for detection testing",
        "event": {
            "command": simulation.command,
            "user": simulation.user,
            "host": simulation.host,
            "process_id": simulation.process_id,
            "source_ip": simulation.source_ip
        }
    }