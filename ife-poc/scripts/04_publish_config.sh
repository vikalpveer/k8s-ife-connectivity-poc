#!/bin/bash
set -e

CONTROLLER_URL=${CONTROLLER_URL:-http://localhost:8081}

echo "=========================================="
echo "Publishing Configuration"
echo "=========================================="
echo "Controller URL: $CONTROLLER_URL"
echo ""

# Function to publish config
publish_config() {
    local version=$1
    local airline=$2
    local aircraft_id=$3
    local ap_type=$4
    local region=$5
    local payload=$6
    
    echo "Publishing config:"
    echo "  Version: $version"
    echo "  Airline: ${airline:-all}"
    echo "  Aircraft: ${aircraft_id:-all}"
    echo "  AP Type: ${ap_type:-all}"
    echo "  Region: ${region:-all}"
    
    # Build JSON payload
    local json_data=$(cat <<EOF
{
    "version": "$version",
    "airline": $([ -n "$airline" ] && echo "\"$airline\"" || echo "null"),
    "aircraft_id": $([ -n "$aircraft_id" ] && echo "\"$aircraft_id\"" || echo "null"),
    "ap_type": $([ -n "$ap_type" ] && echo "\"$ap_type\"" || echo "null"),
    "region": $([ -n "$region" ] && echo "\"$region\"" || echo "null"),
    "payload": $payload
}
EOF
)
    
    # Publish to controller
    response=$(curl -s -X POST "$CONTROLLER_URL/admin/publish" \
        -H "Content-Type: application/json" \
        -d "$json_data")
    
    echo "Response: $response"
    echo ""
}

# Check if specific config is requested
if [ $# -gt 0 ]; then
    case "$1" in
        test-a)
            echo "Running Test A: Targeted config push"
            echo "Publishing v2 config for Delta, a320-ind-023, wifi only"
            echo ""
            
            PAYLOAD='{"policy": "test-a", "bandwidth_limit": "20mbps", "priority": "high", "test": "acceptance-test-a"}'
            publish_config "v2" "Delta" "a320-ind-023" "wifi" "" "$PAYLOAD"
            ;;
        
        global)
            echo "Publishing global config v2 for all APs"
            echo ""
            
            PAYLOAD='{"policy": "global", "bandwidth_limit": "10mbps", "priority": "normal", "message": "Global configuration v2"}'
            publish_config "v2" "" "" "" "" "$PAYLOAD"
            ;;
        
        *)
            echo "Unknown config type: $1"
            echo "Usage: $0 [test-a|global]"
            exit 1
            ;;
    esac
else
    # Default: publish a sample config
    echo "Publishing default v2 config for all APs"
    echo ""
    
    PAYLOAD='{"policy": "default", "bandwidth_limit": "10mbps", "priority": "normal", "message": "Default configuration v2"}'
    publish_config "v2" "" "" "" "" "$PAYLOAD"
fi

echo "=========================================="
echo "✓ Configuration published!"
echo "=========================================="
echo ""
echo "To verify, check controller status:"
echo "  curl $CONTROLLER_URL/admin/status | jq"
echo ""
echo "To view AP logs:"
echo "  kubectl logs -n aircraft-<AIRCRAFT_ID> <POD_NAME> -c ap-simulator"
