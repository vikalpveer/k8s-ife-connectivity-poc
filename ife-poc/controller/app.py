#!/usr/bin/env python3
"""
IFE PoC Controller - External controller for managing aircraft AP configurations
"""
import os
import json
import sqlite3
import logging
from datetime import datetime
from typing import Optional, Dict, Any, List
from contextlib import contextmanager

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Environment configuration
REGION = os.getenv("REGION", "us-east")
PORT = int(os.getenv("PORT", "8081"))
DB_PATH = os.getenv("DB_PATH", f"/data/controller-{REGION}.db")

app = FastAPI(title=f"IFE Controller - {REGION}", version="1.0.0")


# Pydantic models
class RegisterRequest(BaseModel):
    ap_id: str
    aircraft_id: str
    airline: str
    ap_type: str
    preferred_region: str


class HeartbeatRequest(BaseModel):
    ap_id: str
    aircraft_id: str
    current_version: Optional[str] = None
    status: str = "healthy"


class AckRequest(BaseModel):
    ap_id: str
    aircraft_id: str
    version: str
    success: bool
    message: Optional[str] = None


class PublishConfigRequest(BaseModel):
    version: str
    airline: Optional[str] = None
    aircraft_id: Optional[str] = None
    ap_type: Optional[str] = None
    region: Optional[str] = None
    payload: Dict[str, Any]


class ConfigResponse(BaseModel):
    version: str
    payload: Dict[str, Any]
    has_update: bool


# Database management
@contextmanager
def get_db():
    """Context manager for database connections"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()


def init_db():
    """Initialize database schema"""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    
    with get_db() as conn:
        cursor = conn.cursor()
        
        # APs table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS aps (
                ap_id TEXT PRIMARY KEY,
                aircraft_id TEXT NOT NULL,
                airline TEXT NOT NULL,
                ap_type TEXT NOT NULL,
                preferred_region TEXT NOT NULL,
                registered_at TEXT NOT NULL,
                last_seen TEXT NOT NULL,
                last_applied_version TEXT,
                status TEXT DEFAULT 'healthy'
            )
        """)
        
        # Configs table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS configs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                version TEXT NOT NULL,
                airline TEXT,
                aircraft_id TEXT,
                ap_type TEXT,
                region TEXT,
                payload TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
        """)
        
        # Create indexes
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_configs_version ON configs(version)")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_aps_aircraft ON aps(aircraft_id)")
        
        logger.info(f"Database initialized at {DB_PATH}")


# API endpoints
@app.on_event("startup")
async def startup_event():
    """Initialize database on startup"""
    init_db()
    logger.info(f"Controller started in region: {REGION} on port {PORT}")


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "region": REGION,
        "timestamp": datetime.utcnow().isoformat()
    }


@app.post("/register")
async def register(req: RegisterRequest):
    """Register a new AP"""
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                INSERT OR REPLACE INTO aps 
                (ap_id, aircraft_id, airline, ap_type, preferred_region, registered_at, last_seen)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (req.ap_id, req.aircraft_id, req.airline, req.ap_type, 
                  req.preferred_region, now, now))
            
            logger.info(f"Registered AP: {req.ap_id} from aircraft {req.aircraft_id}")
            
            return {
                "status": "registered",
                "ap_id": req.ap_id,
                "region": REGION,
                "timestamp": now
            }
    except Exception as e:
        logger.error(f"Registration error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/heartbeat")
async def heartbeat(req: HeartbeatRequest):
    """Process heartbeat from AP"""
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                UPDATE aps 
                SET last_seen = ?, status = ?, last_applied_version = COALESCE(?, last_applied_version)
                WHERE ap_id = ?
            """, (now, req.status, req.current_version, req.ap_id))
            
            if cursor.rowcount == 0:
                raise HTTPException(status_code=404, detail="AP not registered")
            
            return {
                "status": "ok",
                "region": REGION,
                "timestamp": now
            }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Heartbeat error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/config")
async def get_config(
    ap_id: str = Query(...),
    current_version: Optional[str] = Query(None)
):
    """Get configuration for an AP"""
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            
            # Get AP details
            cursor.execute("""
                SELECT aircraft_id, airline, ap_type, preferred_region
                FROM aps WHERE ap_id = ?
            """, (ap_id,))
            
            ap = cursor.fetchone()
            if not ap:
                raise HTTPException(status_code=404, detail="AP not registered")
            
            # Find matching config (most specific match wins)
            cursor.execute("""
                SELECT version, payload, 
                       (CASE WHEN airline = ? THEN 8 ELSE 0 END +
                        CASE WHEN aircraft_id = ? THEN 4 ELSE 0 END +
                        CASE WHEN ap_type = ? THEN 2 ELSE 0 END +
                        CASE WHEN region = ? THEN 1 ELSE 0 END) as specificity
                FROM configs
                WHERE (airline IS NULL OR airline = ?)
                  AND (aircraft_id IS NULL OR aircraft_id = ?)
                  AND (ap_type IS NULL OR ap_type = ?)
                  AND (region IS NULL OR region = ?)
                ORDER BY specificity DESC, created_at DESC
                LIMIT 1
            """, (ap['airline'], ap['aircraft_id'], ap['ap_type'], ap['preferred_region'],
                  ap['airline'], ap['aircraft_id'], ap['ap_type'], ap['preferred_region']))
            
            config = cursor.fetchone()
            
            if not config:
                # Return default config
                return {
                    "version": "v1",
                    "payload": {"default": True, "message": "Default configuration"},
                    "has_update": current_version != "v1"
                }
            
            has_update = config['version'] != current_version
            
            return {
                "version": config['version'],
                "payload": json.loads(config['payload']),
                "has_update": has_update
            }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Config retrieval error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/ack")
async def acknowledge(req: AckRequest):
    """Acknowledge config application"""
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            
            if req.success:
                cursor.execute("""
                    UPDATE aps 
                    SET last_applied_version = ?
                    WHERE ap_id = ?
                """, (req.version, req.ap_id))
                
                logger.info(f"AP {req.ap_id} successfully applied version {req.version}")
            else:
                logger.warning(f"AP {req.ap_id} failed to apply version {req.version}: {req.message}")
            
            return {
                "status": "acknowledged",
                "timestamp": datetime.utcnow().isoformat()
            }
    except Exception as e:
        logger.error(f"Acknowledgment error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/admin/publish")
async def publish_config(req: PublishConfigRequest):
    """Publish a new configuration"""
    try:
        # Validate payload has required fields
        if not req.payload:
            raise HTTPException(status_code=400, detail="Payload cannot be empty")
        
        with get_db() as conn:
            cursor = conn.cursor()
            now = datetime.utcnow().isoformat()
            
            cursor.execute("""
                INSERT INTO configs (version, airline, aircraft_id, ap_type, region, payload, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (req.version, req.airline, req.aircraft_id, req.ap_type, 
                  req.region, json.dumps(req.payload), now))
            
            logger.info(f"Published config version {req.version} with selectors: "
                       f"airline={req.airline}, aircraft={req.aircraft_id}, "
                       f"ap_type={req.ap_type}, region={req.region}")
            
            return {
                "status": "published",
                "version": req.version,
                "timestamp": now
            }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Publish error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/admin/status")
async def get_status():
    """Get status of all registered APs"""
    try:
        with get_db() as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT ap_id, aircraft_id, airline, ap_type, preferred_region,
                       last_seen, last_applied_version, status
                FROM aps
                ORDER BY aircraft_id, ap_type
            """)
            
            aps = []
            for row in cursor.fetchall():
                aps.append({
                    "ap_id": row['ap_id'],
                    "aircraft_id": row['aircraft_id'],
                    "airline": row['airline'],
                    "ap_type": row['ap_type'],
                    "preferred_region": row['preferred_region'],
                    "last_seen": row['last_seen'],
                    "last_applied_version": row['last_applied_version'],
                    "status": row['status']
                })
            
            return {
                "region": REGION,
                "total_aps": len(aps),
                "aps": aps,
                "timestamp": datetime.utcnow().isoformat()
            }
    except Exception as e:
        logger.error(f"Status retrieval error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=PORT)
