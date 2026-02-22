#!/bin/bash
set -e

CLUSTER_NAME=${CLUSTER_NAME:-ife-poc}

echo "=========================================="
echo "Creating k3d Cluster: $CLUSTER_NAME"
echo "=========================================="

# Check if cluster already exists
if k3d cluster list | grep -q "^$CLUSTER_NAME"; then
    echo "Cluster '$CLUSTER_NAME' already exists."
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        k3d cluster delete $CLUSTER_NAME
    else
        echo "Using existing cluster."
        exit 0
    fi
fi

echo "Creating new k3d cluster..."

# Create cluster with host network access
# This allows pods to reach host.k3d.internal for controller access
k3d cluster create $CLUSTER_NAME \
    --agents 1 \
    --port "8080:80@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --wait

echo ""
echo "Cluster created successfully!"
echo ""

# Verify cluster is running
echo "Verifying cluster status..."
kubectl cluster-info
echo ""

# Show nodes
echo "Cluster nodes:"
kubectl get nodes
echo ""

echo "=========================================="
echo "✓ Cluster '$CLUSTER_NAME' is ready!"
echo "=========================================="
