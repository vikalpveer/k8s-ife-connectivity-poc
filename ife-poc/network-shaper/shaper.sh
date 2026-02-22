#!/bin/bash
set -e

# Network shaping script for simulating satellite connectivity
# Runs as a sidecar container to apply tc netem rules

PROFILE=${NETWORK_PROFILE:-ku_low_latency}
INTERFACE=${INTERFACE:-eth0}

echo "Starting network shaper with profile: $PROFILE on interface: $INTERFACE"

# Function to apply network shaping
apply_shaping() {
    local profile=$1
    
    # Clear any existing rules
    tc qdisc del dev $INTERFACE root 2>/dev/null || true
    
    case $profile in
        ku_high_latency)
            echo "Applying KU high latency profile"
            # High latency: 600ms +/- 100ms, 2% loss, 2Mbps bandwidth
            tc qdisc add dev $INTERFACE root handle 1: netem delay 600ms 100ms loss 2%
            tc qdisc add dev $INTERFACE parent 1:1 handle 10: tbf rate 2mbit burst 32kbit latency 400ms
            ;;
        ku_low_latency)
            echo "Applying KU low latency profile"
            # Low latency: 200ms +/- 30ms, 0.5% loss, 10Mbps bandwidth
            tc qdisc add dev $INTERFACE root handle 1: netem delay 200ms 30ms loss 0.5%
            tc qdisc add dev $INTERFACE parent 1:1 handle 10: tbf rate 10mbit burst 32kbit latency 400ms
            ;;
        ka_band)
            echo "Applying KA band profile"
            # KA band: 100ms +/- 20ms, 0.1% loss, 50Mbps bandwidth
            tc qdisc add dev $INTERFACE root handle 1: netem delay 100ms 20ms loss 0.1%
            tc qdisc add dev $INTERFACE parent 1:1 handle 10: tbf rate 50mbit burst 64kbit latency 400ms
            ;;
        none)
            echo "No network shaping applied"
            ;;
        *)
            echo "Unknown profile: $profile, using ku_low_latency"
            apply_shaping ku_low_latency
            return
            ;;
    esac
    
    echo "Network shaping applied successfully"
    tc qdisc show dev $INTERFACE
}

# Apply initial shaping
apply_shaping $PROFILE

# Keep container running and monitor for profile changes
echo "Network shaper running. Monitoring for changes..."
while true; do
    sleep 60
    # In a real implementation, could watch for config changes and reapply
done
