# IFE PoC Architecture

## System Overview

This document describes the architecture and design decisions for the In-Flight Entertainment (IFE) Proof of Concept system.

## Components

### 1. Controller Service

**Location**: Runs on host machine as Docker containers (outside Kubernetes)

**Technology Stack**:
- Python 3.11
- FastAPI (web framework)
- SQLite (data persistence)
- Uvicorn (ASGI server)

**Responsibilities**:
- AP registration and lifecycle management
- Configuration storage and distribution
- Heartbeat monitoring
- Version tracking and acknowledgment

**Data Model**:

```sql
-- APs table
CREATE TABLE aps (
    ap_id TEXT PRIMARY KEY,
    aircraft_id TEXT NOT NULL,
    airline TEXT NOT NULL,
    ap_type TEXT NOT NULL,
    preferred_region TEXT NOT NULL,
    registered_at TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    last_applied_version TEXT,
    status TEXT DEFAULT 'healthy'
);

-- Configs table
CREATE TABLE configs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version TEXT NOT NULL,
    airline TEXT,
    aircraft_id TEXT,
    ap_type TEXT,
    region TEXT,
    payload TEXT NOT NULL,
    created_at TEXT NOT NULL
);
```

**API Endpoints**:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/health` | Health check |
| POST | `/register` | Register new AP |
| POST | `/heartbeat` | AP heartbeat |
| GET | `/config` | Get configuration |
| POST | `/ack` | Acknowledge config application |
| POST | `/admin/publish` | Publish new config |
| GET | `/admin/status` | Get all APs status |

### 2. AP Simulator

**Location**: Runs as pods in Kubernetes namespaces

**Technology Stack**:
- Python 3.11
- requests library
- Structured JSON logging

**State Machine**:

```
initializing → registering → running ⇄ applying_config
                    ↓
                 (retry with backoff)
```

**Behavior**:
1. **Initialization**: Load environment configuration
2. **Registration**: Register with preferred controller region
3. **Heartbeat Loop**: Send periodic heartbeats (default: 10s)
4. **Config Polling**: Poll for config updates (default: 15s)
5. **Config Application**: Apply configs atomically and send ACK
6. **Failover**: Switch regions on failure with exponential backoff

**Failover Logic**:
```python
initial_backoff = 1.0s
max_backoff = 60.0s
backoff = initial_backoff

on_failure:
    apply_backoff_with_jitter()
    if backoff >= max_backoff / 2:
        switch_to_alternate_region()
    backoff = min(backoff * 2, max_backoff)

on_success:
    backoff = initial_backoff
```

### 3. Network Shaper Sidecar

**Location**: Runs as sidecar container in each AP pod

**Technology Stack**:
- Alpine Linux
- iproute2 (tc command)
- Bash

**Network Profiles**:

| Profile | Latency | Jitter | Loss | Bandwidth |
|---------|---------|--------|------|-----------|
| ku_high_latency | 600ms | ±100ms | 2% | 2 Mbps |
| ku_low_latency | 200ms | ±30ms | 0.5% | 10 Mbps |
| ka_band | 100ms | ±20ms | 0.1% | 50 Mbps |

**Implementation**:
```bash
# Example: ku_low_latency profile
tc qdisc add dev eth0 root handle 1: netem delay 200ms 30ms loss 0.5%
tc qdisc add dev eth0 parent 1:1 handle 10: tbf rate 10mbit burst 32kbit latency 400ms
```

## Kubernetes Architecture

### Namespace Design

Each aircraft gets its own namespace:
```
aircraft-<AIRCRAFT_ID>
```

**Benefits**:
- Logical isolation per aircraft
- Easy resource management
- Clear organizational structure
- Simplified RBAC (if needed)

### Pod Design

Each AP type (telecom, wifi, ife) runs as a separate pod with two containers:

```yaml
Pod: ap-<AP_TYPE>
├── Container: ap-simulator (main)
│   └── Runs agent.py
└── Container: network-shaper (sidecar)
    └── Applies tc netem rules
```

**Container Communication**:
- Share network namespace (shareProcessNamespace: true)
- Network shaper affects all traffic from the pod
- No inter-container communication needed

### Resource Allocation

```yaml
ap-simulator:
  requests: {memory: 64Mi, cpu: 50m}
  limits: {memory: 128Mi, cpu: 200m}

network-shaper:
  requests: {memory: 32Mi, cpu: 10m}
  limits: {memory: 64Mi, cpu: 50m}
```

## Configuration Management

### Targeting System

Configurations use a specificity-based matching system:

**Selectors**:
- `airline`: Target specific airline (e.g., "Delta")
- `aircraft_id`: Target specific aircraft (e.g., "a320-ind-023")
- `ap_type`: Target specific AP type (e.g., "wifi")
- `region`: Target specific region (e.g., "us-east")

**Specificity Scoring**:
```
score = (airline_match ? 8 : 0) +
        (aircraft_id_match ? 4 : 0) +
        (ap_type_match ? 2 : 0) +
        (region_match ? 1 : 0)
```

**Example Scenarios**:

1. **Global Config**: All selectors null → applies to all APs
2. **Airline Config**: airline="Delta", others null → all Delta APs
3. **Specific AP**: airline="Delta", aircraft_id="a320-ind-023", ap_type="wifi" → one specific AP

### Version Management

- Versions are strings (e.g., "v1", "v2", "v3")
- APs track `current_version` and report it in heartbeats
- Controller returns `has_update: true` if newer version available
- APs apply configs atomically and send ACK

## Multi-Region Architecture

### Controller Deployment

Two independent controller instances:
```
us-east:8081 ← → APs ← → us-west:8082
```

**Database Strategy**: Separate SQLite per region
- Pros: Simple, independent, no sync complexity
- Cons: No automatic data replication
- Trade-off: Acceptable for PoC, would use distributed DB in production

### Failover Mechanism

**Detection**: HTTP request timeout/failure
**Action**: Switch to alternate region
**Backoff**: Exponential with jitter to prevent thundering herd
**Recovery**: APs continue with new region (no automatic switch back)

**Sequence Diagram**:
```
AP                  us-east             us-west
│                      │                   │
├─ heartbeat ────────→ X (down)            │
│                      │                   │
├─ (backoff 1s)        │                   │
├─ heartbeat ────────→ X                   │
│                      │                   │
├─ (backoff 2s)        │                   │
├─ switch region       │                   │
├─ heartbeat ──────────────────────────→   │
│                      │                   ├─ OK
├─ continue ←──────────────────────────────┤
```

## Network Communication

### Pod to Host Communication

**Challenge**: Pods need to reach controllers on host machine

**Solution**: k3d's `host.k3d.internal` DNS entry
```
CONTROLLER_US_EAST=http://host.k3d.internal:8081
CONTROLLER_US_WEST=http://host.k3d.internal:8082
```

**Alternative Approaches**:
1. ~~NodePort service~~ - Adds unnecessary complexity
2. ~~Host network mode~~ - Reduces isolation
3. ✓ **host.k3d.internal** - Clean, simple, k3d-native

### Network Shaping Implementation

**Requirement**: Apply tc rules without knowing pod's node

**Solution**: Sidecar with NET_ADMIN capability
```yaml
securityContext:
  capabilities:
    add: [NET_ADMIN]
```

**Why Sidecar vs DaemonSet**:
- ✓ Sidecar: Per-pod configuration, portable, no node awareness needed
- ✗ DaemonSet: Would need to identify which pods to affect, node-specific

## Deployment Flow

```
1. Prerequisites Check (00_prereqs.sh)
   └─ Verify: docker, k3d, kubectl

2. Cluster Creation (01_cluster.sh)
   └─ k3d cluster create with host access

3. Image Building (02_build_images.sh)
   ├─ Build: controller, ap-simulator, network-shaper
   └─ Import into k3d cluster

4. Controller Start (start_controllers.sh)
   ├─ Start us-east:8081
   └─ Start us-west:8082

5. Aircraft Deployment (03_deploy_aircraft.sh)
   ├─ Create namespaces
   └─ Deploy AP pods (3 per aircraft)

6. Verification (06_verify.sh)
   ├─ Check controller health
   ├─ Check pod status
   └─ View sample logs
```

## Testing Strategy

### Acceptance Test A: Targeted Config Push
**Goal**: Verify selective configuration distribution
**Method**: Publish config with specific selectors, verify only matching APs apply it
**Validation**: Check `last_applied_version` in controller status

### Acceptance Test B: Region Failover
**Goal**: Verify automatic failover on controller failure
**Method**: Stop us-east controller, monitor AP behavior
**Validation**: APs switch to us-west with proper backoff

### Acceptance Test C: Recovery
**Goal**: Verify system stability after controller recovery
**Method**: Restart us-east controller, monitor reconciliation
**Validation**: System continues operating normally

## Security Considerations

**Current State** (PoC):
- No authentication/authorization
- No TLS/encryption
- No secrets management
- Privileged containers (NET_ADMIN)

**Production Requirements**:
- [ ] mTLS between APs and controllers
- [ ] API authentication (JWT/OAuth)
- [ ] Config encryption at rest
- [ ] Network policies
- [ ] Pod security policies
- [ ] Secrets management (Vault/Sealed Secrets)

## Scalability Considerations

**Current Limits**:
- Single-node k3d cluster
- SQLite (single-writer)
- No horizontal scaling

**Production Scaling**:
- Multi-node Kubernetes cluster
- Distributed database (PostgreSQL/CockroachDB)
- Controller horizontal scaling with load balancer
- Caching layer (Redis)
- Message queue for async operations

## Monitoring and Observability

**Current Implementation**:
- Structured JSON logging to stdout
- Controller `/admin/status` endpoint
- kubectl logs for debugging

**Production Requirements**:
- [ ] Prometheus metrics
- [ ] Grafana dashboards
- [ ] Distributed tracing (Jaeger)
- [ ] Log aggregation (ELK/Loki)
- [ ] Alerting (AlertManager)

## Future Enhancements

1. **Config Rollback**: Ability to rollback to previous versions
2. **Canary Deployments**: Gradual config rollout
3. **Config Validation**: JSON schema validation
4. **Webhooks**: Notify external systems on config changes
5. **Web UI**: Management interface for controllers
6. **Metrics Export**: Prometheus endpoints
7. **Health Checks**: Liveness/readiness probes
8. **Graceful Shutdown**: Proper cleanup on termination
