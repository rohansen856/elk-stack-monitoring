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

print_status "🧹 Cleaning up Kubernetes deployment..."

# Delete the application
print_status "Removing application components..."
kubectl delete -k k8s/base/ --ignore-not-found=true

# Wait a moment for resources to be deleted
sleep 5

# Force delete any remaining pods
print_status "Force deleting any remaining pods..."
kubectl delete pods --all -n threat-detection --force --grace-period=0 --ignore-not-found=true

# Delete the namespace (this will delete everything in it)
print_status "Deleting namespace..."
kubectl delete namespace threat-detection --ignore-not-found=true

# Clean up persistent volumes
print_status "Cleaning up persistent volumes..."
kubectl delete pv postgres-pv redis-pv elasticsearch-pv --ignore-not-found=true

# Remove NGINX Ingress Controller (optional)
read -p "Do you want to remove the NGINX Ingress Controller? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Removing NGINX Ingress Controller..."
    kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml --ignore-not-found=true
fi

# Check cluster type and offer to delete cluster
if command -v kind >/dev/null 2>&1 && kind get clusters | grep -q "kind"; then
    echo
    read -p "Do you want to delete the Kind cluster? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deleting Kind cluster..."
        kind delete cluster
        print_success "Kind cluster deleted"
    fi
elif command -v minikube >/dev/null 2>&1; then
    echo
    read -p "Do you want to stop Minikube? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Stopping Minikube..."
        minikube stop
        print_success "Minikube stopped"

        echo
        read -p "Do you want to delete Minikube cluster? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deleting Minikube cluster..."
            minikube delete
            print_success "Minikube cluster deleted"
        fi
    fi
fi

print_success "🎉 Cleanup completed!"