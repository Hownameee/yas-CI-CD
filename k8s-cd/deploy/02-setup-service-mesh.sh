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

echo ">>> Injecting Istio sidecar into 'ingress-nginx' namespace (to support STRICT mTLS entry)..."
kubectl label namespace ingress-nginx istio-injection=enabled --overwrite
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx

echo ">>> Applying Istio configurations (mTLS, Destination Rules, Auth Policies) via Loop..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read configuration value from cluster-config.yaml file to construct hosts
DOMAIN=$(yq -r '.domain' "$SCRIPT_DIR/cluster-config.yaml")
NAMESPACE="${YAS_NAMESPACE:-yas}"
if [ -n "${ENV_TAG:-}" ]; then
  IDENTITY_HOST="identity-$ENV_TAG.$DOMAIN"
else
  IDENTITY_HOST="identity.$DOMAIN"
fi

export NAMESPACE DOMAIN IDENTITY_HOST

ISTIO_CONFIGS=("ingress-mtls.yaml" "mtls.yaml" "destination-rule.yaml" "keycloak-internal-dns.yaml" "telemetry-monitor.yaml" "virtual-service-retry-template.yaml" "auth-policy.yaml")

for config in "${ISTIO_CONFIGS[@]}"; do
    if [ -s "$SCRIPT_DIR/istio/$config" ]; then
        echo ">>> Applying $config..."
        envsubst < "$SCRIPT_DIR/istio/$config" | kubectl apply -f -
    else
        echo ">>> Skipping $config (empty or not found)."
    fi
done

echo ">>> Xong Giai đoạn 2: Cài đặt Service Mesh (Istio), Kiali và áp dụng Policies."
sleep 50
