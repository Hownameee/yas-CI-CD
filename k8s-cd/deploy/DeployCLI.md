# Deploy YAS K8s (Hybrid Architecture)

## 0. Khởi động Minikube

Khởi tạo cụm và bật addon Ingress (bỏ qua bước cài Ingress Controller thủ công):

```bash
minikube delete
minikube start --driver=docker --disk-size='80000mb' --memory='18g' --cpus='12' --kubernetes-version=v1.29.0
minikube addons enable ingress
```

## 1. Triển khai Hệ thống (Kiến trúc Hybrid)

Di chuyển vào thư mục `deploy` và chạy tuần tự các script theo đúng 4 giai đoạn:

```bash
cd k8s-cd/deploy/
export DISABLE_OBSERVABILITY="true"
./01-setup-operators.sh
./02-setup-service-mesh.sh
./03-setup-argocd.sh

kubectl apply -f argo/app-dev.yaml
```

## 2. Service Mesh / Kiali sau khi deploy

Các manifest mTLS, retry, authorization policy và Prometheus monitor cho Kiali hiện tại đã được **quản lý hoàn toàn bằng GitOps (ArgoCD)** thông qua `yas-configuration` Helm chart thay vì chạy lệnh bash thủ công. Hệ thống sẽ tự động cấu hình ngay khi ArgoCD đồng bộ nhánh `main`.

Mở Kiali:

```bash
./istio/script/open-kiali.sh
```

Sau đó mở:

```text
http://localhost:20001/kiali
```

Gợi ý cấu hình graph:

```text
Namespace: yas-52
Graph: Workload graph hoặc Service graph
Time range: Last 10m / Last 15m
Display: Traffic, Security
```

Tạo traffic để Kiali hiện topology:

```bash
./istio/script/generate-kiali-traffic.sh
```

Script này mặc định dùng:

```text
YAS_NAMESPACE=yas-52
ENV_TAG=dev-52
COUNT=30
SLEEP_SECONDS=1
```

Nếu cần đổi:

```bash
YAS_NAMESPACE=yas-52 ENV_TAG=dev-52 COUNT=60 SLEEP_SECONDS=1 ./istio/script/generate-kiali-traffic.sh
```

## 3. Evidence cho yêu cầu Service Mesh

Chạy script này để tạo pod test, bắn traffic và ghi log evidence:

```bash
./istio/script/service-mesh-evidence.sh
```

Hoặc dùng lệnh one-shot đầy đủ hơn, gồm cả retry thành công và retry thất bại:

```bash
./istio/script/service-mesh-one-shot.sh
```

Lệnh one-shot sẽ tạo thêm service demo tạm:

```text
retry-flaky
```

`retry-flaky` cố ý trả `500, 500, 200` để chứng minh retry thành công trong một request.

Script sẽ tạo 3 pod tạm trong 5 phút:

```text
auth-allowed-storefront-bff  serviceAccount=storefront-bff
auth-blocked-default         serviceAccount=default
retry-test                   serviceAccount=storefront-bff
```

File evidence được ghi vào:

```text
k8s-cd/deploy/evidence/auth-policy-test-3.txt
k8s-cd/deploy/evidence/retry-failure-evidence.txt
k8s-cd/deploy/evidence/retry-success-evidence.txt
```

Ý nghĩa:

```text
auth-allowed-storefront-bff -> product = 200
auth-blocked-default        -> product = 403 RBAC: access denied
retry-test                  -> product actuator endpoint = 500 + Envoy response_flags.URX
retry-test                  -> retry-flaky = 200 after retry
```

Trong Kiali, chọn `Workload graph` và tìm:

```text
auth-allowed-storefront-bff -> product
auth-blocked-default -> product
retry-test -> product
retry-test -> retry-flaky
```

## 4. Cấu hình Local DNS (Mapping Domain)

```bash
kubectl get nodes -o wide

sudo nano /etc/hosts
```

*Thêm nội dung sau vào file `/etc/hosts`. Nếu bạn có đặt `ENV_TAG`, hãy thêm suffix tương ứng:*

### Nếu KHÔNG dùng ENV_TAG:
```text
192.168.49.2 pgoperator.yas.local.com
192.168.49.2 pgadmin.yas.local.com
192.168.49.2 akhq.yas.local.com
192.168.49.2 kibana.yas.local.com
192.168.49.2 identity.yas.local.com
192.168.49.2 backoffice.yas.local.com
192.168.49.2 storefront.yas.local.com
192.168.49.2 grafana.yas.local.com
192.168.49.2 api.yas.local.com
```

### Nếu dùng ENV_TAG (ví dụ `dev-52`):
```text
192.168.49.2 identity-dev-52.yas.local.com
192.168.49.2 backoffice-dev-52.yas.local.com
192.168.49.2 storefront-dev-52.yas.local.com
192.168.49.2 api-dev-52.yas.local.com
192.168.49.2 pgadmin-dev-52.yas.local.com
192.168.49.2 akhq-dev-52.yas.local.com
192.168.49.2 kibana-dev-52.yas.local.com
192.168.49.2 grafana.yas.local.com
```

## 5. Teardown & Cleanup (Dọn dẹp cụm)

Để gỡ bỏ toàn bộ hệ thống một cách sạch sẽ:

```bash
# Xoá ứng dụng trên ArgoCD (tự động dọn dẹp tất cả Helm releases và Kubernetes resources)
kubectl delete -f argo/app-dev.yaml
kubectl delete -f argo/app-staging.yaml

# Đợi ArgoCD gỡ cài đặt xong, xoá namespace
kubectl delete ns yas-dev yas-staging --ignore-not-found=true
```
