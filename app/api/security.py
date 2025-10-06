from fastapi import APIRouter, BackgroundTasks
from typing import List, Dict
from app.services.threat_detection import threat_detector
from app.services.alerting import alerting_service
import structlog

logger = structlog.get_logger()
router = APIRouter()

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