# Corrections for Project Report

File này ghi lại các phần cần sửa trong báo cáo để khớp với cấu hình hiện tại trong `k8s-cd/deploy`.

## Các điểm cần sửa

1. **Application layer không còn deploy đầy đủ 19 service qua `04-deploy-apps.sh`.**
   Script hiện tại deploy:
   - `backoffice-bff`, `backoffice-ui`
   - `storefront-bff`, `storefront-ui`
   - `swagger-ui`
   - `cart`, `customer`, `inventory`, `media`, `order`, `product`, `search`, `tax`, `sampledata`

   Các service đã bỏ khỏi deploy demo: `location`, `payment`, `promotion`, `rating`, `recommendation`, `webhook`.

2. **Retry evidence không nên mô tả là xem log sidecar của `product`.**
   Retry là hành vi của **caller sidecar**. Evidence đúng là:
   - `retry-test -> product` gọi endpoint trả `500`, Envoy caller sidecar có retry exhausted / `URX`.
   - `retry-test -> retry-flaky` gọi service demo trả `500, 500, 200`, request cuối cùng trả `200`, chứng minh retry thành công.

3. **Kiali topology cần Prometheus scrape metric từ Istio sidecar.**
   Manifest `istio/telemetry-monitor.yaml` đã được thêm để tạo:
   - `PodMonitor istio-sidecars`
   - `ServiceMonitor istiod`

4. **Namespace trong phần demo nên ghi theo biến hoặc theo thực tế `yas-52`.**
   Nếu báo cáo dùng môi trường demo hiện tại thì dùng `yas-52`, `ENV_TAG=dev-52`.
   Nếu muốn tổng quát thì dùng `${YAS_NAMESPACE}`.

5. **Danh sách screenshot retry nên đổi.**
   Không dùng `15-retry-envoy-log.png` với mô tả "product sidecar có 3 attempt".
   Nên dùng:
   - `15-retry-failure-evidence.png`: `cat k8s-cd/deploy/evidence/retry-failure-evidence.txt`
   - `16-retry-success-evidence.png`: `cat k8s-cd/deploy/evidence/retry-success-evidence.txt`

## Đoạn thay thế cho phần 4.4 Application layer

```md
### 4.4. Application layer (Phase 4)
File `04-deploy-apps.sh` deploy các service cần thiết cho demo:

1. `yas-configuration` — chart tổng hợp ConfigMap/Secret + Stakater Reloader
2. `backoffice-bff` + `backoffice-ui`
3. `storefront-bff` + `storefront-ui`
4. `swagger-ui`
5. Vòng lặp 9 microservice core: `cart`, `customer`, `inventory`, `media`, `order`, `product`, `search`, `tax`, `sampledata`
6. Populate ảnh sample vào pod `media` bằng `kubectl cp -c media`

Các service upstream không cần cho demo hiện tại (`location`, `payment`, `promotion`, `rating`, `recommendation`, `webhook`) đã được bỏ khỏi script deploy để giảm tài nguyên và tránh lỗi route tới service không tồn tại.
```

## Đoạn thay thế cho phần 8.3 Kiali topology

```md
### 8.3. Kiali topology (Yêu cầu nâng cao #2)

Kiali lấy dữ liệu topology từ Prometheus metric của Istio sidecar. Vì vậy ngoài cài Kiali, project có thêm `istio/telemetry-monitor.yaml` để Prometheus scrape:
- `PodMonitor istio-sidecars`: scrape `/stats/prometheus` của các pod có Istio sidecar trong namespace ứng dụng và `ingress-nginx`
- `ServiceMonitor istiod`: scrape control plane Istio

Mở Kiali:

```bash
cd k8s-cd/deploy
./07-open-kiali.sh
```

Truy cập:

```text
http://localhost:20001/kiali
```

Tạo traffic:

```bash
YAS_NAMESPACE=yas-52 ENV_TAG=dev-52 COUNT=60 SLEEP_SECONDS=1 ./05-generate-kiali-traffic.sh
```

Hoặc chạy một lệnh evidence đầy đủ cho AuthorizationPolicy và Retry:

```bash
YAS_NAMESPACE=yas-52 POD_TTL_SECONDS=600 ./08-service-mesh-one-shot.sh
```

Trong Kiali chọn:
- Namespace: `yas-52`
- Graph: `Workload graph`
- Time range: `Last 5m` hoặc `Last 10m`
- Display: bật `Traffic` và `Security`

Các flow kỳ vọng:
- `ingress-nginx -> storefront-ui`
- `storefront-ui/storefront-bff -> product/media/search/...`
- `auth-allowed-storefront-bff -> product`
- `auth-blocked-default -> product` với response `403`
- `retry-test -> product` với retry exhausted
- `retry-test -> retry-flaky` với response `200` sau retry
```

## Đoạn thay thế cho phần 8.4 Retry policy

```md
### 8.4. Retry policy (Yêu cầu nâng cao #3.a)

`istio/virtual-service-retry-template.yaml` tạo `VirtualService` retry cho toàn bộ service đang deploy trong demo:
- `backoffice-bff`, `backoffice-ui`
- `storefront-bff`, `storefront-ui`
- `swagger-ui`
- `cart`, `customer`, `inventory`, `media`, `order`, `product`, `search`, `tax`, `sampledata`

Ví dụ `product-retry`:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: product-retry
  namespace: ${NAMESPACE}
spec:
  hosts:
    - product.${NAMESPACE}.svc.cluster.local
  http:
    - timeout: 10s
      retries:
        attempts: 3
        perTryTimeout: 3s
        retryOn: 5xx,connect-failure,refused-stream,gateway-error
      route:
        - destination:
            host: product.${NAMESPACE}.svc.cluster.local
            port:
              number: 80
```

Lưu ý: retry được thực hiện ở **caller sidecar**, không phải ở sidecar của service đích. Vì vậy evidence đúng là xem request/log/stat từ pod caller.

Project có script:

```bash
YAS_NAMESPACE=yas-52 POD_TTL_SECONDS=600 ./08-service-mesh-one-shot.sh
```

Script tạo `retry-flaky` tạm thời. Service này cố ý trả `500, 500, 200`; khi gọi qua VirtualService retry, client nhận `200`, chứng minh retry policy hoạt động.

Evidence được lưu tại:

```text
k8s-cd/deploy/evidence/retry-failure-evidence.txt
k8s-cd/deploy/evidence/retry-success-evidence.txt
```
```

## Đoạn thay thế cho phần 8.5.1 Test AuthorizationPolicy

```md
### 8.5.1. Kịch bản test policy (Yêu cầu nâng cao #3 Test)

Chạy một lệnh để tạo pod test, gọi service, tạo traffic cho Kiali và ghi evidence:

```bash
cd k8s-cd/deploy
YAS_NAMESPACE=yas-52 POD_TTL_SECONDS=600 ./08-service-mesh-one-shot.sh
```

Script tạo các pod tạm:

| Pod | ServiceAccount | Mục đích |
|---|---|---|
| `auth-allowed-storefront-bff` | `storefront-bff` | Caller hợp lệ gọi `product` |
| `auth-blocked-default` | `default` | Caller không hợp lệ gọi `product` |
| `retry-test` | `storefront-bff` | Caller dùng để test retry |
| `retry-flaky` | không cần SA đặc biệt | Service demo trả `500,500,200` |

Kết quả kỳ vọng:

| Case | Kết quả |
|---|---|
| `auth-allowed-storefront-bff -> product` | HTTP `200` |
| `auth-blocked-default -> product` | HTTP `403` / RBAC denied |
| `retry-test -> product actuator health` | HTTP `500`, retry exhausted |
| `retry-test -> retry-flaky` | HTTP `200` sau retry |

File evidence:

```text
k8s-cd/deploy/evidence/auth-policy-test-3.txt
k8s-cd/deploy/evidence/retry-failure-evidence.txt
k8s-cd/deploy/evidence/retry-success-evidence.txt
```
```

## Đoạn thay thế cho phụ lục screenshot Service Mesh

```md
### Screenshot Service Mesh cần chụp

| # | Tên file | Chụp gì | Chứng minh |
|---|---|---|---|
| 08 | `08-kiali-graph.png` | Kiali Graph namespace `yas-52`, thấy các edge giữa workload | Topology |
| 09 | `09-kiali-mtls-locks.png` | Kiali bật Display `Security`, thấy mTLS lock | mTLS active |
| 10 | `10-peerauth-strict.png` | `kubectl get peerauthentication -n yas-52 -o yaml` | mTLS STRICT |
| 11 | `11-authpolicy-list.png` | `kubectl get authorizationpolicy -n yas-52` | AuthZ policy đã apply |
| 12 | `12-auth-allowed.png` | `cat k8s-cd/deploy/evidence/auth-policy-test-3.txt`, phần ALLOWED | Test allow |
| 13 | `13-auth-denied.png` | `cat k8s-cd/deploy/evidence/auth-policy-test-3.txt`, phần BLOCKED | Test deny |
| 14 | `14-virtualservice-retry.png` | `kubectl get virtualservice product-retry -n yas-52 -o yaml` | Retry policy |
| 15 | `15-retry-failure-evidence.png` | `cat k8s-cd/deploy/evidence/retry-failure-evidence.txt` | Retry exhausted khi service trả 500 liên tục |
| 16 | `16-retry-success-evidence.png` | `cat k8s-cd/deploy/evidence/retry-success-evidence.txt` | Retry thành công khi upstream trả `500,500,200` |
```

## Lệnh chụp evidence nhanh

```bash
cd k8s-cd/deploy
YAS_NAMESPACE=yas-52 POD_TTL_SECONDS=600 ./08-service-mesh-one-shot.sh

kubectl get peerauthentication,destinationrule,virtualservice,authorizationpolicy -n yas-52
kubectl get peerauthentication -n yas-52 -o yaml
kubectl get authorizationpolicy -n yas-52
kubectl get virtualservice product-retry -n yas-52 -o yaml

cat evidence/auth-policy-test-3.txt
cat evidence/retry-failure-evidence.txt
cat evidence/retry-success-evidence.txt
```

