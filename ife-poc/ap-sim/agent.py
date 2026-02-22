#!/usr/bin/env python3
"""
IFE PoC AP Simulator - Simulates aircraft access point behavior
"""
import os
import sys
import json
import time
import random
import logging
from datetime import datetime
from typing import Optional, Dict, Any

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Configure structured JSON logging
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "ap_id": getattr(record, 'ap_id', None),
            "aircraft_id": getattr(record, 'aircraft_id', None),
            "ap_type": getattr(record, 'ap_type', None),
            "controller_region": getattr(record, 'controller_region', None),
            "state": getattr(record, 'state', None),
            "config_version": getattr(record, 'config_version', None),
        }
        return json.dumps({k: v for k, v in log_data.items() if v is not None})

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger = logging.getLogger(__name__)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# Environment configuration
AP_ID = os.getenv("AP_ID")
AIRCRAFT_ID = os.getenv("AIRCRAFT_ID")
AIRLINE = os.getenv("AIRLINE")
AP_TYPE = os.getenv("AP_TYPE")
PREFERRED_REGION = os.getenv("PREFERRED_REGION", "us-east")

# Controller endpoints
CONTROLLERS = {
    "us-east": os.getenv("CONTROLLER_US_EAST", "http://host.k3d.internal:8081"),
    "us-west": os.getenv("CONTROLLER_US_WEST", "http://host.k3d.internal:8082")
}

# Timing configuration
HEARTBEAT_INTERVAL = int(os.getenv("HEARTBEAT_INTERVAL", "10"))  # seconds
CONFIG_POLL_INTERVAL = int(os.getenv("CONFIG_POLL_INTERVAL", "15"))  # seconds
INITIAL_BACKOFF = float(os.getenv("INITIAL_BACKOFF", "1.0"))  # seconds
MAX_BACKOFF = float(os.getenv("MAX_BACKOFF", "60.0"))  # seconds

# Validate required environment variables
if not all([AP_ID, AIRCRAFT_ID, AIRLINE, AP_TYPE]):
    logger.error("Missing required environment variables: AP_ID, AIRCRAFT_ID, AIRLINE, AP_TYPE")
    sys.exit(1)


class APSimulator:
    """Aircraft Access Point Simulator"""
    
    def __init__(self):
        self.ap_id = AP_ID
        self.aircraft_id = AIRCRAFT_ID
        self.airline = AIRLINE
        self.ap_type = AP_TYPE
        self.preferred_region = PREFERRED_REGION
        
        self.current_region = PREFERRED_REGION
        self.current_version = None
        self.state = "initializing"
        self.backoff = INITIAL_BACKOFF
        
        # Setup HTTP session with retries
        self.session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=0.5,
            status_forcelist=[500, 502, 503, 504]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)
        
        self.log_extra = {
            'ap_id': self.ap_id,
            'aircraft_id': self.aircraft_id,
            'ap_type': self.ap_type,
            'controller_region': self.current_region,
            'state': self.state,
            'config_version': self.current_version
        }
    
    def log(self, level, message, **kwargs):
        """Log with structured context"""
        extra = self.log_extra.copy()
        extra.update(kwargs)
        extra['state'] = self.state
        extra['controller_region'] = self.current_region
        extra['config_version'] = self.current_version
        getattr(logger, level)(message, extra=extra)
    
    def get_controller_url(self, region: Optional[str] = None) -> str:
        """Get controller URL for specified region"""
        region = region or self.current_region
        return CONTROLLERS.get(region, CONTROLLERS[PREFERRED_REGION])
    
    def switch_region(self):
        """Switch to alternate controller region"""
        regions = list(CONTROLLERS.keys())
        regions.remove(self.current_region)
        if regions:
            old_region = self.current_region
            self.current_region = regions[0]
            self.log('warning', f"Switching from {old_region} to {self.current_region}")
            self.backoff = INITIAL_BACKOFF  # Reset backoff on successful switch
    
    def apply_backoff(self):
        """Apply exponential backoff with jitter"""
        jitter = random.uniform(0, 0.3 * self.backoff)
        sleep_time = self.backoff + jitter
        self.log('info', f"Applying backoff: {sleep_time:.2f}s")
        time.sleep(sleep_time)
        self.backoff = min(self.backoff * 2, MAX_BACKOFF)
    
    def register(self) -> bool:
        """Register with controller"""
        self.state = "registering"
        url = f"{self.get_controller_url()}/register"
        
        payload = {
            "ap_id": self.ap_id,
            "aircraft_id": self.aircraft_id,
            "airline": self.airline,
            "ap_type": self.ap_type,
            "preferred_region": self.preferred_region
        }
        
        try:
            self.log('info', f"Registering with controller at {url}")
            response = self.session.post(url, json=payload, timeout=5)
            response.raise_for_status()
            
            self.log('info', "Registration successful")
            self.backoff = INITIAL_BACKOFF  # Reset backoff on success
            return True
            
        except requests.exceptions.RequestException as e:
            self.log('error', f"Registration failed: {e}")
            return False
    
    def send_heartbeat(self) -> bool:
        """Send heartbeat to controller"""
        url = f"{self.get_controller_url()}/heartbeat"
        
        payload = {
            "ap_id": self.ap_id,
            "aircraft_id": self.aircraft_id,
            "current_version": self.current_version,
            "status": "healthy"
        }
        
        try:
            response = self.session.post(url, json=payload, timeout=5)
            response.raise_for_status()
            
            self.log('debug', "Heartbeat sent")
            self.backoff = INITIAL_BACKOFF  # Reset backoff on success
            return True
            
        except requests.exceptions.RequestException as e:
            self.log('error', f"Heartbeat failed: {e}")
            return False
    
    def poll_config(self) -> Optional[Dict[str, Any]]:
        """Poll for configuration updates"""
        url = f"{self.get_controller_url()}/config"
        params = {
            "ap_id": self.ap_id,
            "current_version": self.current_version
        }
        
        try:
            response = self.session.get(url, params=params, timeout=5)
            response.raise_for_status()
            
            data = response.json()
            
            if data.get("has_update"):
                self.log('info', f"New config available: {data['version']}")
                return data
            else:
                self.log('debug', "No config update available")
                return None
            
        except requests.exceptions.RequestException as e:
            self.log('error', f"Config poll failed: {e}")
            return None
    
    def apply_config(self, config: Dict[str, Any]) -> bool:
        """Apply configuration atomically"""
        self.state = "applying_config"
        version = config['version']
        payload = config['payload']
        
        try:
            self.log('info', f"Applying config version {version}")
            
            # Simulate config validation
            if not isinstance(payload, dict):
                raise ValueError("Invalid payload format")
            
            # Simulate config application (would be actual config changes in real system)
            time.sleep(random.uniform(0.5, 2.0))
            
            # Update current version
            old_version = self.current_version
            self.current_version = version
            
            self.log('info', f"Config applied successfully: {old_version} -> {version}")
            self.state = "running"
            return True
            
        except Exception as e:
            self.log('error', f"Config application failed: {e}")
            self.state = "running"
            return False
    
    def send_ack(self, version: str, success: bool, message: Optional[str] = None) -> bool:
        """Send acknowledgment to controller"""
        url = f"{self.get_controller_url()}/ack"
        
        payload = {
            "ap_id": self.ap_id,
            "aircraft_id": self.aircraft_id,
            "version": version,
            "success": success,
            "message": message
        }
        
        try:
            response = self.session.post(url, json=payload, timeout=5)
            response.raise_for_status()
            
            self.log('debug', f"ACK sent for version {version}")
            return True
            
        except requests.exceptions.RequestException as e:
            self.log('error', f"ACK failed: {e}")
            return False
    
    def run(self):
        """Main run loop"""
        self.log('info', "AP Simulator starting")
        
        # Initial registration with retry
        while not self.register():
            self.apply_backoff()
            # Try alternate region if registration fails
            if self.backoff >= MAX_BACKOFF / 2:
                self.switch_region()
        
        self.state = "running"
        self.log('info', "AP Simulator running")
        
        last_heartbeat = 0
        last_config_poll = 0
        
        while True:
            try:
                current_time = time.time()
                
                # Send heartbeat
                if current_time - last_heartbeat >= HEARTBEAT_INTERVAL:
                    if not self.send_heartbeat():
                        self.apply_backoff()
                        self.switch_region()
                        # Re-register with new region
                        if not self.register():
                            continue
                    last_heartbeat = current_time
                
                # Poll for config updates
                if current_time - last_config_poll >= CONFIG_POLL_INTERVAL:
                    config = self.poll_config()
                    if config:
                        success = self.apply_config(config)
                        self.send_ack(config['version'], success, 
                                     None if success else "Application failed")
                    last_config_poll = current_time
                
                # Sleep briefly to avoid tight loop
                time.sleep(1)
                
            except KeyboardInterrupt:
                self.log('info', "Shutting down gracefully")
                break
            except Exception as e:
                self.log('error', f"Unexpected error: {e}")
                time.sleep(5)


if __name__ == "__main__":
    simulator = APSimulator()
    simulator.run()
