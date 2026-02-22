#!/bin/bash
set -e

echo "=========================================="
echo "Checking Prerequisites for IFE PoC"
echo "=========================================="

MISSING_DEPS=0

# Check for Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "✓ Docker found: $DOCKER_VERSION"
    
    # Check if Docker daemon is running
    if docker info &> /dev/null; then
        echo "✓ Docker daemon is running"
    else
        echo "✗ Docker daemon is not running"
        MISSING_DEPS=1
    fi
else
    echo "✗ Docker not found"
    echo "  Install: https://docs.docker.com/engine/install/"
    MISSING_DEPS=1
fi

# Check for k3d
if command -v k3d &> /dev/null; then
    K3D_VERSION=$(k3d version | head -n1)
    echo "✓ k3d found: $K3D_VERSION"
else
    echo "✗ k3d not found"
    echo "  Install: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
    MISSING_DEPS=1
fi

# Check for kubectl
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null || kubectl version --client)
    echo "✓ kubectl found: $KUBECTL_VERSION"
else
    echo "✗ kubectl not found"
    echo "  Install: https://kubernetes.io/docs/tasks/tools/"
    MISSING_DEPS=1
fi

# Check for jq (optional but useful)
if command -v jq &> /dev/null; then
    JQ_VERSION=$(jq --version)
    echo "✓ jq found: $JQ_VERSION"
else
    echo "⚠ jq not found (optional, but recommended for JSON parsing)"
    echo "  Install: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
fi

# Check for curl
if command -v curl &> /dev/null; then
    echo "✓ curl found"
else
    echo "✗ curl not found"
    MISSING_DEPS=1
fi

echo ""
echo "=========================================="

if [ $MISSING_DEPS -eq 0 ]; then
    echo "✓ All required dependencies are installed!"
    echo "=========================================="
    exit 0
else
    echo "✗ Some required dependencies are missing."
    echo "  Please install them and run this script again."
    echo "=========================================="
    exit 1
fi
