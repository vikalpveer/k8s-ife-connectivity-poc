#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
K8S_DIR="$PROJECT_ROOT/k8s"
TEMP_DIR="$PROJECT_ROOT/.tmp"

# Default aircraft configuration
NUM_AIRCRAFT=${NUM_AIRCRAFT:-5}
AIRLINE=${AIRLINE:-Delta}

echo "=========================================="
echo "Deploying Aircraft to Kubernetes"
echo "=========================================="
echo "Number of aircraft: $NUM_AIRCRAFT"
echo "Airline: $AIRLINE"
echo ""

# Create temp directory for generated manifests
mkdir -p "$TEMP_DIR"

# Aircraft configurations (lowercase for K8s namespace compliance)
AIRCRAFT_IDS=(
    "a320-ind-023"
    "b737-nyc-045"
    "a350-lax-067"
    "b787-sea-089"
    "a321-atl-012"
)

AP_TYPES=("telecom" "wifi" "ife")
NETWORK_PROFILES=("ku_low_latency" "ku_high_latency" "ku_low_latency")
PREFERRED_REGIONS=("us-east" "us-west" "us-east")

# Deploy aircraft
for i in $(seq 0 $((NUM_AIRCRAFT - 1))); do
    AIRCRAFT_ID="${AIRCRAFT_IDS[$i]}"
    
    echo "Deploying aircraft: $AIRCRAFT_ID"
    
    # Create namespace
    NAMESPACE_FILE="$TEMP_DIR/namespace-${AIRCRAFT_ID}.yaml"
    sed -e "s/__AIRCRAFT_ID__/${AIRCRAFT_ID}/g" \
        -e "s/__AIRLINE__/${AIRLINE}/g" \
        "$K8S_DIR/namespace-template.yaml" > "$NAMESPACE_FILE"
    
    kubectl apply -f "$NAMESPACE_FILE"
    
    # Deploy each AP type
    for j in "${!AP_TYPES[@]}"; do
        AP_TYPE="${AP_TYPES[$j]}"
        NETWORK_PROFILE="${NETWORK_PROFILES[$j]}"
        PREFERRED_REGION="${PREFERRED_REGIONS[$j]}"
        AP_ID="${AIRCRAFT_ID}-${AP_TYPE}"
        
        echo "  - Deploying AP: $AP_TYPE (profile: $NETWORK_PROFILE, region: $PREFERRED_REGION)"
        
        DEPLOYMENT_FILE="$TEMP_DIR/deployment-${AIRCRAFT_ID}-${AP_TYPE}.yaml"
        sed -e "s/__AIRCRAFT_ID__/${AIRCRAFT_ID}/g" \
            -e "s/__AIRLINE__/${AIRLINE}/g" \
            -e "s/__AP_TYPE__/${AP_TYPE}/g" \
            -e "s/__AP_ID__/${AP_ID}/g" \
            -e "s/__NETWORK_PROFILE__/${NETWORK_PROFILE}/g" \
            -e "s/__PREFERRED_REGION__/${PREFERRED_REGION}/g" \
            "$K8S_DIR/ap-deployment-template.yaml" > "$DEPLOYMENT_FILE"
        
        kubectl apply -f "$DEPLOYMENT_FILE"
    done
    
    echo ""
done

echo "Waiting for pods to be ready..."
sleep 5

echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="

# Show namespaces
echo ""
echo "Aircraft namespaces:"
kubectl get namespaces | grep aircraft

# Show pods in each namespace
echo ""
for i in $(seq 0 $((NUM_AIRCRAFT - 1))); do
    AIRCRAFT_ID="${AIRCRAFT_IDS[$i]}"
    echo "Pods in aircraft-${AIRCRAFT_ID}:"
    kubectl get pods -n "aircraft-${AIRCRAFT_ID}" -o wide || true
    echo ""
done

echo "=========================================="
echo "✓ Aircraft deployment complete!"
echo "=========================================="
echo ""
echo "To view logs from a specific AP:"
echo "  kubectl logs -n aircraft-<AIRCRAFT_ID> <POD_NAME> -c ap-simulator"
echo ""
echo "To view all pods:"
echo "  kubectl get pods --all-namespaces | grep aircraft"
