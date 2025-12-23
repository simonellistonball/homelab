#!/bin/bash
set -e

# Homelab K8s Deployment Script
# Deploys all services in order

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! command -v helm &> /dev/null; then
        log_error "helm not found. Please install helm."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    log_success "Prerequisites checked!"
}

# Load configuration
load_config() {
    if [ -f "${SCRIPT_DIR}/config.env" ]; then
        source "${SCRIPT_DIR}/config.env"
        log_info "Configuration loaded from config.env"
    else
        log_warning "config.env not found. Using default values."
    fi
}

# Deploy a component
deploy_component() {
    local component_dir="$1"
    local component_name="$(basename ${component_dir})"

    if [ -f "${component_dir}/deploy.sh" ]; then
        log_info "=========================================="
        log_info "Deploying: ${component_name}"
        log_info "=========================================="

        cd "${component_dir}"
        chmod +x deploy.sh
        ./deploy.sh
        cd "${SCRIPT_DIR}"

        log_success "${component_name} deployed!"
        echo ""
    else
        log_warning "No deploy.sh found for ${component_name}, skipping..."
    fi
}

# Main deployment
main() {
    echo ""
    echo "=============================================="
    echo "  Homelab K8s Deployment"
    echo "=============================================="
    echo ""

    check_prerequisites
    load_config

    # Ask for confirmation
    read -p "This will deploy all services to your K8s cluster. Continue? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled."
        exit 0
    fi

    echo ""
    log_info "Starting deployment..."
    echo ""

    # Deploy in order
    deploy_component "${SCRIPT_DIR}/00-namespaces"
    deploy_component "${SCRIPT_DIR}/01-metallb"
    deploy_component "${SCRIPT_DIR}/02-traefik"
    deploy_component "${SCRIPT_DIR}/03-cert-manager"
    deploy_component "${SCRIPT_DIR}/04-storage"
    deploy_component "${SCRIPT_DIR}/05-redis"
    deploy_component "${SCRIPT_DIR}/06-monitoring"
    deploy_component "${SCRIPT_DIR}/07-harbor"
    deploy_component "${SCRIPT_DIR}/08-gitea"
    deploy_component "${SCRIPT_DIR}/09-dagster"
    deploy_component "${SCRIPT_DIR}/10-redpanda"
    deploy_component "${SCRIPT_DIR}/11-n8n"
    deploy_component "${SCRIPT_DIR}/12-ai"

    echo ""
    log_success "=============================================="
    log_success "  Deployment Complete!"
    log_success "=============================================="
    echo ""
    echo "Service URLs:"
    echo "  Traefik Dashboard: https://traefik.apps.house.simonellistonball.com/dashboard/"
    echo "  Grafana:           https://grafana.apps.house.simonellistonball.com"
    echo "  Prometheus:        https://prometheus.apps.house.simonellistonball.com"
    echo "  Harbor:            https://harbor.apps.house.simonellistonball.com"
    echo "  Gitea:             https://gitea.apps.house.simonellistonball.com"
    echo "  Dagster:           https://dagster.apps.house.simonellistonball.com"
    echo "  Redpanda Console:  https://redpanda.apps.house.simonellistonball.com"
    echo "  n8n:               https://n8n.apps.house.simonellistonball.com"
    echo "  LiteLLM:           https://llm.apps.house.simonellistonball.com"
    echo "  Whisper:           https://whisper.apps.house.simonellistonball.com"
    echo ""
    echo "Note: Ensure your DNS points *.apps.house.simonellistonball.com to ${TRAEFIK_IP:-192.168.100.111}"
    echo ""
}

# Allow running individual components
if [ "$1" != "" ]; then
    load_config
    if [ -d "${SCRIPT_DIR}/$1" ]; then
        deploy_component "${SCRIPT_DIR}/$1"
    else
        log_error "Component not found: $1"
        echo "Available components:"
        ls -d */ | grep -E '^[0-9]' | sed 's/\///'
        exit 1
    fi
else
    main
fi
