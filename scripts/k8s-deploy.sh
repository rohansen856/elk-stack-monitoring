#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    print_error "docker-compose.yml not found. Please run this script from the project root."
    exit 1
fi

print_status "🚀 Starting Kubernetes deployment for Advanced Threat Detection System"

# Check Docker connectivity
print_status "🔍 Checking Docker connectivity..."
if ! docker version >/dev/null 2>&1; then
    print_error "Docker is not running or not accessible"
    exit 1
fi

# Check network connectivity (optional, for troubleshooting)
if ! curl -s --connect-timeout 5 registry-1.docker.io >/dev/null 2>&1; then
    print_warning "Docker registry connectivity may be limited"
    print_warning "If image builds fail, try: docker pull python:3.11-slim && docker pull node:18-alpine"
fi

# Check if Kind or Minikube is running
if command -v kind >/dev/null 2>&1; then
    print_status "Checking Kind cluster status..."
    if kind get clusters | grep -q "threat-detection"; then
        print_success "Kind cluster 'threat-detection' already exists"
        CLUSTER_TYPE="kind"
        # Set kubectl context to the existing cluster
        kubectl config use-context kind-threat-detection >/dev/null 2>&1 || {
            print_error "Kind cluster exists but kubectl context is not accessible"
            print_status "Deleting and recreating Kind cluster..."
            kind delete cluster --name threat-detection
            kind create cluster --config scripts/kind-config.yaml --name threat-detection || {
                print_error "Failed to create Kind cluster"
                exit 1
            }
        }
        print_status "Using existing Kind cluster 'threat-detection'"
    else
        print_status "Starting Kind cluster..."
        kind create cluster --config scripts/kind-config.yaml --name threat-detection || {
            print_error "Failed to create Kind cluster"
            exit 1
        }
        CLUSTER_TYPE="kind"
    fi
elif command -v minikube >/dev/null 2>&1; then
    print_status "Checking Minikube status..."
    if minikube status | grep -q "Running"; then
        print_success "Minikube is running"
        CLUSTER_TYPE="minikube"
    else
        print_status "Starting Minikube..."
        minikube start --cpus=4 --memory=8192 --disk-size=50g || {
            print_error "Failed to start Minikube"
            exit 1
        }
        CLUSTER_TYPE="minikube"
    fi
else
    print_error "Neither Kind nor Minikube found. Please install one of them."
    exit 1
fi

# Build Docker images
print_status "📦 Building Docker images..."

# Check if images already exist
if docker images ps25238-app:latest --format "table {{.Repository}}" | grep -q "ps25238-app"; then
    print_status "Backend image already exists, skipping build..."
else
    print_status "Building backend image..."
    docker build -t ps25238-app:latest . || {
        print_error "Failed to build backend image"
        print_warning "This might be due to network connectivity issues."
        print_warning "Try running 'docker pull python:3.11-slim' first, then retry."
        exit 1
    }
fi

if docker images ps25238-frontend:latest --format "table {{.Repository}}" | grep -q "ps25238-frontend"; then
    print_status "Frontend image already exists, skipping build..."
else
    print_status "Building frontend image..."
    docker build -t ps25238-frontend:latest ./website || {
        print_error "Failed to build frontend image"
        print_warning "This might be due to network connectivity issues."
        print_warning "Try running 'docker pull node:18-alpine' first, then retry."
        exit 1
    }
fi

# Load images into cluster
if [[ "$CLUSTER_TYPE" == "kind" ]]; then
    print_status "Loading images into Kind cluster..."
    kind load docker-image ps25238-app:latest --name threat-detection
    kind load docker-image ps25238-frontend:latest --name threat-detection
elif [[ "$CLUSTER_TYPE" == "minikube" ]]; then
    print_status "Loading images into Minikube..."
    minikube image load ps25238-app:latest
    minikube image load ps25238-frontend:latest
fi

# Install NGINX Ingress Controller
print_status "🌐 Installing NGINX Ingress Controller..."
if [[ "$CLUSTER_TYPE" == "kind" ]]; then
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
elif [[ "$CLUSTER_TYPE" == "minikube" ]]; then
    minikube addons enable ingress
fi

print_status "Waiting for ingress controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || {
  print_warning "Ingress controller timeout - continuing with deployment"
  print_warning "This is likely due to network connectivity issues"
}

# Clean up any existing deployment
print_status "🧹 Cleaning up any existing deployment..."
kubectl delete -k k8s/base/ --ignore-not-found=true --timeout=60s
sleep 5

# Deploy the application
print_status "🔧 Deploying application components..."

# Apply all manifests using Kustomize
kubectl apply -k k8s/base/

print_status "⏳ Waiting for deployments to be ready..."

# Wait for namespace
kubectl wait --for=condition=Ready namespace/threat-detection --timeout=60s

# Wait for database
print_status "Waiting for PostgreSQL..."
kubectl wait --for=condition=available --timeout=300s deployment/postgres -n threat-detection

# Wait for Redis
print_status "Waiting for Redis..."
kubectl wait --for=condition=available --timeout=300s deployment/redis -n threat-detection

# Wait for Elasticsearch
print_status "Waiting for Elasticsearch..."
kubectl wait --for=condition=available --timeout=600s deployment/elasticsearch -n threat-detection

# Run database migration
print_status "🗄️ Running database migrations..."
kubectl wait --for=condition=complete --timeout=300s job/migrate-job -n threat-detection

# Wait for backend
print_status "Waiting for backend..."
kubectl wait --for=condition=available --timeout=300s deployment/backend -n threat-detection

# Wait for frontend
print_status "Waiting for frontend..."
kubectl wait --for=condition=available --timeout=300s deployment/frontend -n threat-detection

# Wait for ELK components
print_status "Waiting for Logstash..."
kubectl wait --for=condition=available --timeout=300s deployment/logstash -n threat-detection

print_status "Waiting for Kibana..."
kubectl wait --for=condition=available --timeout=300s deployment/kibana -n threat-detection

# Get service information
print_status "📋 Getting service information..."

if [[ "$CLUSTER_TYPE" == "minikube" ]]; then
    FRONTEND_URL=$(minikube service frontend-loadbalancer -n threat-detection --url 2>/dev/null || echo "http://localhost:80")
    BACKEND_URL=$(minikube service backend-loadbalancer -n threat-detection --url 2>/dev/null || echo "http://localhost:8000")
    KIBANA_URL=$(minikube service kibana-loadbalancer -n threat-detection --url 2>/dev/null || echo "http://localhost:5601")
else
    # For Kind, we'll use port-forwarding
    FRONTEND_URL="http://localhost:3000"
    BACKEND_URL="http://localhost:8000"
    KIBANA_URL="http://localhost:5601"
fi

print_success "🎉 Deployment completed successfully!"
echo
echo "====================================="
echo "🌐 Access URLs:"
echo "====================================="
echo "Frontend (Next.js):     $FRONTEND_URL"
echo "Backend API (FastAPI):  $BACKEND_URL/docs"
echo "Kibana Dashboard:       $KIBANA_URL"
echo "API Health Check:       $BACKEND_URL/health"
echo "Prometheus Metrics:     $BACKEND_URL/metrics"
echo "====================================="

if [[ "$CLUSTER_TYPE" == "kind" ]]; then
    echo
    print_warning "📝 Note for Kind users:"
    echo "To access services, run the following port-forward commands in separate terminals:"
    echo "kubectl port-forward -n threat-detection svc/frontend 3000:3000"
    echo "kubectl port-forward -n threat-detection svc/backend 8000:8000"
    echo "kubectl port-forward -n threat-detection svc/kibana 5601:5601"
fi

echo
echo "📊 To view pods status:"
echo "kubectl get pods -n threat-detection"
echo
echo "🔍 To view logs:"
echo "kubectl logs -f deployment/backend -n threat-detection"
echo "kubectl logs -f deployment/frontend -n threat-detection"
echo
echo "🧹 To clean up:"
echo "./scripts/k8s-cleanup.sh"

print_success "Advanced Threat Detection System is now running on Kubernetes! 🚀"