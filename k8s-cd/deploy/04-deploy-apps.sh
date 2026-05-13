#!/bin/bash
set -x

helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

read -rd '' DOMAIN \
< <(yq -r '.domain' ./cluster-config.yaml)

NAMESPACE="${YAS_NAMESPACE:-yas}"

# Construct dynamic domains
if [ -n "$ENV_TAG" ]; then
  IDENTITY_HOST="identity-$ENV_TAG.$DOMAIN"
  BACKOFFICE_HOST="backoffice-$ENV_TAG.$DOMAIN"
  STOREFRONT_HOST="storefront-$ENV_TAG.$DOMAIN"
  API_HOST="api-$ENV_TAG.$DOMAIN"
else
  IDENTITY_HOST="identity.$DOMAIN"
  BACKOFFICE_HOST="backoffice.$DOMAIN"
  STOREFRONT_HOST="storefront.$DOMAIN"
  API_HOST="api.$DOMAIN"
fi

# Function to populate media images
populate_media_images() {
  local namespace=$1
  echo ">>> Populating sample images for media service in namespace $namespace..."
  
  # Wait for media pod to be ready
  kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=media -n "$namespace" --timeout=300s
  
  local media_pod=$(kubectl get pod -l app.kubernetes.io/name=media -n "$namespace" -o jsonpath='{.items[0].metadata.name}')
  
  if [ -n "$media_pod" ]; then
    echo ">>> Copying images to pod $media_pod..."
    # The script is in k8s-cd/deploy, images are at ../../sampledata/images/sample
    kubectl cp ../../sampledata/images/sample -n "$namespace" "$media_pod":/images/
    echo ">>> Sample images populated successfully."
  else
    echo ">>> ERROR: Media pod not found. Skipping image population."
  fi
}

# Create namespace yas if not exists
kubectl create namespace "$NAMESPACE" || true

echo ">>> Deploying YAS Configuration (including Reloader)..."
helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
--namespace "$NAMESPACE" \
--set global.domain="$DOMAIN" \
--set global.envTag="$ENV_TAG"

sleep 35

echo ">>> Deploying Backoffice..."
helm dependency build ../charts/backoffice-bff
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
--namespace "$NAMESPACE" \
--set backend.ingress.host="$BACKOFFICE_HOST" \
--set global.domain="$DOMAIN" \
--set global.envTag="$ENV_TAG"

helm dependency build ../charts/backoffice-ui
helm upgrade --install backoffice-ui ../charts/backoffice-ui \
--namespace "$NAMESPACE" \
--set ingress.host="$BACKOFFICE_HOST" \
--set ui.extraEnvs[0].name=API_BASE_PATH \
--set ui.extraEnvs[0].value="http://$BACKOFFICE_HOST/api"

sleep 35

echo ">>> Deploying Storefront..."
helm dependency build ../charts/storefront-bff
helm upgrade --install storefront-bff ../charts/storefront-bff \
--namespace "$NAMESPACE" \
--set backend.ingress.host="$STOREFRONT_HOST" \
--set global.domain="$DOMAIN" \
--set global.envTag="$ENV_TAG"

helm dependency build ../charts/storefront-ui
helm upgrade --install storefront-ui ../charts/storefront-ui \
--namespace "$NAMESPACE" \
--set ingress.host="$STOREFRONT_HOST" \
--set ui.extraEnvs[0].name=API_BASE_PATH \
--set ui.extraEnvs[0].value="http://$STOREFRONT_HOST/api"

sleep 35

echo ">>> Deploying Swagger UI..."
helm upgrade --install swagger-ui ../charts/swagger-ui \
--namespace "$NAMESPACE" \
--set ingress.host="$API_HOST"

sleep 35

echo ">>> Deploying Core Microservices..."
for chart in {"cart","customer","inventory","location","media","order","payment","product","promotion","rating","search","tax","recommendation","webhook","sampledata"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "$chart" ../charts/"$chart" \
    --namespace "$NAMESPACE" \
    --set backend.ingress.host="$API_HOST" \
    --set backend.ingress.enabled=true \
    --set backend.ingress.path="/$chart" \
    --set global.domain="$DOMAIN" \
    --set global.envTag="$ENV_TAG"
    sleep 35
done

# Populate media images after all services are deployed
populate_media_images "$NAMESPACE"

echo ">>> Xong Giai đoạn 4: Tất cả Microservices và UI đã được cài vào namespace '$NAMESPACE' với domain prefix '$ENV_TAG'."
