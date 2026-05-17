#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${DOMAIN:-$(yq -r '.domain' "$SCRIPT_DIR/../../cluster-config.yaml")}"
ENV_TAG="${ENV_TAG:-dev-52}"
NAMESPACE="${YAS_NAMESPACE:-yas-52}"
MINIKUBE_IP="${MINIKUBE_IP:-$(minikube ip)}"
COUNT="${COUNT:-30}"
SLEEP_SECONDS="${SLEEP_SECONDS:-1}"

if [ -n "$ENV_TAG" ]; then
  STOREFRONT_HOST="storefront-$ENV_TAG.$DOMAIN"
  API_HOST="api-$ENV_TAG.$DOMAIN"
  IDENTITY_HOST="identity-$ENV_TAG.$DOMAIN"
else
  STOREFRONT_HOST="storefront.$DOMAIN"
  API_HOST="api.$DOMAIN"
  IDENTITY_HOST="identity.$DOMAIN"
fi

curl_https() {
  local host=$1
  local path=$2

  curl -ksS \
    --resolve "$host:443:$MINIKUBE_IP" \
    --max-time 15 \
    -o /dev/null \
    -w "%{http_code} %{url_effective}\n" \
    "https://$host$path" || true
}

curl_http() {
  local host=$1
  local path=$2

  curl -sS \
    --resolve "$host:80:$MINIKUBE_IP" \
    --max-time 15 \
    -o /dev/null \
    -w "%{http_code} %{url_effective}\n" \
    "http://$host$path" || true
}

echo ">>> Generating Kiali traffic"
echo ">>> namespace=$NAMESPACE envTag=${ENV_TAG:-none} minikubeIp=$MINIKUBE_IP count=$COUNT"
echo ">>> storefront=$STOREFRONT_HOST api=$API_HOST identity=$IDENTITY_HOST"

for i in $(seq 1 "$COUNT"); do
  echo ">>> Round $i/$COUNT"

  curl_https "$STOREFRONT_HOST" "/"
  curl_https "$STOREFRONT_HOST" "/authentication"
  curl_https "$STOREFRONT_HOST" "/api/product/storefront/categories"
  curl_https "$STOREFRONT_HOST" "/api/product/storefront/categories/suggestions"
  curl_https "$STOREFRONT_HOST" "/api/product/storefront/products/featured?pageNo=0"
  curl_https "$STOREFRONT_HOST" "/api/search/storefront/search?keyword=macbook&size=5"
  curl_https "$STOREFRONT_HOST" "/api/cart/storefront/cart/items"
  curl_https "$STOREFRONT_HOST" "/api/customer/storefront/customer/profile"
  curl_https "$STOREFRONT_HOST" "/products/macbook-air-m3"

  curl_https "$API_HOST" "/media/medias/3/file/Samsung_category.jpg"
  curl_https "$API_HOST" "/swagger-ui"

  curl_http "$IDENTITY_HOST" "/realms/Yas/.well-known/openid-configuration"

  sleep "$SLEEP_SECONDS"
done

echo ">>> Done. In Kiali, select namespace '$NAMESPACE', Graph=Workload graph or Service graph, Last 15m, then refresh."
