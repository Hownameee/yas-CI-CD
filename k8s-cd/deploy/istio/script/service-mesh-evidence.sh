#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${YAS_NAMESPACE:-yas-52}"
POD_TTL_SECONDS="${POD_TTL_SECONDS:-300}"
REPORT_DIR="${REPORT_DIR:-$SCRIPT_DIR/../../evidence}"
PRODUCT_OK_URL="${PRODUCT_OK_URL:-http://product/product/storefront/products}"
PRODUCT_500_URL="${PRODUCT_500_URL:-http://product/product/actuator/health}"

mkdir -p "$REPORT_DIR"

AUTH_ALLOWED_POD="auth-allowed-storefront-bff"
AUTH_BLOCKED_POD="auth-blocked-default"
RETRY_POD="retry-test"

create_curl_pod() {
  local pod_name=$1
  local service_account=$2

  kubectl delete pod "$pod_name" -n "$NAMESPACE" --ignore-not-found=true >/dev/null
  kubectl run "$pod_name" -n "$NAMESPACE" \
    --image=curlimages/curl:8.7.1 \
    --restart=Never \
    --overrides="{\"spec\":{\"serviceAccountName\":\"$service_account\",\"terminationGracePeriodSeconds\":0,\"containers\":[{\"name\":\"curl\",\"image\":\"curlimages/curl:8.7.1\",\"command\":[\"sleep\",\"$POD_TTL_SECONDS\"]}]}}"
  kubectl wait --for=condition=Ready "pod/$pod_name" -n "$NAMESPACE" --timeout=120s
}

curl_from_pod() {
  local pod_name=$1
  local url=$2

  kubectl exec -n "$NAMESPACE" "$pod_name" -c curl -- curl -i -sS "$url" || true
}

echo ">>> Creating temporary mesh curl pods in namespace '$NAMESPACE' for $POD_TTL_SECONDS seconds..."
create_curl_pod "$AUTH_ALLOWED_POD" "storefront-bff"
create_curl_pod "$AUTH_BLOCKED_POD" "default"
create_curl_pod "$RETRY_POD" "storefront-bff"

echo ">>> Generating AuthorizationPolicy traffic..."
for i in $(seq 1 20); do
  kubectl exec -n "$NAMESPACE" "$AUTH_ALLOWED_POD" -c curl -- curl -sS -o /dev/null "$PRODUCT_OK_URL" || true
  kubectl exec -n "$NAMESPACE" "$AUTH_BLOCKED_POD" -c curl -- curl -sS -o /dev/null "$PRODUCT_OK_URL" || true
done

echo ">>> Generating retry traffic..."
for i in $(seq 1 20); do
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- curl -sS -o /dev/null "$PRODUCT_500_URL" || true
done

AUTH_REPORT="$REPORT_DIR/auth-policy-test-3.txt"
RETRY_REPORT="$REPORT_DIR/retry-test-evidence.txt"

{
  echo "AuthorizationPolicy Test 3 Evidence"
  date
  echo
  echo "Temporary pods:"
  kubectl get pods -n "$NAMESPACE" "$AUTH_ALLOWED_POD" "$AUTH_BLOCKED_POD" "$RETRY_POD" \
    -o custom-columns=NAME:.metadata.name,SERVICE_ACCOUNT:.spec.serviceAccountName,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,CONTAINERS:.spec.containers[*].name
  echo
  echo "Product AuthorizationPolicy:"
  kubectl get authorizationpolicy allow-product-callers -n "$NAMESPACE" -o yaml
  echo
  echo "[ALLOWED] $AUTH_ALLOWED_POD serviceAccount=storefront-bff -> product"
  curl_from_pod "$AUTH_ALLOWED_POD" "$PRODUCT_OK_URL"
  echo
  echo "[BLOCKED] $AUTH_BLOCKED_POD serviceAccount=default -> product"
  curl_from_pod "$AUTH_BLOCKED_POD" "$PRODUCT_OK_URL"
} > "$AUTH_REPORT" 2>&1

{
  echo "Retry Policy Evidence"
  date
  echo
  echo "Temporary retry pod:"
  kubectl get pod -n "$NAMESPACE" "$RETRY_POD" \
    -o custom-columns=NAME:.metadata.name,SERVICE_ACCOUNT:.spec.serviceAccountName,READY:.status.containerStatuses[*].ready,STATUS:.status.phase,CONTAINERS:.spec.containers[*].name
  echo
  echo "Product retry VirtualService:"
  kubectl get virtualservice product-retry -n "$NAMESPACE" -o yaml
  echo
  echo "[TRIGGER 500] $RETRY_POD serviceAccount=storefront-bff -> product actuator endpoint"
  curl_from_pod "$RETRY_POD" "$PRODUCT_500_URL"
  echo
  echo "[ENVOY RETRY/STATS EVIDENCE]"
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- \
    curl -sS 'http://127.0.0.1:15000/stats?filter=retry|istio_requests_total'
} > "$RETRY_REPORT" 2>&1

echo ">>> Evidence written:"
echo ">>> $AUTH_REPORT"
echo ">>> $RETRY_REPORT"
echo ">>> Pods are still running for screenshots:"
kubectl get pods -n "$NAMESPACE" "$AUTH_ALLOWED_POD" "$AUTH_BLOCKED_POD" "$RETRY_POD" -o wide
echo ">>> Kiali: Namespace=$NAMESPACE, Graph=Workload graph, Time=Last 5m or Last 10m, Display=Traffic."
