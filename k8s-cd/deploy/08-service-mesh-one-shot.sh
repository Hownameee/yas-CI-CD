#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${YAS_NAMESPACE:-yas-52}"
POD_TTL_SECONDS="${POD_TTL_SECONDS:-600}"
REPORT_DIR="${REPORT_DIR:-$SCRIPT_DIR/evidence}"
PRODUCT_OK_URL="${PRODUCT_OK_URL:-http://product/product/storefront/products}"
PRODUCT_500_URL="${PRODUCT_500_URL:-http://product/product/actuator/health}"
FLAKY_HOST="retry-flaky.${NAMESPACE}.svc.cluster.local"
FLAKY_URL="http://${FLAKY_HOST}/"
FLAKY_RESET_URL="http://${FLAKY_HOST}/reset"

mkdir -p "$REPORT_DIR"

AUTH_ALLOWED_POD="auth-allowed-storefront-bff"
AUTH_BLOCKED_POD="auth-blocked-default"
RETRY_POD="retry-test"
FLAKY_POD="retry-flaky"
FLAKY_SERVICE="retry-flaky"
FLAKY_VS="retry-flaky-success"

create_curl_pod() {
  local pod_name=$1
  local service_account=$2

  kubectl delete pod "$pod_name" -n "$NAMESPACE" --ignore-not-found=true >/dev/null
  kubectl run "$pod_name" -n "$NAMESPACE" \
    --image=curlimages/curl:8.7.1 \
    --restart=Never \
    --overrides="{\"spec\":{\"serviceAccountName\":\"$service_account\",\"terminationGracePeriodSeconds\":0,\"containers\":[{\"name\":\"curl\",\"image\":\"curlimages/curl:8.7.1\",\"command\":[\"sleep\",\"$POD_TTL_SECONDS\"]}]}}"
  kubectl wait --for=condition=Ready "pod/$pod_name" -n "$NAMESPACE" --timeout=180s
}

create_retry_flaky_service() {
  kubectl delete virtualservice "$FLAKY_VS" -n "$NAMESPACE" --ignore-not-found=true >/dev/null
  kubectl delete service "$FLAKY_SERVICE" -n "$NAMESPACE" --ignore-not-found=true >/dev/null
  kubectl delete pod "$FLAKY_POD" -n "$NAMESPACE" --ignore-not-found=true >/dev/null

  cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${FLAKY_POD}
  namespace: ${NAMESPACE}
  labels:
    app: ${FLAKY_SERVICE}
spec:
  activeDeadlineSeconds: ${POD_TTL_SECONDS}
  terminationGracePeriodSeconds: 0
  containers:
    - name: flaky
      image: python:3.12-alpine
      ports:
        - name: http
          containerPort: 8080
      command:
        - python
        - -c
        - |
          from http.server import BaseHTTPRequestHandler, HTTPServer
          count = 0
          class Handler(BaseHTTPRequestHandler):
              def do_GET(self):
                  global count
                  if self.path.startswith("/reset"):
                      count = 0
                      self.send_response(200)
                      self.end_headers()
                      self.wfile.write(b"reset")
                      return
                  count += 1
                  if count <= 2:
                      self.send_response(500)
                      self.end_headers()
                      self.wfile.write(("flaky 500 attempt %d" % count).encode())
                      return
                  self.send_response(200)
                  self.end_headers()
                  self.wfile.write(("flaky 200 attempt %d" % count).encode())
          HTTPServer(("", 8080), Handler).serve_forever()
---
apiVersion: v1
kind: Service
metadata:
  name: ${FLAKY_SERVICE}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: ${FLAKY_SERVICE}
  ports:
    - name: http
      port: 80
      targetPort: 8080
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ${FLAKY_VS}
  namespace: ${NAMESPACE}
spec:
  hosts:
    - ${FLAKY_HOST}
  http:
    - timeout: 10s
      retries:
        attempts: 3
        perTryTimeout: 3s
        retryOn: 5xx,connect-failure,refused-stream,gateway-error
      route:
        - destination:
            host: ${FLAKY_HOST}
            port:
              number: 80
YAML

  kubectl wait --for=condition=Ready "pod/$FLAKY_POD" -n "$NAMESPACE" --timeout=180s
}

curl_from_pod() {
  local pod_name=$1
  local url=$2

  kubectl exec -n "$NAMESPACE" "$pod_name" -c curl -- curl -i -sS "$url" || true
}

echo ">>> Creating temporary mesh pods in namespace '$NAMESPACE' for $POD_TTL_SECONDS seconds..."
create_curl_pod "$AUTH_ALLOWED_POD" "storefront-bff"
create_curl_pod "$AUTH_BLOCKED_POD" "default"
create_curl_pod "$RETRY_POD" "storefront-bff"

echo ">>> Creating temporary retry success demo service '$FLAKY_SERVICE'..."
create_retry_flaky_service

echo ">>> Generating AuthorizationPolicy traffic..."
for i in $(seq 1 20); do
  kubectl exec -n "$NAMESPACE" "$AUTH_ALLOWED_POD" -c curl -- curl -sS -o /dev/null "$PRODUCT_OK_URL" || true
  kubectl exec -n "$NAMESPACE" "$AUTH_BLOCKED_POD" -c curl -- curl -sS -o /dev/null "$PRODUCT_OK_URL" || true
done

echo ">>> Generating retry failure traffic: retry-test -> product returns 500 until retry limit is exceeded..."
for i in $(seq 1 20); do
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- curl -sS -o /dev/null "$PRODUCT_500_URL" || true
done

echo ">>> Generating retry success traffic: retry-test -> retry-flaky returns 500,500,200 in one client request..."
kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- curl -sS -o /dev/null "$FLAKY_RESET_URL" || true
kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- curl -i -sS "$FLAKY_URL" || true
for i in $(seq 1 10); do
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- curl -sS -o /dev/null "$FLAKY_RESET_URL" || true
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- curl -sS -o /dev/null "$FLAKY_URL" || true
done

AUTH_REPORT="$REPORT_DIR/auth-policy-test-3.txt"
RETRY_FAILURE_REPORT="$REPORT_DIR/retry-failure-evidence.txt"
RETRY_SUCCESS_REPORT="$REPORT_DIR/retry-success-evidence.txt"

{
  echo "AuthorizationPolicy Test 3 Evidence"
  date
  echo
  echo "Temporary pods:"
  kubectl get pods -n "$NAMESPACE" "$AUTH_ALLOWED_POD" "$AUTH_BLOCKED_POD" "$RETRY_POD" "$FLAKY_POD" \
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
  echo "Retry Failure Evidence"
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
  echo "[ENVOY RETRY FAILURE/STATS EVIDENCE]"
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- \
    curl -sS 'http://127.0.0.1:15000/stats?filter=retry|istio_requests_total'
} > "$RETRY_FAILURE_REPORT" 2>&1

{
  echo "Retry Success Evidence"
  date
  echo
  echo "Temporary flaky service:"
  kubectl get pod "$FLAKY_POD" -n "$NAMESPACE" -o wide
  kubectl get service "$FLAKY_SERVICE" -n "$NAMESPACE" -o wide
  kubectl get virtualservice "$FLAKY_VS" -n "$NAMESPACE" -o yaml
  echo
  echo "[RESET FLAKY COUNTER]"
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- curl -i -sS "$FLAKY_RESET_URL" || true
  echo
  echo "[RETRY SUCCESS] One client request should finish as 200 after upstream returns 500 twice."
  curl_from_pod "$RETRY_POD" "$FLAKY_URL"
  echo
  echo "[ENVOY RETRY SUCCESS/STATS EVIDENCE]"
  kubectl exec -n "$NAMESPACE" "$RETRY_POD" -c curl -- \
    curl -sS 'http://127.0.0.1:15000/stats?filter=retry-flaky|retry|istio_requests_total'
} > "$RETRY_SUCCESS_REPORT" 2>&1

echo ">>> Evidence written:"
echo ">>> $AUTH_REPORT"
echo ">>> $RETRY_FAILURE_REPORT"
echo ">>> $RETRY_SUCCESS_REPORT"
echo ">>> Temporary pods/services are still running for screenshots:"
kubectl get pods -n "$NAMESPACE" "$AUTH_ALLOWED_POD" "$AUTH_BLOCKED_POD" "$RETRY_POD" "$FLAKY_POD" -o wide
echo ">>> Kiali: Namespace=$NAMESPACE, Graph=Workload graph, Time=Last 5m or Last 10m, Display=Traffic."
echo ">>> Expected Kiali flows:"
echo ">>>   auth-allowed-storefront-bff -> product = 200"
echo ">>>   auth-blocked-default -> product = 403"
echo ">>>   retry-test -> product = 500 retry exhausted"
echo ">>>   retry-test -> retry-flaky = 200 after retry"
