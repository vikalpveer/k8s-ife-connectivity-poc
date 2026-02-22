# Kubernetes Learning Guide

## Understanding Kubernetes Through the IFE PoC Project

This document explains core Kubernetes concepts and demonstrates how the IFE (In-Flight Entertainment) PoC project helps you explore and understand them in a practical, hands-on way.

---

## Table of Contents

1. [What is Kubernetes?](#what-is-kubernetes)
2. [Core Kubernetes Concepts](#core-kubernetes-concepts)
3. [How This Project Demonstrates Each Concept](#how-this-project-demonstrates-each-concept)
4. [Hands-On Learning Exercises](#hands-on-learning-exercises)
5. [Advanced Concepts Explored](#advanced-concepts-explored)

---

## What is Kubernetes?

**Kubernetes (K8s)** is an open-source container orchestration platform that automates the deployment, scaling, and management of containerized applications.

### Why Kubernetes?

- **Container Orchestration**: Manages multiple containers across multiple machines
- **Self-Healing**: Automatically restarts failed containers
- **Scaling**: Scales applications up or down based on demand
- **Service Discovery**: Enables containers to find and communicate with each other
- **Rolling Updates**: Updates applications without downtime
- **Resource Management**: Efficiently allocates CPU and memory

### The Problem Kubernetes Solves

Imagine you have 100 microservices running in containers across 50 servers. Without Kubernetes:
- Manual deployment and updates
- No automatic recovery from failures
- Complex networking setup
- Difficult resource allocation
- No centralized management

Kubernetes automates all of this!

---

## Core Kubernetes Concepts

### 1. Cluster

**What it is**: A set of machines (nodes) that run containerized applications managed by Kubernetes.

**Components**:
- **Control Plane**: Manages the cluster (scheduling, maintaining state, scaling)
- **Worker Nodes**: Run the actual application containers

**In This Project**:
```bash
# We use k3d to create a lightweight Kubernetes cluster
k3d cluster create ife-poc --agents 1
```

This creates:
- 1 server node (control plane)
- 1 agent node (worker)

**Explore It**:
```bash
# View cluster information
kubectl cluster-info

# View nodes in the cluster
kubectl get nodes

# Describe a node to see its details
kubectl describe node k3d-ife-poc-server-0
```

---

### 2. Namespace

**What it is**: A virtual cluster within a physical cluster. Provides isolation and organization for resources.

**Use Cases**:
- Multi-tenancy (different teams/projects)
- Environment separation (dev, staging, prod)
- Resource quotas and access control

**In This Project**:
We create one namespace per aircraft, demonstrating multi-tenancy:

```yaml
# k8s/namespace-template.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: aircraft-a320-ind-023
  labels:
    type: aircraft
    aircraft-id: a320-ind-023
    airline: Delta
```

**Why This Matters**:
- Each aircraft is logically isolated
- Resources can be managed per aircraft
- Easy to delete all resources for one aircraft
- Simulates real-world multi-tenant scenarios

**Explore It**:
```bash
# List all aircraft namespaces
kubectl get namespaces | grep aircraft

# View resources in a specific namespace
kubectl get all -n aircraft-a320-ind-023

# Delete an entire aircraft (all its resources)
kubectl delete namespace aircraft-a320-ind-023
```

**Real-World Analogy**: Think of namespaces like apartments in a building. Each tenant (aircraft) has their own space, but they share the building infrastructure (cluster).

---

### 3. Pod

**What it is**: The smallest deployable unit in Kubernetes. A pod contains one or more containers that share storage and network.

**Key Characteristics**:
- Containers in a pod share the same IP address
- They can communicate via localhost
- They share storage volumes
- Scheduled together on the same node

**In This Project**:
Each AP (Access Point) runs as a pod with two containers:

```yaml
# Simplified pod structure
Pod: ap-wifi
├── Container 1: ap-simulator (main application)
└── Container 2: network-shaper (sidecar)
```

**Why Two Containers?**:
- **Separation of Concerns**: Main app logic vs. network configuration
- **Sidecar Pattern**: Helper container enhances main container
- **Shared Network**: Both containers see the same network interface

**Explore It**:
```bash
# List all pods
kubectl get pods --all-namespaces | grep aircraft

# Describe a pod to see its containers
kubectl describe pod -n aircraft-a320-ind-023 ap-wifi-xxxxx

# View logs from specific container
kubectl logs -n aircraft-a320-ind-023 ap-wifi-xxxxx -c ap-simulator

# Execute command in a container
kubectl exec -it -n aircraft-a320-ind-023 ap-wifi-xxxxx -c network-shaper -- sh
```

**Real-World Analogy**: A pod is like a car. The main container is the engine, and the sidecar is the GPS system. They work together, share the same vehicle (network/storage), and are always together.

---

### 4. Deployment

**What it is**: Manages a set of identical pods, ensuring the desired number of replicas are running.

**Features**:
- **Declarative Updates**: Describe desired state, K8s makes it happen
- **Rolling Updates**: Update pods gradually without downtime
- **Rollback**: Revert to previous version if needed
- **Scaling**: Easily increase/decrease replicas

**In This Project**:
Each AP type is managed by a Deployment:

```yaml
# k8s/ap-deployment-template.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ap-wifi
  namespace: aircraft-a320-ind-023
spec:
  replicas: 1  # How many pods to run
  selector:
    matchLabels:
      ap-type: wifi
  template:
    # Pod template here
```

**Explore It**:
```bash
# View deployments
kubectl get deployments -n aircraft-a320-ind-023

# Scale a deployment (increase replicas)
kubectl scale deployment ap-wifi -n aircraft-a320-ind-023 --replicas=3

# View the new pods created
kubectl get pods -n aircraft-a320-ind-023

# Scale back down
kubectl scale deployment ap-wifi -n aircraft-a320-ind-023 --replicas=1

# View deployment history
kubectl rollout history deployment ap-wifi -n aircraft-a320-ind-023
```

**Real-World Analogy**: A deployment is like a factory production line. You specify how many products (pods) you want, and the factory (Kubernetes) ensures that many are always being produced, replacing any defective ones automatically.

---

### 5. Labels and Selectors

**What they are**: 
- **Labels**: Key-value pairs attached to objects for identification
- **Selectors**: Query labels to find specific objects

**Use Cases**:
- Organizing resources
- Selecting pods for services
- Filtering in queries

**In This Project**:
We use labels extensively:

```yaml
labels:
  app: ap-simulator
  ap-type: wifi
  aircraft-id: a320-ind-023
  airline: Delta
```

**Explore It**:
```bash
# Find all wifi APs across all aircraft
kubectl get pods --all-namespaces -l ap-type=wifi

# Find all APs for a specific aircraft
kubectl get pods --all-namespaces -l aircraft-id=a320-ind-023

# Find all Delta airline APs
kubectl get pods --all-namespaces -l airline=Delta

# Combine multiple labels
kubectl get pods --all-namespaces -l ap-type=wifi,airline=Delta

# View logs from all wifi APs
kubectl logs -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator --tail=20
```

**Real-World Analogy**: Labels are like tags on products in a warehouse. You can quickly find all "red" items, all "large" items, or all "red AND large" items using selectors.

---

### 6. Container Images

**What they are**: Packaged applications with all dependencies, ready to run.

**In This Project**:
We build three custom images:

1. **controller:latest** - FastAPI application
2. **ap-simulator:latest** - Python agent
3. **network-shaper:latest** - Alpine with tc tools

**Build Process**:
```bash
# Build images
docker build -t controller:latest ./controller
docker build -t ap-simulator:latest ./ap-sim
docker build -t network-shaper:latest ./network-shaper

# Import into k3d cluster
k3d image import controller:latest -c ife-poc
```

**Explore It**:
```bash
# View images in Docker
docker images | grep -E "controller|ap-simulator|network-shaper"

# View image details
docker inspect ap-simulator:latest

# View what's inside an image
docker run --rm -it ap-simulator:latest sh
```

**Real-World Analogy**: Container images are like shipping containers. They package everything needed (app + dependencies) in a standardized format that can run anywhere.

---

### 7. Environment Variables

**What they are**: Configuration values passed to containers at runtime.

**In This Project**:
Each AP pod receives configuration via environment variables:

```yaml
env:
- name: AP_ID
  value: "a320-ind-023-wifi"
- name: AIRCRAFT_ID
  value: "a320-ind-023"
- name: AIRLINE
  value: "Delta"
- name: AP_TYPE
  value: "wifi"
- name: PREFERRED_REGION
  value: "us-west"
- name: CONTROLLER_US_EAST
  value: "http://controller-us-east:8081"
```

**Why This Matters**:
- Same image, different configuration
- No need to rebuild images for different environments
- Secrets can be injected securely

**Explore It**:
```bash
# View environment variables in a pod
kubectl exec -n aircraft-a320-ind-023 ap-wifi-xxxxx -c ap-simulator -- env

# View specific variable
kubectl exec -n aircraft-a320-ind-023 ap-wifi-xxxxx -c ap-simulator -- printenv AP_ID
```

---

### 8. Resource Limits

**What they are**: CPU and memory constraints for containers.

**In This Project**:
```yaml
resources:
  requests:  # Minimum guaranteed
    memory: "64Mi"
    cpu: "50m"
  limits:    # Maximum allowed
    memory: "128Mi"
    cpu: "200m"
```

**Why This Matters**:
- Prevents one pod from consuming all resources
- Helps Kubernetes schedule pods efficiently
- Ensures fair resource distribution

**Explore It**:
```bash
# View resource usage
kubectl top pods -n aircraft-a320-ind-023

# View resource requests/limits
kubectl describe pod -n aircraft-a320-ind-023 ap-wifi-xxxxx | grep -A 5 "Limits"
```

**Real-World Analogy**: Like giving each employee a desk (request) and a maximum office space (limit). Everyone gets what they need, but no one can take over the entire floor.

---

### 9. Security Context

**What it is**: Security settings for pods and containers.

**In This Project**:
The network-shaper needs special permissions:

```yaml
securityContext:
  capabilities:
    add:
    - NET_ADMIN  # Required for tc netem commands
  privileged: false
```

**Why This Matters**:
- Principle of least privilege
- Only grant necessary permissions
- Reduces security risks

**Explore It**:
```bash
# View security context
kubectl get pod -n aircraft-a320-ind-023 ap-wifi-xxxxx -o yaml | grep -A 10 securityContext

# Test network shaping
kubectl exec -n aircraft-a320-ind-023 ap-wifi-xxxxx -c network-shaper -- tc qdisc show dev eth0
```

---

### 10. Multi-Container Pods (Sidecar Pattern)

**What it is**: Running multiple containers in a single pod that work together.

**Common Patterns**:
- **Sidecar**: Helper container (logging, monitoring, proxying)
- **Ambassador**: Proxy container for external services
- **Adapter**: Transforms output for standardization

**In This Project**:
We use the **Sidecar Pattern**:

```
┌─────────────────────────────────┐
│          Pod: ap-wifi            │
│                                  │
│  ┌──────────────────────────┐   │
│  │   ap-simulator           │   │
│  │   (Main Application)     │   │
│  └──────────────────────────┘   │
│                                  │
│  ┌──────────────────────────┐   │
│  │   network-shaper         │   │
│  │   (Sidecar - tc netem)   │   │
│  └──────────────────────────┘   │
│                                  │
│  Shared: Network, Volumes        │
└─────────────────────────────────┘
```

**Why This Pattern?**:
- **Separation of Concerns**: Main app doesn't need to know about network shaping
- **Reusability**: Network shaper can be used with any app
- **Independent Updates**: Update shaper without touching main app

**Explore It**:
```bash
# View both containers in a pod
kubectl get pod -n aircraft-a320-ind-023 ap-wifi-xxxxx -o jsonpath='{.spec.containers[*].name}'

# View logs from each container
kubectl logs -n aircraft-a320-ind-023 ap-wifi-xxxxx -c ap-simulator --tail=10
kubectl logs -n aircraft-a320-ind-023 ap-wifi-xxxxx -c network-shaper --tail=10

# Exec into each container
kubectl exec -it -n aircraft-a320-ind-023 ap-wifi-xxxxx -c ap-simulator -- sh
kubectl exec -it -n aircraft-a320-ind-023 ap-wifi-xxxxx -c network-shaper -- sh
```

---

## How This Project Demonstrates Each Concept

### 1. Multi-Tenancy with Namespaces

**Concept**: Isolating resources for different tenants

**In This Project**:
- Each aircraft = separate namespace
- 5 aircraft = 5 namespaces
- Simulates airline managing multiple planes

**Try It**:
```bash
# Deploy only 2 aircraft
NUM_AIRCRAFT=2 ./scripts/03_deploy_aircraft.sh

# View isolation
kubectl get pods -n aircraft-a320-ind-023
kubectl get pods -n aircraft-b737-nyc-045

# Delete one aircraft without affecting others
kubectl delete namespace aircraft-a320-ind-023
```

---

### 2. Declarative Configuration

**Concept**: Describe desired state, Kubernetes makes it happen

**In This Project**:
- YAML manifests describe what we want
- Kubernetes ensures it exists
- Self-healing if pods crash

**Try It**:
```bash
# Apply a deployment
kubectl apply -f .tmp/deployment-a320-ind-023-wifi.yaml

# Delete a pod (Kubernetes will recreate it)
kubectl delete pod -n aircraft-a320-ind-023 ap-wifi-xxxxx

# Watch it come back
kubectl get pods -n aircraft-a320-ind-023 -w
```

---

### 3. Service Discovery and Networking

**Concept**: Containers finding and communicating with each other

**In This Project**:
- APs discover controllers by name
- Controllers run on k3d network
- DNS resolution: `controller-us-east` → IP address

**Network Flow**:
```
Pod (ap-wifi)
    ↓
DNS Lookup: controller-us-west
    ↓
k3d Network DNS
    ↓
Resolves to: 172.18.0.X
    ↓
HTTP Request to controller
```

**Try It**:
```bash
# View DNS resolution from inside a pod
kubectl exec -n aircraft-a320-ind-023 ap-wifi-xxxxx -c ap-simulator -- \
  python3 -c "import socket; print(socket.gethostbyname('controller-us-west'))"

# View network interfaces
kubectl exec -n aircraft-a320-ind-023 ap-wifi-xxxxx -c network-shaper -- ip addr
```

---

### 4. Configuration Management

**Concept**: Externalizing configuration from code

**In This Project**:
- Environment variables for configuration
- Same image, different config per AP
- No hardcoded values

**Configuration Hierarchy**:
```
Template (k8s/ap-deployment-template.yaml)
    ↓
Script substitution (03_deploy_aircraft.sh)
    ↓
Generated manifest (.tmp/deployment-*.yaml)
    ↓
Applied to cluster
    ↓
Environment variables in container
```

**Try It**:
```bash
# View generated manifest
cat .tmp/deployment-a320-ind-023-wifi.yaml

# Compare with template
diff k8s/ap-deployment-template.yaml .tmp/deployment-a320-ind-023-wifi.yaml
```

---

### 5. Observability and Logging

**Concept**: Understanding what's happening in your cluster

**In This Project**:
- Structured JSON logging
- Centralized log collection via kubectl
- Real-time monitoring

**Try It**:
```bash
# View logs from all wifi APs
kubectl logs -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator --tail=20

# Follow logs in real-time
kubectl logs -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator -f

# Parse JSON logs
kubectl logs -n aircraft-a320-ind-023 -l ap-type=wifi -c ap-simulator --tail=100 | \
  grep "Registration successful"
```

---

### 6. Scaling and Resource Management

**Concept**: Running multiple instances and managing resources

**In This Project**:
- Each AP has resource requests/limits
- Can scale deployments up/down
- Kubernetes schedules based on available resources

**Try It**:
```bash
# Scale up wifi APs
kubectl scale deployment ap-wifi -n aircraft-a320-ind-023 --replicas=3

# Watch pods being created
kubectl get pods -n aircraft-a320-ind-023 -w

# View resource usage
kubectl top pods -n aircraft-a320-ind-023

# Scale back down
kubectl scale deployment ap-wifi -n aircraft-a320-ind-023 --replicas=1
```

---

### 7. Container Lifecycle

**Concept**: Understanding how containers start, run, and stop

**In This Project**:
- Containers start with specific commands
- Environment variables loaded at startup
- Graceful shutdown on termination

**Lifecycle Flow**:
```
1. Image Pull (if not cached)
2. Container Creation
3. Environment Variables Injected
4. Command Execution (python agent.py)
5. Application Startup
6. Running State
7. Termination Signal (SIGTERM)
8. Graceful Shutdown
9. Container Removal
```

**Try It**:
```bash
# View container command
kubectl get pod -n aircraft-a320-ind-023 ap-wifi-xxxxx -o jsonpath='{.spec.containers[0].command}'

# View container status
kubectl describe pod -n aircraft-a320-ind-023 ap-wifi-xxxxx | grep -A 10 "Container"

# Restart a pod
kubectl delete pod -n aircraft-a320-ind-023 ap-wifi-xxxxx
```

---

## Hands-On Learning Exercises

### Exercise 1: Namespace Isolation

**Goal**: Understand how namespaces provide isolation

```bash
# 1. Create a test namespace
kubectl create namespace test-isolation

# 2. Try to access pods in aircraft namespace from test namespace
kubectl get pods -n test-isolation  # Empty
kubectl get pods -n aircraft-a320-ind-023  # Has pods

# 3. Deploy something in test namespace
kubectl run nginx --image=nginx -n test-isolation

# 4. Verify isolation
kubectl get pods -n test-isolation
kubectl get pods -n aircraft-a320-ind-023

# 5. Cleanup
kubectl delete namespace test-isolation
```

**Learning**: Namespaces provide logical isolation. Resources in one namespace don't appear in another.

---

### Exercise 2: Pod Communication

**Goal**: Understand how pods communicate

```bash
# 1. Get IP of a controller
docker inspect controller-us-east | grep IPAddress

# 2. Test connectivity from a pod
kubectl exec -n aircraft-a320-ind-023 ap-wifi-xxxxx -c ap-simulator -- \
  python3 -c "import requests; print(requests.get('http://controller-us-east:8081/health').json())"

# 3. View network from inside pod
kubectl exec -n aircraft-a320-ind-023 ap-wifi-xxxxx -c network-shaper -- ip route
```

**Learning**: Pods can reach external containers by name when on the same Docker network.

---

### Exercise 3: Resource Limits in Action

**Goal**: See what happens when a container exceeds limits

```bash
# 1. View current resource usage
kubectl top pod -n aircraft-a320-ind-023 ap-wifi-xxxxx

# 2. View resource limits
kubectl describe pod -n aircraft-a320-ind-023 ap-wifi-xxxxx | grep -A 5 "Limits"

# 3. Try to use more memory (this would cause OOMKilled if exceeded)
# Note: Our apps are lightweight, so they won't hit limits in normal operation
```

**Learning**: Kubernetes enforces resource limits to prevent resource exhaustion.

---

### Exercise 4: Label-Based Operations

**Goal**: Use labels for bulk operations

```bash
# 1. Find all wifi APs
kubectl get pods --all-namespaces -l ap-type=wifi

# 2. View logs from all wifi APs
for pod in $(kubectl get pods -n aircraft-a320-ind-023 -l ap-type=wifi -o name); do
  echo "=== $pod ==="
  kubectl logs -n aircraft-a320-ind-023 $pod -c ap-simulator --tail=5
done

# 3. Delete all wifi APs (they'll be recreated by deployment)
kubectl delete pods -n aircraft-a320-ind-023 -l ap-type=wifi

# 4. Watch them come back
kubectl get pods -n aircraft-a320-ind-023 -w
```

**Learning**: Labels enable powerful bulk operations and queries.

---

### Exercise 5: Deployment Updates

**Goal**: Update a deployment and watch rollout

```bash
# 1. View current deployment
kubectl get deployment ap-wifi -n aircraft-a320-ind-023

# 2. Update image (simulate new version)
kubectl set image deployment/ap-wifi ap-simulator=ap-simulator:v2 -n aircraft-a320-ind-023

# 3. Watch rollout (will fail since v2 doesn't exist, but shows the process)
kubectl rollout status deployment/ap-wifi -n aircraft-a320-ind-023

# 4. Rollback
kubectl rollout undo deployment/ap-wifi -n aircraft-a320-ind-023

# 5. View rollout history
kubectl rollout history deployment/ap-wifi -n aircraft-a320-ind-023
```

**Learning**: Kubernetes manages rolling updates and rollbacks automatically.

---

## Advanced Concepts Explored

### 1. Network Policies (Conceptual)

**What it is**: Firewall rules for pods

**In This Project**: Not implemented, but could be added to:
- Restrict which pods can talk to controllers
- Isolate aircraft from each other
- Allow only specific ports

**How to Add**:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-controller-access
  namespace: aircraft-a320-ind-023
spec:
  podSelector:
    matchLabels:
      app: ap-simulator
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 8081
    - protocol: TCP
      port: 8082
```

---

### 2. ConfigMaps and Secrets

**What they are**: 
- **ConfigMaps**: Non-sensitive configuration data
- **Secrets**: Sensitive data (passwords, tokens)

**In This Project**: We use environment variables directly, but could use ConfigMaps:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: controller-config
data:
  us-east-url: "http://controller-us-east:8081"
  us-west-url: "http://controller-us-west:8082"
---
# Reference in pod
env:
- name: CONTROLLER_US_EAST
  valueFrom:
    configMapKeyRef:
      name: controller-config
      key: us-east-url
```

---

### 3. Persistent Volumes

**What they are**: Storage that persists beyond pod lifecycle

**In This Project**: Controllers use Docker volumes for SQLite databases:

```bash
# View controller data
ls -la ife-poc/.data/
cat ife-poc/.data/controller-us-east.db
```

**In Kubernetes**: Would use PersistentVolumeClaims:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: controller-data
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

---

### 4. Health Checks

**What they are**: Probes to check if containers are healthy

**Types**:
- **Liveness Probe**: Is the container alive? (restart if not)
- **Readiness Probe**: Is the container ready for traffic?
- **Startup Probe**: Has the container started?

**How to Add to This Project**:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 3
```

---

### 5. Horizontal Pod Autoscaling

**What it is**: Automatically scale pods based on metrics

**Example**:
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ap-wifi-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ap-wifi
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
```

---

## Key Takeaways

### What You've Learned

1. **Cluster Architecture**: Control plane + worker nodes
2. **Namespaces**: Logical isolation and multi-tenancy
3. **Pods**: Smallest deployable units, can have multiple containers
4. **Deployments**: Manage pod replicas and updates
5. **Labels**: Organize and query resources
6. **Networking**: Service discovery and container communication
7. **Configuration**: Environment variables and external config
8. **Resource Management**: CPU/memory requests and limits
9. **Security**: Capabilities and security contexts
10. **Observability**: Logging and monitoring

### Real-World Applications

This project simulates real scenarios:

- **Multi-Tenancy**: SaaS platforms with customer isolation
- **Microservices**: Multiple services communicating
- **Sidecar Pattern**: Service mesh, logging, monitoring
- **Configuration Management**: Environment-specific settings
- **High Availability**: Multiple regions, failover
- **Resource Optimization**: Efficient resource allocation

### Next Steps

1. **Add Services**: Expose APs via Kubernetes Services
2. **Implement Ingress**: External access to controllers
3. **Add Monitoring**: Prometheus + Grafana
4. **Implement RBAC**: Role-based access control
5. **Add Network Policies**: Restrict pod communication
6. **Use Helm**: Package management for Kubernetes
7. **Implement GitOps**: ArgoCD or Flux for deployments

---

## Conclusion

This IFE PoC project provides a practical, hands-on way to learn Kubernetes concepts. By simulating a real-world scenario (aircraft access points), you've explored:

- Core Kubernetes primitives
- Multi-container patterns
- Networking and service discovery
- Configuration management
- Resource management
- Observability

The best way to learn is by doing. Experiment with the commands, break things, fix them, and understand why they work the way they do.

**Happy Learning! 🚀**
