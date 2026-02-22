# IFE PoC - In-Flight Entertainment Connectivity Simulator

A comprehensive Proof of Concept (PoC) for simulating aircraft access points (APs) in a Kubernetes environment with external controller management, configuration distribution, and multi-region failover capabilities.

## Overview

This PoC simulates:
- **Aircraft Access Points**: Multiple aircraft with 3 AP types each (telecom, wifi, ife)
- **External Controllers**: Multi-region controllers (us-east, us-west) running outside Kubernetes
- **Configuration Management**: Targeted config distribution with version control
- **Network Simulation**: Realistic satellite connectivity profiles (latency, jitter, bandwidth)
- **Failover**: Automatic region failover with exponential backoff

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (k3d)                  │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Namespace: aircraft-a320-ind-023                      │   │
│  │                                                        │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │   │
│  │  │ AP: telecom  │  │ AP: wifi     │  │ AP: ife    │ │   │
│  │  │ + net-shaper │  │ + net-shaper │  │ + net-shaper│ │   │
│  │  └──────────────┘  └──────────────┘  └────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  ... (more aircraft namespaces) ...                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ HTTP API
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Host Machine (Docker)                     │
│                                                               │
│  ┌──────────────────┐              ┌──────────────────┐     │
│  │ Controller       │              │ Controller       │     │
│  │ us-east:8081     │              │ us-west:8082     │     │
│  │ (SQLite DB)      │              │ (SQLite DB)      │     │
│  └──────────────────┘              └──────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Controller (`controller/`)
- **Technology**: Python + FastAPI
- **Purpose**: Manages AP registration, heartbeats, and configuration distribution
- **Endpoints**:
  - `POST /register` - AP registration
  - `POST /heartbeat` - Health checks
  - `GET /config` - Configuration retrieval
  - `POST /ack` - Config application acknowledgment
  - `POST /admin/publish` - Publish targeted configs
  - `GET /admin/status` - View all APs and their status

### 2. AP Simulator (`ap-sim/`)
- **Technology**: Python + requests
- **Purpose**: Simulates aircraft access point behavior
- **Features**:
  - Automatic registration with controller
  - Periodic heartbeats
  - Configuration polling and atomic application
  - Multi-region failover with exponential backoff
  - Structured JSON logging

### 3. Network Shaper (`network-shaper/`)
- **Technology**: Alpine Linux + tc netem
- **Purpose**: Simulates satellite connectivity conditions
- **Profiles**:
  - `ku_high_latency`: 600ms ±100ms, 2% loss, 2Mbps
  - `ku_low_latency`: 200ms ±30ms, 0.5% loss, 10Mbps
  - `ka_band`: 100ms ±20ms, 0.1% loss, 50Mbps

## Prerequisites

- Docker (20.10+)
- k3d (5.0+)
- kubectl (1.25+)
- curl
- jq (optional, for JSON parsing)

## Quick Start

### 1. Check Prerequisites
```bash
cd ife-poc
chmod +x scripts/*.sh
./scripts/00_prereqs.sh
```

### 2. Create Kubernetes Cluster
```bash
./scripts/01_cluster.sh
```

### 3. Build and Import Docker Images
```bash
./scripts/02_build_images.sh
```

### 4. Start Controllers
```bash
./scripts/start_controllers.sh
```

### 5. Deploy Aircraft
```bash
./scripts/03_deploy_aircraft.sh
```

### 6. Verify Deployment
```bash
./scripts/06_verify.sh
```

## Acceptance Tests

### Test A: Targeted Config Push

Deploy 5 aircraft and publish a config targeting only specific APs:

```bash
# Publish config v2 for Delta, a320-ind-023, wifi only
./scripts/04_publish_config.sh test-a

# Wait a few seconds for APs to poll and apply
sleep 20

# Verify only wifi pods in a320-ind-023 applied v2
curl -s http://localhost:8081/admin/status | jq '.aps[] | select(.aircraft_id == "a320-ind-023" and .ap_type == "wifi") | {ap_id, last_applied_version}'

# Check logs
kubectl logs -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator --tail=20
```

**Expected Result**: Only the wifi AP in aircraft a320-ind-023 should show `last_applied_version: "v2"`.

### Test B: Region Failover

Simulate controller failure and verify failover:

```bash
# Stop us-east controller
./scripts/05_region_fail.sh us-east down

# Monitor AP logs to see failover
kubectl logs -f -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator

# Check that APs are now connecting to us-west
curl -s http://localhost:8082/admin/status | jq '.total_aps'
```

**Expected Result**: APs should detect us-east failure, apply exponential backoff, and switch to us-west controller.

### Test C: Recovery

Restore the failed controller:

```bash
# Bring us-east back online
./scripts/05_region_fail.sh us-east up

# Monitor AP behavior
kubectl logs -f -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator

# Verify both controllers see APs
curl -s http://localhost:8081/admin/status | jq '.total_aps'
curl -s http://localhost:8082/admin/status | jq '.total_aps'
```

**Expected Result**: APs continue operating, may switch back to preferred region based on policy.

## Configuration Management

### Publishing Configurations

Configurations are published with selectors to target specific APs:

```bash
# Global config (all APs)
curl -X POST http://localhost:8081/admin/publish \
  -H "Content-Type: application/json" \
  -d '{
    "version": "v3",
    "airline": null,
    "aircraft_id": null,
    "ap_type": null,
    "region": null,
    "payload": {
      "policy": "global",
      "bandwidth_limit": "15mbps"
    }
  }'

# Targeted config (specific airline + aircraft + AP type)
curl -X POST http://localhost:8081/admin/publish \
  -H "Content-Type: application/json" \
  -d '{
    "version": "v4",
    "airline": "Delta",
    "aircraft_id": "a320-ind-023",
    "ap_type": "wifi",
    "region": null,
    "payload": {
      "policy": "premium",
      "bandwidth_limit": "50mbps",
      "priority": "high"
    }
  }'
```

### Config Matching Logic

The controller uses specificity scoring to match configs:
- Airline match: +8 points
- Aircraft ID match: +4 points
- AP type match: +2 points
- Region match: +1 point

The config with the highest specificity score is returned.

## Monitoring and Debugging

### View All Pods
```bash
kubectl get pods --all-namespaces | grep aircraft
```

### View AP Logs
```bash
# Specific pod
kubectl logs -n aircraft-a320-ind-023 <POD_NAME> -c ap-simulator -f

# All wifi APs
kubectl logs -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator --tail=50

# Network shaper logs
kubectl logs -n aircraft-a320-ind-023 <POD_NAME> -c network-shaper
```

### Check Controller Status
```bash
# US-EAST
curl -s http://localhost:8081/admin/status | jq

# US-WEST
curl -s http://localhost:8082/admin/status | jq

# Controller logs
docker logs -f controller-us-east
docker logs -f controller-us-west
```

### View Network Shaping
```bash
# Exec into pod
kubectl exec -it -n aircraft-a320-ind-023 <POD_NAME> -c network-shaper -- sh

# View tc rules
tc qdisc show dev eth0
```

## Project Structure

```
ife-poc/
├── controller/              # External controller service
│   ├── app.py              # FastAPI application
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Container image
├── ap-sim/                 # AP simulator agent
│   ├── agent.py            # Main agent logic
│   ├── requirements.txt    # Python dependencies
│   └── Dockerfile          # Container image
├── network-shaper/         # Network shaping sidecar
│   ├── shaper.sh           # tc netem script
│   └── Dockerfile          # Container image
├── k8s/                    # Kubernetes manifests
│   ├── namespace-template.yaml
│   └── ap-deployment-template.yaml
├── scripts/                # Automation scripts
│   ├── 00_prereqs.sh       # Check dependencies
│   ├── 01_cluster.sh       # Create k3d cluster
│   ├── 02_build_images.sh  # Build Docker images
│   ├── 03_deploy_aircraft.sh  # Deploy aircraft
│   ├── 04_publish_config.sh   # Publish configs
│   ├── 05_region_fail.sh      # Simulate failures
│   ├── 06_verify.sh           # Verify deployment
│   └── start_controllers.sh   # Start controllers
└── README.md               # This file
```

## Design Decisions

### Controller Storage
- **Choice**: Separate SQLite databases per region
- **Rationale**: Simulates independent regional controllers; simpler than shared DB
- **Trade-off**: No automatic data replication between regions

### Network Shaping
- **Implementation**: Sidecar container with NET_ADMIN capability
- **Rationale**: Works regardless of node scheduling; isolated from main container
- **Alternative**: DaemonSet approach would require node-specific configuration

### Failover Policy
- **Current**: APs switch to alternate region on failure, stay there
- **Alternative**: Could implement "preferred region" return after recovery
- **Configurable**: Via environment variables in AP simulator

### Configuration Versioning
- **Approach**: String-based versions (v1, v2, etc.)
- **Comparison**: Simple string equality check
- **Enhancement**: Could use semantic versioning for more complex scenarios

## Cleanup

```bash
# Stop controllers
docker stop controller-us-east controller-us-west
docker rm controller-us-east controller-us-west

# Delete cluster
k3d cluster delete ife-poc

# Remove data
rm -rf .data .tmp
```

## Troubleshooting

### Pods not starting
```bash
# Check pod status
kubectl describe pod -n aircraft-a320-ind-023 <POD_NAME>

# Check events
kubectl get events -n aircraft-a320-ind-023 --sort-by='.lastTimestamp'
```

### APs not connecting to controller
```bash
# Verify controller is accessible from pod
kubectl exec -it -n aircraft-a320-ind-023 <POD_NAME> -c ap-simulator -- sh
curl http://host.k3d.internal:8081/health

# Check controller logs
docker logs controller-us-east
```

### Network shaping not working
```bash
# Verify NET_ADMIN capability
kubectl get pod -n aircraft-a320-ind-023 <POD_NAME> -o yaml | grep -A5 capabilities

# Check tc rules
kubectl exec -it -n aircraft-a320-ind-023 <POD_NAME> -c network-shaper -- tc qdisc show dev eth0
```

## Future Enhancements

- [ ] Add Prometheus metrics export
- [ ] Implement config rollback mechanism
- [ ] Add authentication/authorization to controller APIs
- [ ] Support for config encryption
- [ ] Web UI for controller management
- [ ] Automated acceptance test suite
- [ ] Support for more network profiles
- [ ] Config change webhooks/notifications

## License

This is a PoC project for educational and testing purposes.

## Contributing

This is an experimental PoC. Feel free to extend and modify for your use cases.
