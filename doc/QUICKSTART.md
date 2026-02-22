# Quick Start Guide

Get the IFE PoC up and running in 5 minutes!

## Prerequisites

Ensure you have the required tools installed:
```bash
cd ife-poc
./scripts/00_prereqs.sh
```

## Option 1: Using Makefile (Recommended)

Run the complete setup with a single command:
```bash
make all
```

This will:
1. ✓ Check prerequisites
2. ✓ Create k3d cluster
3. ✓ Build Docker images
4. ✓ Start controllers
5. ✓ Deploy aircraft

## Option 2: Step-by-Step

### 1. Create Cluster
```bash
./scripts/01_cluster.sh
```

### 2. Build Images
```bash
./scripts/02_build_images.sh
```

### 3. Start Controllers
```bash
./scripts/start_controllers.sh
```

### 4. Deploy Aircraft
```bash
./scripts/03_deploy_aircraft.sh
```

## Verify Deployment

```bash
make verify
# or
./scripts/06_verify.sh
```

## Run Acceptance Tests

### Test A: Targeted Config Push
```bash
make test-a
```

Expected: Only wifi AP in a320-ind-023 receives v2 config

### Test B: Region Failover
```bash
make test-b
```

Expected: APs failover to us-west when us-east goes down

### Test C: Recovery
```bash
make test-c
```

Expected: System continues operating after us-east recovery

## View Logs

```bash
# View specific AP logs
kubectl logs -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator -f

# View controller logs
docker logs -f controller-us-east
```

## Check Status

```bash
# Controller status
curl http://localhost:8081/admin/status | jq

# All pods
kubectl get pods --all-namespaces | grep aircraft
```

## Cleanup

```bash
make clean
```

## Troubleshooting

### Pods not starting?
```bash
kubectl describe pod -n aircraft-a320-ind-023 <POD_NAME>
```

### Controllers not accessible?
```bash
# Test from within a pod
kubectl exec -it -n aircraft-a320-ind-023 <POD_NAME> -c ap-simulator -- sh
curl http://host.k3d.internal:8081/health
```

### Need to rebuild?
```bash
make clean
make all
```

## Next Steps

- Read [`README.md`](README.md) for detailed documentation
- Read [`ARCHITECTURE.md`](ARCHITECTURE.md) for design details
- Experiment with custom configurations
- Monitor AP behavior during failover scenarios
