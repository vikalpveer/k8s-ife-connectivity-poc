#!/bin/bash
set -e

REGION=${1:-us-east}
ACTION=${2:-down}

echo "=========================================="
echo "Region Failover Simulation"
echo "=========================================="
echo "Region: $REGION"
echo "Action: $ACTION"
echo ""

case "$ACTION" in
    down)
        echo "Simulating $REGION controller failure..."
        
        # Find and stop the controller container for this region
        CONTAINER_NAME="controller-${REGION}"
        
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "Stopping controller container: $CONTAINER_NAME"
            docker stop "$CONTAINER_NAME"
            echo "✓ Controller stopped"
        else
            echo "⚠ Controller container not found: $CONTAINER_NAME"
            echo "Available containers:"
            docker ps --format "table {{.Names}}\t{{.Status}}" | grep controller || echo "No controller containers running"
        fi
        
        echo ""
        echo "Monitoring AP behavior..."
        echo "APs should failover to alternate region with exponential backoff"
        echo ""
        echo "To monitor AP logs:"
        echo "  kubectl logs -f -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator"
        ;;
    
    up)
        echo "Restoring $REGION controller..."
        
        CONTAINER_NAME="controller-${REGION}"
        
        if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "Starting controller container: $CONTAINER_NAME"
            docker start "$CONTAINER_NAME"
            echo "✓ Controller started"
        else
            echo "⚠ Controller container not found: $CONTAINER_NAME"
            echo "You may need to start the controller manually"
        fi
        
        echo ""
        echo "APs should detect restored controller and may switch back"
        ;;
    
    *)
        echo "Unknown action: $ACTION"
        echo "Usage: $0 <region> <down|up>"
        echo "Example: $0 us-east down"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "✓ Region failover simulation complete!"
echo "=========================================="
