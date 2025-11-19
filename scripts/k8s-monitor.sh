#!/bin/bash

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

# Function to check deployment status
check_deployment() {
    local deployment=$1
    local namespace=$2
    local status=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

    if [[ "$status" == "$desired" && "$status" != "0" ]]; then
        print_success "✅ $deployment: $status/$desired ready"
    elif [[ "$status" == "0" ]]; then
        print_error "❌ $deployment: Not running"
    else
        print_warning "⚠️  $deployment: $status/$desired ready"
    fi
}

# Function to check service status
check_service() {
    local service=$1
    local namespace=$2
    local port=$3

    if kubectl get service $service -n $namespace >/dev/null 2>&1; then
        print_success "✅ Service $service is available"
    else
        print_error "❌ Service $service is not found"
    fi
}

print_status "🔍 Monitoring Advanced Threat Detection System on Kubernetes"
echo "=================================================="

# Check namespace
if kubectl get namespace threat-detection >/dev/null 2>&1; then
    print_success "✅ Namespace 'threat-detection' exists"
else
    print_error "❌ Namespace 'threat-detection' not found"
    exit 1
fi

echo
print_status "📊 Deployment Status:"
check_deployment "postgres" "threat-detection"
check_deployment "redis" "threat-detection"
check_deployment "elasticsearch" "threat-detection"
check_deployment "logstash" "threat-detection"
check_deployment "kibana" "threat-detection"
check_deployment "backend" "threat-detection"
check_deployment "frontend" "threat-detection"

echo
print_status "🌐 Service Status:"
check_service "postgres" "threat-detection"
check_service "redis" "threat-detection"
check_service "elasticsearch" "threat-detection"
check_service "logstash" "threat-detection"
check_service "kibana" "threat-detection"
check_service "backend" "threat-detection"
check_service "frontend" "threat-detection"

echo
print_status "💾 Storage Status:"
kubectl get pvc -n threat-detection 2>/dev/null || print_warning "No PVCs found"

echo
print_status "🏃 Running Pods:"
kubectl get pods -n threat-detection --field-selector=status.phase=Running 2>/dev/null | grep -v "NAME" | wc -l | xargs echo "Running pods:"

echo
print_status "❌ Failed Pods:"
kubectl get pods -n threat-detection --field-selector=status.phase=Failed 2>/dev/null | grep -v "NAME"

echo
print_status "🔄 Pending Pods:"
kubectl get pods -n threat-detection --field-selector=status.phase=Pending 2>/dev/null | grep -v "NAME"

echo
print_status "📈 Resource Usage:"
kubectl top nodes 2>/dev/null || print_warning "Metrics server not available"
echo
kubectl top pods -n threat-detection 2>/dev/null || print_warning "Pod metrics not available"

echo
print_status "🔗 Access Information:"

# Check cluster type and provide appropriate access info
if command -v kind >/dev/null 2>&1 && kind get clusters | grep -q "kind"; then
    echo "Cluster Type: Kind"
    echo "To access services, use port-forwarding:"
    echo "  Frontend:  kubectl port-forward -n threat-detection svc/frontend 3000:3000"
    echo "  Backend:   kubectl port-forward -n threat-detection svc/backend 8000:8000"
    echo "  Kibana:    kubectl port-forward -n threat-detection svc/kibana 5601:5601"
elif command -v minikube >/dev/null 2>&1; then
    echo "Cluster Type: Minikube"
    echo "Service URLs:"
    echo "  Frontend:  $(minikube service frontend-loadbalancer -n threat-detection --url 2>/dev/null || echo 'Not available')"
    echo "  Backend:   $(minikube service backend-loadbalancer -n threat-detection --url 2>/dev/null || echo 'Not available')"
    echo "  Kibana:    $(minikube service kibana-loadbalancer -n threat-detection --url 2>/dev/null || echo 'Not available')"
fi

echo
print_status "🔧 Useful Commands:"
echo "  View all resources:     kubectl get all -n threat-detection"
echo "  View pod logs:          kubectl logs -f deployment/backend -n threat-detection"
echo "  Describe pod:           kubectl describe pod <pod-name> -n threat-detection"
echo "  Get events:             kubectl get events -n threat-detection --sort-by='.lastTimestamp'"
echo "  Shell into pod:         kubectl exec -it deployment/backend -n threat-detection -- /bin/bash"

echo
echo "=================================================="
print_status "Monitor completed. Run this script again to refresh status."