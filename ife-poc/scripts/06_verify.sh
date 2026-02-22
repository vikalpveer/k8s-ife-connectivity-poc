#!/bin/bash
set -e

CONTROLLER_US_EAST=${CONTROLLER_US_EAST:-http://localhost:8081}
CONTROLLER_US_WEST=${CONTROLLER_US_WEST:-http://localhost:8082}

echo "=========================================="
echo "Verification Script"
echo "=========================================="
echo ""

# Function to check controller health
check_controller() {
    local name=$1
    local url=$2
    
    echo "Checking $name controller..."
    if curl -s -f "$url/health" > /dev/null 2>&1; then
        response=$(curl -s "$url/health")
        echo "✓ $name is healthy"
        echo "  Response: $response"
    else
        echo "✗ $name is not responding"
        return 1
    fi
    echo ""
}

# Function to get controller status
get_controller_status() {
    local name=$1
    local url=$2
    
    echo "Getting $name controller status..."
    response=$(curl -s "$url/admin/status" 2>/dev/null || echo '{"error": "failed to connect"}')
    
    if command -v jq &> /dev/null; then
        echo "$response" | jq '.'
    else
        echo "$response"
    fi
    echo ""
}

# Check controllers
echo "=== Controller Health Checks ==="
echo ""
check_controller "US-EAST" "$CONTROLLER_US_EAST" || true
check_controller "US-WEST" "$CONTROLLER_US_WEST" || true

# Get controller status
echo "=== Controller Status ==="
echo ""
get_controller_status "US-EAST" "$CONTROLLER_US_EAST"
get_controller_status "US-WEST" "$CONTROLLER_US_WEST"

# Check Kubernetes resources
echo "=== Kubernetes Resources ==="
echo ""

echo "Namespaces:"
kubectl get namespaces | grep aircraft || echo "No aircraft namespaces found"
echo ""

echo "All AP Pods:"
kubectl get pods --all-namespaces | grep aircraft || echo "No aircraft pods found"
echo ""

# Check specific aircraft
AIRCRAFT_ID="a320-ind-023"
if kubectl get namespace "aircraft-${AIRCRAFT_ID}" &> /dev/null; then
    echo "Pods in aircraft-${AIRCRAFT_ID}:"
    kubectl get pods -n "aircraft-${AIRCRAFT_ID}" -o wide
    echo ""
    
    echo "Sample AP logs (wifi):"
    POD_NAME=$(kubectl get pods -n "aircraft-${AIRCRAFT_ID}" -l ap-type=wifi -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$POD_NAME" ]; then
        echo "Pod: $POD_NAME"
        kubectl logs -n "aircraft-${AIRCRAFT_ID}" "$POD_NAME" -c ap-simulator --tail=10 || true
    else
        echo "No wifi pod found"
    fi
fi

echo ""
echo "=========================================="
echo "✓ Verification complete!"
echo "=========================================="
echo ""
echo "Useful commands:"
echo "  # View all aircraft pods"
echo "  kubectl get pods --all-namespaces | grep aircraft"
echo ""
echo "  # View logs from specific AP"
echo "  kubectl logs -n aircraft-<AIRCRAFT_ID> <POD_NAME> -c ap-simulator -f"
echo ""
echo "  # Check controller status"
echo "  curl $CONTROLLER_US_EAST/admin/status | jq"
echo ""
echo "  # Publish config"
echo "  ./scripts/04_publish_config.sh test-a"
