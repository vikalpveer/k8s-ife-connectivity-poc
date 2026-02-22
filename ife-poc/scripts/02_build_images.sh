#!/bin/bash
set -e

CLUSTER_NAME=${CLUSTER_NAME:-ife-poc}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Building Docker Images"
echo "=========================================="

cd "$PROJECT_ROOT"

# Build controller image
echo ""
echo "Building controller image..."
docker build -t controller:latest ./controller
echo "✓ Controller image built"

# Build AP simulator image
echo ""
echo "Building AP simulator image..."
docker build -t ap-simulator:latest ./ap-sim
echo "✓ AP simulator image built"

# Build network shaper image
echo ""
echo "Building network shaper image..."
docker build -t network-shaper:latest ./network-shaper
echo "✓ Network shaper image built"

# Import images into k3d cluster
echo ""
echo "Importing images into k3d cluster..."
k3d image import controller:latest -c $CLUSTER_NAME
k3d image import ap-simulator:latest -c $CLUSTER_NAME
k3d image import network-shaper:latest -c $CLUSTER_NAME
echo "✓ Images imported into cluster"

echo ""
echo "=========================================="
echo "✓ All images built and imported!"
echo "=========================================="

# Show images
echo ""
echo "Docker images:"
docker images | grep -E "controller|ap-simulator|network-shaper|REPOSITORY"
