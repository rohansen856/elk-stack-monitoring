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

print_status "🚀 Starting Kubernetes deployment (offline/cached mode)"

# Check Docker
if ! docker version >/dev/null 2>&1; then
    print_error "Docker is not running"
    exit 1
fi

# Check Kind cluster
if command -v kind >/dev/null 2>&1; then
    if kind get clusters | grep -q "threat-detection"; then
        print_success "Kind cluster 'threat-detection' exists"
        kubectl config use-context kind-threat-detection >/dev/null 2>&1
        CLUSTER_TYPE="kind"
    else
        print_error "Kind cluster 'threat-detection' not found"
        print_status "Please run: kind create cluster --name threat-detection"
        exit 1
    fi
else
    print_error "Kind not found. Please install Kind first."
    exit 1
fi

# Use existing Docker images from docker-compose
print_status "📦 Using existing Docker images..."

# Check if we can use images from docker-compose
if docker-compose ps | grep -q "ps25238"; then
    print_status "Found existing docker-compose containers"

    # Get image names from running containers
    BACKEND_IMAGE=$(docker-compose images app | tail -1 | awk '{print $2":"$3}' | sed 's/ps25238-//g')
    FRONTEND_IMAGE=$(docker-compose images frontend | tail -1 | awk '{print $2":"$3}' | sed 's/ps25238-//g')

    if [[ "$BACKEND_IMAGE" != ":" ]]; then
        print_status "Tagging backend image: $BACKEND_IMAGE -> ps25238-app:latest"
        docker tag $BACKEND_IMAGE ps25238-app:latest
    fi

    if [[ "$FRONTEND_IMAGE" != ":" ]]; then
        print_status "Tagging frontend image: $FRONTEND_IMAGE -> ps25238-frontend:latest"
        docker tag $FRONTEND_IMAGE ps25238-frontend:latest
    fi
else
    # Check if images already exist locally
    if ! docker images ps25238-app:latest --format "table {{.Repository}}" | grep -q "ps25238-app"; then
        print_warning "Backend image not found locally"
        print_status "Attempting to build from existing base images..."

        # Try to build with --pull=false to use cached images
        docker build -t ps25238-app:latest --pull=false . || {
            print_error "Failed to build backend image"
            print_error "Please ensure base images are available or network connectivity is working"
            exit 1
        }
    fi

    if ! docker images ps25238-frontend:latest --format "table {{.Repository}}" | grep -q "ps25238-frontend"; then
        print_warning "Frontend image not found locally"
        print_status "Attempting to build from existing base images..."

        docker build -t ps25238-frontend:latest --pull=false ./website || {
            print_error "Failed to build frontend image"
            print_error "Please ensure base images are available or network connectivity is working"
            exit 1
        }
    fi
fi

print_success "Docker images ready"

# Load images into Kind
print_status "Loading images into Kind cluster..."
kind load docker-image ps25238-app:latest --name threat-detection
kind load docker-image ps25238-frontend:latest --name threat-detection

print_success "Images loaded into Kind cluster"

# Clean up existing deployment
print_status "🧹 Cleaning up any existing deployment..."
kubectl delete -k k8s/base/ --ignore-not-found=true --timeout=30s || true
sleep 3

# Deploy application
print_status "🔧 Deploying application components..."
kubectl apply -k k8s/base/

print_status "⏳ Waiting for deployments to be ready..."

# Wait for namespace
kubectl wait --for=condition=Ready namespace/threat-detection --timeout=30s || true

# Wait for core services with shorter timeouts
print_status "Waiting for PostgreSQL..."
kubectl wait --for=condition=available --timeout=120s deployment/postgres -n threat-detection || {
    print_warning "PostgreSQL deployment timeout"
}

print_status "Waiting for Redis..."
kubectl wait --for=condition=available --timeout=60s deployment/redis -n threat-detection || {
    print_warning "Redis deployment timeout"
}

print_status "Waiting for Elasticsearch..."
kubectl wait --for=condition=available --timeout=180s deployment/elasticsearch -n threat-detection || {
    print_warning "Elasticsearch deployment timeout"
}

# Run migration job
print_status "🗄️ Running database migrations..."
kubectl wait --for=condition=complete --timeout=120s job/migrate-job -n threat-detection || {
    print_warning "Migration job timeout - checking manually..."
    kubectl get jobs -n threat-detection
}

# Wait for application services
print_status "Waiting for backend..."
kubectl wait --for=condition=available --timeout=120s deployment/backend -n threat-detection || {
    print_warning "Backend deployment timeout"
}

print_status "Waiting for frontend..."
kubectl wait --for=condition=available --timeout=120s deployment/frontend -n threat-detection || {
    print_warning "Frontend deployment timeout"
}

# Get status
print_success "🎉 Deployment process completed!"
echo
echo "====================================="
echo "🌐 Access URLs (use port-forwarding):"
echo "====================================="
echo "Frontend:  kubectl port-forward -n threat-detection svc/frontend 3000:3000"
echo "Backend:   kubectl port-forward -n threat-detection svc/backend 8000:8000"
echo "Kibana:    kubectl port-forward -n threat-detection svc/kibana 5601:5601"
echo "====================================="
echo
echo "📊 Check status:"
echo "kubectl get pods -n threat-detection"
echo
echo "🔍 View logs:"
echo "kubectl logs -f deployment/backend -n threat-detection"
echo "kubectl logs -f deployment/frontend -n threat-detection"
echo
echo "🧹 Cleanup:"
echo "./scripts/k8s-cleanup.sh"

print_status "Run './scripts/k8s-monitor.sh' for detailed status monitoring"