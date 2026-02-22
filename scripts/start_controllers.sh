#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_ROOT/.data"

echo "=========================================="
echo "Starting Controller Instances"
echo "=========================================="

# Create data directory
mkdir -p "$DATA_DIR"

# Stop existing controllers if running
echo "Stopping existing controllers..."
docker stop controller-us-east 2>/dev/null || true
docker stop controller-us-west 2>/dev/null || true
docker rm controller-us-east 2>/dev/null || true
docker rm controller-us-west 2>/dev/null || true

# Get k3d network name
K3D_NETWORK=$(docker network ls --format '{{.Name}}' | grep k3d | head -1)
if [ -z "$K3D_NETWORK" ]; then
    echo "Error: k3d network not found. Make sure the cluster is running."
    exit 1
fi
echo "Using k3d network: $K3D_NETWORK"

echo ""
echo "Starting US-EAST controller on port 8081..."
docker run -d \
    --name controller-us-east \
    --network "$K3D_NETWORK" \
    -p 8081:8081 \
    -e REGION=us-east \
    -e PORT=8081 \
    -e DB_PATH=/data/controller-us-east.db \
    -v "$DATA_DIR:/data" \
    controller:latest

echo "✓ US-EAST controller started"

echo ""
echo "Starting US-WEST controller on port 8082..."
docker run -d \
    --name controller-us-west \
    --network "$K3D_NETWORK" \
    -p 8082:8082 \
    -e REGION=us-west \
    -e PORT=8082 \
    -e DB_PATH=/data/controller-us-west.db \
    -v "$DATA_DIR:/data" \
    controller:latest

echo "✓ US-WEST controller started"

echo ""
echo "Waiting for controllers to be ready..."
sleep 3

# Check health
echo ""
echo "Checking controller health..."
echo ""

echo "US-EAST:"
curl -s http://localhost:8081/health | python3 -m json.tool || echo "Failed to connect"

echo ""
echo "US-WEST:"
curl -s http://localhost:8082/health | python3 -m json.tool || echo "Failed to connect"

echo ""
echo "=========================================="
echo "✓ Controllers started successfully!"
echo "=========================================="
echo ""
echo "Controller endpoints:"
echo "  US-EAST: http://localhost:8081"
echo "  US-WEST: http://localhost:8082"
echo ""
echo "To view logs:"
echo "  docker logs -f controller-us-east"
echo "  docker logs -f controller-us-west"
echo ""
echo "To stop controllers:"
echo "  docker stop controller-us-east controller-us-west"
