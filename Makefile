.PHONY: help prereqs cluster build deploy controllers verify clean test-a test-b test-c all

help:
	@echo "IFE PoC - Makefile Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make prereqs     - Check prerequisites"
	@echo "  make cluster     - Create k3d cluster"
	@echo "  make build       - Build Docker images"
	@echo "  make controllers - Start controller instances"
	@echo "  make deploy      - Deploy aircraft to cluster"
	@echo "  make all         - Run complete setup (prereqs -> deploy)"
	@echo ""
	@echo "Testing:"
	@echo "  make verify      - Verify deployment"
	@echo "  make test-a      - Run acceptance test A (targeted config)"
	@echo "  make test-b      - Run acceptance test B (region failover)"
	@echo "  make test-c      - Run acceptance test C (recovery)"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean       - Remove cluster and data"
	@echo ""

prereqs:
	@./scripts/00_prereqs.sh

cluster:
	@./scripts/01_cluster.sh

build:
	@./scripts/02_build_images.sh

controllers:
	@./scripts/start_controllers.sh

deploy:
	@./scripts/03_deploy_aircraft.sh

verify:
	@./scripts/06_verify.sh

all: prereqs cluster build controllers deploy
	@echo ""
	@echo "=========================================="
	@echo "✓ Complete setup finished!"
	@echo "=========================================="
	@echo ""
	@echo "Next steps:"
	@echo "  make verify    - Verify deployment"
	@echo "  make test-a    - Run acceptance tests"

test-a:
	@echo "Running Acceptance Test A: Targeted Config Push"
	@./scripts/04_publish_config.sh test-a
	@echo ""
	@echo "Waiting for APs to poll and apply config..."
	@sleep 20
	@echo ""
	@echo "Checking controller status..."
	@curl -s http://localhost:8081/admin/status | jq '.aps[] | select(.aircraft_id == "a320-ind-023" and .ap_type == "wifi") | {ap_id, last_applied_version}'

test-b:
	@echo "Running Acceptance Test B: Region Failover"
	@./scripts/05_region_fail.sh us-east down
	@echo ""
	@echo "Waiting for failover to complete..."
	@sleep 30
	@echo ""
	@echo "Checking us-west controller status..."
	@curl -s http://localhost:8082/admin/status | jq '.total_aps'

test-c:
	@echo "Running Acceptance Test C: Recovery"
	@./scripts/05_region_fail.sh us-east up
	@echo ""
	@echo "Waiting for recovery..."
	@sleep 20
	@echo ""
	@echo "Checking both controllers..."
	@echo "US-EAST:"
	@curl -s http://localhost:8081/admin/status | jq '.total_aps'
	@echo "US-WEST:"
	@curl -s http://localhost:8082/admin/status | jq '.total_aps'

clean:
	@echo "Cleaning up..."
	@docker stop controller-us-east controller-us-west 2>/dev/null || true
	@docker rm controller-us-east controller-us-west 2>/dev/null || true
	@k3d cluster delete ife-poc 2>/dev/null || true
	@rm -rf .data .tmp
	@echo "✓ Cleanup complete"
