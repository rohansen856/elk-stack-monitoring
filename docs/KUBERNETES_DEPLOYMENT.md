# Kubernetes Deployment Guide

## Overview

This guide provides comprehensive instructions for deploying the Advanced Threat Detection System on Kubernetes using either Kind or Minikube for production-grade local development.

## Prerequisites

### Required Software
- **Docker**: Container runtime
- **kubectl**: Kubernetes command-line tool
- **Either Kind or Minikube**:
  - **Kind**: Recommended for CI/CD and lightweight testing
  - **Minikube**: Better for local development with more features

### System Requirements
- **Memory**: 8GB+ RAM recommended
- **CPU**: 4+ cores recommended
- **Storage**: 50GB+ available disk space
- **Network**: Internet connectivity for image pulls

## Quick Start

### 1. Automated Deployment

```bash
# Clone the repository and navigate to project root
git clone <repository-url>
cd ps25238

# Make scripts executable (if needed)
chmod +x scripts/*.sh

# Deploy everything automatically
./scripts/k8s-deploy.sh
```

The deployment script will:
- ✅ Detect and start Kind/Minikube cluster
- ✅ Build Docker images for backend and frontend
- ✅ Load images into the cluster
- ✅ Install NGINX Ingress Controller
- ✅ Deploy all application components
- ✅ Run database migrations
- ✅ Provide access URLs

### 2. Monitor Deployment

```bash
# Check system status
./scripts/k8s-monitor.sh

# View pods
kubectl get pods -n threat-detection

# View logs
kubectl logs -f deployment/backend -n threat-detection
```

### 3. Access Applications

#### For Kind Clusters
Use port-forwarding in separate terminals:
```bash
# Frontend (Next.js)
kubectl port-forward -n threat-detection svc/frontend 3000:3000

# Backend API (FastAPI)
kubectl port-forward -n threat-detection svc/backend 8000:8000

# Kibana Dashboard
kubectl port-forward -n threat-detection svc/kibana 5601:5601
```

Then access:
- **Frontend**: http://localhost:3000
- **API Docs**: http://localhost:8000/docs
- **Kibana**: http://localhost:5601

#### For Minikube Clusters
```bash
# Get service URLs
minikube service frontend-loadbalancer -n threat-detection --url
minikube service backend-loadbalancer -n threat-detection --url
minikube service kibana-loadbalancer -n threat-detection --url
```

## Manual Deployment

### 1. Cluster Setup

#### Using Kind
```bash
# Create cluster with custom config
kind create cluster --config scripts/kind-config.yaml

# Verify cluster
kubectl cluster-info --context kind-threat-detection
```

#### Using Minikube
```bash
# Start Minikube with adequate resources
minikube start --cpus=4 --memory=8192 --disk-size=50g

# Verify cluster
kubectl cluster-info
```

### 2. Build and Load Images

```bash
# Build backend image
docker build -t ps25238-app:latest .

# Build frontend image
docker build -t ps25238-frontend:latest ./website

# Load images into cluster
# For Kind:
kind load docker-image ps25238-app:latest
kind load docker-image ps25238-frontend:latest

# For Minikube:
minikube image load ps25238-app:latest
minikube image load ps25238-frontend:latest
```

### 3. Install Ingress Controller

#### For Kind
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for readiness
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

#### For Minikube
```bash
minikube addons enable ingress
```

### 4. Deploy Application

```bash
# Deploy all components using Kustomize
kubectl apply -k k8s/base/

# Wait for deployments
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n threat-detection
kubectl wait --for=condition=available --timeout=300s deployment/backend -n threat-detection
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n threat-detection
```

## Architecture Overview

### Kubernetes Resources

#### Core Components
- **Namespace**: `threat-detection` - Isolated environment for all resources
- **ConfigMap**: Application configuration and environment variables
- **Secret**: Sensitive data (passwords, keys) in base64 encoding

#### Data Layer
- **PostgreSQL**:
  - Deployment with persistent volume (5GB)
  - Service for database connectivity
  - Health checks and resource limits
- **Redis**:
  - Deployment with persistent volume (1GB)
  - Service for cache connectivity
  - Health checks and resource limits

#### ELK Stack
- **Elasticsearch**:
  - Single-node deployment with persistent volume (10GB)
  - Optimized for security data storage
  - Init containers for proper setup
- **Logstash**:
  - Log processing and enrichment
  - Multiple input ports (Beats, TCP, Syslog)
  - ConfigMap for pipeline configuration
- **Kibana**:
  - Security dashboards and visualization
  - Connected to Elasticsearch
  - ConfigMap for custom configuration

#### Application Layer
- **Backend (FastAPI)**:
  - 2 replicas with horizontal pod autoscaling
  - Health checks and readiness probes
  - Init containers waiting for dependencies
  - Resource requests and limits
- **Frontend (Next.js)**:
  - 2 replicas with horizontal pod autoscaling
  - Production optimized build
  - Health checks via API route

#### Monitoring
- **Filebeat**: DaemonSet for container log collection
- **Metricbeat**: DaemonSet for system metrics collection
- **ServiceAccounts & RBAC**: Proper permissions for monitoring

#### Networking
- **Services**: ClusterIP services for internal communication
- **LoadBalancer**: External access for Minikube
- **Ingress**: HTTP routing and SSL termination
- **NetworkPolicies**: Security policies (optional)

### Resource Management

#### Resource Requests & Limits
```yaml
# Example: Backend deployment
resources:
  requests:
    memory: "512Mi"
    cpu: "300m"
  limits:
    memory: "1Gi"
    cpu: "600m"
```

#### Horizontal Pod Autoscaling
- **Backend**: 2-10 replicas based on CPU (70%) and Memory (80%)
- **Frontend**: 2-8 replicas based on CPU (70%) and Memory (80%)

#### Persistent Storage
- **PostgreSQL**: 5GB for database data
- **Redis**: 1GB for cache data
- **Elasticsearch**: 10GB for security logs and indices

## Configuration Management

### Environment Variables
Managed through ConfigMap and Secrets:

```yaml
# ConfigMap (non-sensitive)
ENVIRONMENT: "production"
DATABASE_URL: "postgresql://user:password@postgres:5432/todo_db"
ELASTICSEARCH_URL: "http://elasticsearch:9200"

# Secret (sensitive, base64 encoded)
SECRET_KEY: <base64-encoded-jwt-secret>
POSTGRES_PASSWORD: <base64-encoded-password>
```

### Customization with Kustomize

#### Development Overlay
```bash
# Create development-specific configurations
mkdir -p k8s/overlays/development
cat > k8s/overlays/development/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: threat-detection-dev

resources:
  - ../../base

patchesStrategicMerge:
  - replica-override.yaml

replicas:
  - name: backend
    count: 1
  - name: frontend
    count: 1
EOF
```

#### Production Overlay
```bash
# Create production-specific configurations
mkdir -p k8s/overlays/production
# Add SSL certificates, resource limits, etc.
```

## Monitoring and Observability

### Health Checks
All services include:
- **Liveness Probes**: Restart unhealthy containers
- **Readiness Probes**: Control traffic routing
- **Startup Probes**: Handle slow-starting containers

### Logging
- **Centralized Logging**: All logs go to Elasticsearch via Filebeat
- **Structured Logs**: JSON format for easy parsing
- **Log Retention**: Configurable retention policies

### Metrics
- **Application Metrics**: Prometheus metrics from FastAPI
- **System Metrics**: Node and pod metrics via Metricbeat
- **Custom Metrics**: Security-specific metrics

### Troubleshooting Commands

```bash
# Check cluster status
kubectl get all -n threat-detection

# View pod logs
kubectl logs -f deployment/backend -n threat-detection
kubectl logs -f deployment/frontend -n threat-detection

# Describe resources for troubleshooting
kubectl describe pod <pod-name> -n threat-detection
kubectl describe deployment backend -n threat-detection

# Check events
kubectl get events -n threat-detection --sort-by='.lastTimestamp'

# Shell into containers
kubectl exec -it deployment/backend -n threat-detection -- /bin/bash

# Port forward for debugging
kubectl port-forward deployment/backend 8000:8000 -n threat-detection
```

## Security Considerations

### Network Security
- **Network Policies**: Control inter-pod communication
- **Service Mesh**: Consider Istio for advanced security (optional)
- **Ingress TLS**: SSL/TLS termination at ingress level

### Pod Security
- **Security Contexts**: Non-root user execution where possible
- **Resource Limits**: Prevent resource exhaustion
- **Read-only Root Filesystem**: Where applicable

### Secret Management
- **Kubernetes Secrets**: Base64 encoded sensitive data
- **External Secret Management**: Consider Vault/External Secrets Operator
- **RBAC**: Role-based access control for service accounts

## Performance Optimization

### Resource Optimization
- **Horizontal Pod Autoscaling**: Scale based on metrics
- **Vertical Pod Autoscaling**: Adjust resource requests automatically
- **Node Affinity**: Schedule pods on appropriate nodes

### Storage Optimization
- **Storage Classes**: Use appropriate storage for workloads
- **Volume Snapshots**: Backup critical data
- **Storage Monitoring**: Track disk usage and performance

## Backup and Recovery

### Database Backup
```bash
# Manual backup
kubectl exec deployment/postgres -n threat-detection -- pg_dump -U user todo_db > backup.sql

# Restore backup
kubectl exec -i deployment/postgres -n threat-detection -- psql -U user -d todo_db < backup.sql
```

### Elasticsearch Backup
```bash
# Create snapshot repository (requires configuration)
# Use Elasticsearch snapshot and restore API
```

## Cleanup

### Remove Application
```bash
# Use cleanup script
./scripts/k8s-cleanup.sh

# Manual cleanup
kubectl delete -k k8s/base/
kubectl delete namespace threat-detection
```

### Remove Cluster
```bash
# Kind
kind delete cluster

# Minikube
minikube delete
```

## Production Considerations

### High Availability
- **Multi-node Cluster**: Run across multiple nodes
- **Pod Disruption Budgets**: Ensure service availability during updates
- **Anti-affinity Rules**: Spread replicas across nodes

### Scaling
- **Cluster Autoscaling**: Add/remove nodes based on demand
- **Database Clustering**: PostgreSQL high availability
- **Elasticsearch Clustering**: Multi-node ES cluster

### Monitoring
- **Prometheus + Grafana**: Comprehensive monitoring stack
- **Alerting**: Critical error notifications
- **Log Aggregation**: Centralized log management

### CI/CD Integration
- **GitOps**: Automated deployments with ArgoCD/Flux
- **Image Registry**: Private container registry
- **Security Scanning**: Container and dependency scanning

This Kubernetes deployment provides a production-ready, scalable, and secure environment for the Advanced Threat Detection System.