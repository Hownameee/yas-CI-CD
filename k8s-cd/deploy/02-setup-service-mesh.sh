#!/bin/bash
set -euo pipefail
set -x

NAMESPACE="${YAS_NAMESPACE:-yas}"

echo ">>> Creating namespace $NAMESPACE (if not exists)..."
kubectl create namespace "$NAMESPACE" || true

echo ">>> Adding Istio Helm repository..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

echo ">>> Installing Istio Base..."
helm upgrade --install istio-base istio/base -n istio-system --create-namespace --wait

echo ">>> Installing Istiod..."
helm upgrade --install istiod istio/istiod -n istio-system --wait

echo ">>> Installing Kiali Server for Topology visualization..."
helm repo add kiali https://kiali.org/helm-charts
helm repo update
# Installing latest stable Kiali
helm upgrade --install kiali-server kiali/kiali-server \
  --namespace istio-system \
  --set auth.strategy="anonymous" \
  --set external_services.prometheus.url="http://prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090" \
  --wait

echo ">>> Enabling automatic sidecar injection for namespace '$NAMESPACE'..."
kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite

echo ">>> Xong Giai đoạn 2: Cài đặt Service Mesh (Istio) và Kiali. Namespace '$NAMESPACE' đã được kích hoạt sidecar injection."
sleep 50
