#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "Installing Prometheus Stack (Prometheus, Grafana, Alertmanager)..."

# Add Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Substitute passwords in prometheus-values.yaml
cat prometheus-values.yaml | \
  sed "s/GRAFANA_ADMIN_PASSWORD_PLACEHOLDER/${GRAFANA_ADMIN_PASSWORD}/g" \
  > /tmp/prometheus-values.yaml

# Install kube-prometheus-stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f /tmp/prometheus-values.yaml \
  --wait

rm /tmp/prometheus-values.yaml

echo "Installing Loki..."
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  -f loki-values.yaml \
  --wait

echo "Installing Promtail..."
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  -f promtail-values.yaml \
  --wait

echo "Creating certificates..."
kubectl apply -f certificate.yaml

echo "Creating IngressRoutes..."
kubectl apply -f ingressroutes.yaml

echo "Monitoring stack installed!"
echo ""
echo "Access URLs:"
echo "  Grafana:      https://grafana.apps.house.simonellistonball.com"
echo "  Prometheus:   https://prometheus.apps.house.simonellistonball.com"
echo "  Alertmanager: https://alertmanager.apps.house.simonellistonball.com"
echo ""
echo "Grafana credentials: admin / (from config.env GRAFANA_ADMIN_PASSWORD)"
