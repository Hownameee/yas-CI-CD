#!/bin/bash
set -euo pipefail
set -x

# NAMESPACE is no longer needed here since ArgoCD manages it.

echo ">>> Adding Istio Helm repository..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

echo ">>> Installing Istio Base..."
helm upgrade --install istio-base istio/base -n istio-system --create-namespace --wait

echo ">>> Installing Istiod..."
helm upgrade --install istiod istio/istiod -n istio-system --wait

if [ "${DISABLE_OBSERVABILITY:-false}" != "true" ]; then
echo ">>> Installing Kiali Server for Topology visualization..."
helm repo add kiali https://kiali.org/helm-charts
helm repo update
# Installing latest stable Kiali
helm upgrade --install kiali-server kiali/kiali-server \
  --namespace istio-system \
  --set auth.strategy="anonymous" \
  --set external_services.prometheus.url="http://prometheus-kube-prometheus-prometheus.observability.svc.cluster.local:9090" \
  --wait
fi

echo ">>> Injecting Istio sidecar into 'ingress-nginx' namespace (to support STRICT mTLS entry)..."
kubectl label namespace ingress-nginx istio-injection=enabled --overwrite
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

echo ">>> Xong Giai đoạn 2: Cài đặt Service Mesh Operator (Istio, Kiali)."
sleep 5
