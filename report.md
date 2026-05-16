# Đồ án 2 - Xây dựng hệ thống CD cho YAS (Yet Another Shop)

> **Môn học**: DevOps  
> **Đề tài**: Xây dựng pipeline CI/CD và Service Mesh cho hệ thống microservice YAS  
> **Nguồn tham khảo ứng dụng**: https://github.com/nashtech-garage/yas  
> **Nhóm**: _<điền MSSV - Họ tên>_

---

## Mục lục

1. [Tổng quan](#1-tổng-quan)
2. [Kiến trúc và công nghệ](#2-kiến-trúc-và-công-nghệ)
3. [Cấu trúc thư mục](#3-cấu-trúc-thư-mục)
4. [Hạ tầng Kubernetes](#4-hạ-tầng-kubernetes)
5. [CI Pipeline - GitHub Actions](#5-ci-pipeline---github-actions)
6. [CD Pipeline - Jenkins](#6-cd-pipeline---jenkins)
7. [Destroy Pipeline](#7-destroy-pipeline)
8. [Service Mesh - Istio và Kiali](#8-service-mesh---istio-và-kiali)
9. [Hướng dẫn triển khai](#9-hướng-dẫn-triển-khai)
10. [Kịch bản test và evidence](#10-kịch-bản-test-và-evidence)
11. [Đối chiếu yêu cầu đồ án](#11-đối-chiếu-yêu-cầu-đồ-án)
12. [Danh sách screenshot cần nộp](#12-danh-sách-screenshot-cần-nộp)

---

## 1. Tổng quan

YAS (Yet Another Shop) là ứng dụng e-commerce dạng microservice. Hệ thống gồm các service backend Spring Boot, frontend Next.js, Keycloak để xác thực, PostgreSQL làm database, Kafka/Debezium cho event và CDC, Elasticsearch cho search, Redis cho cache.

Trong đồ án này, nhóm xây dựng hệ thống CI/CD và triển khai YAS lên Kubernetes bằng Minikube. Ngoài phần cơ bản, nhóm triển khai thêm Service Mesh bằng Istio và Kiali để bật mTLS, quan sát topology, cấu hình retry và giới hạn service-to-service bằng AuthorizationPolicy.

| Hạng mục | Trạng thái |
|---|---|
| Kubernetes cluster bằng Minikube | Hoàn thành |
| Helm chart deploy ứng dụng | Hoàn thành |
| CI GitHub Actions build image và push Docker Hub | Hoàn thành |
| Jenkins CD job chọn branch từng service | Hoàn thành |
| Jenkins destroy job xóa namespace theo build | Hoàn thành |
| Istio mTLS, Kiali, retry, AuthorizationPolicy | Hoàn thành |

---

## 2. Kiến trúc và công nghệ

### 2.1. Stack ứng dụng

| Thành phần | Công nghệ |
|---|---|
| Backend | Java 21, Spring Boot 3.2, Spring Cloud Gateway |
| Frontend | Next.js |
| Identity | Keycloak, realm `Yas` |
| Database | PostgreSQL, Zalando Postgres Operator |
| Messaging | Kafka, Strimzi Operator, Debezium Connect |
| Search | Elasticsearch, ECK Operator |
| Cache | Redis |
| API Gateway/BFF | `storefront-bff`, `backoffice-bff` |

### 2.2. Stack DevOps

| Thành phần | Công nghệ |
|---|---|
| Kubernetes | Minikube 1 node |
| Package manager | Helm 3 |
| Ingress | NGINX Ingress Controller |
| CI | GitHub Actions |
| CD | Jenkins Pipeline |
| Service Mesh | Istio |
| Mesh visualization | Kiali |
| Metrics | Prometheus |
| TLS/cert | cert-manager |

---

## 3. Cấu trúc thư mục

```text
Project-02/
├── .github/workflows/                 # CI workflow cho từng service
├── Jenkinsfile                        # CD job developer_build
├── Jenkinsfile-destroy                # Job xóa deployment
├── report.md                          # Báo cáo đồ án
├── screenshots/                       # Ảnh minh chứng
├── k8s-cd/
│   ├── deploy/
│   │   ├── 01-setup-operators.sh      # Cài operators và observability
│   │   ├── 02-setup-service-mesh.sh   # Cài Istio, Kiali, mTLS, retry, auth policy
│   │   ├── 03-setup-data-layer.sh     # Cài PostgreSQL, Kafka, Elastic, Redis, Keycloak
│   │   ├── 04-deploy-apps.sh          # Deploy application layer
│   │   ├── 05-generate-kiali-traffic.sh
│   │   ├── 06-service-mesh-evidence.sh
│   │   ├── 07-open-kiali.sh
│   │   ├── 08-service-mesh-one-shot.sh
│   │   ├── DeployCLI.md
│   │   ├── evidence/
│   │   └── istio/
│   │       ├── mtls.yaml
│   │       ├── destination-rule.yaml
│   │       ├── ingress-mtls.yaml
│   │       ├── auth-policy.yaml
│   │       ├── virtual-service-retry-template.yaml
│   │       ├── keycloak-internal-dns.yaml
│   │       └── telemetry-monitor.yaml
│   └── charts/
│       ├── backend/
│       ├── ui/
│       ├── yas-configuration/
│       ├── backoffice-bff/
│       ├── backoffice-ui/
│       ├── storefront-bff/
│       ├── storefront-ui/
│       ├── swagger-ui/
│       └── cart/ customer/ inventory/ media/ order/ product/ search/ tax/ sampledata/
```

---

## 4. Hạ tầng Kubernetes

### 4.1. Khởi tạo Minikube

```bash
minikube delete
minikube start --driver=docker \
  --disk-size='80000mb' \
  --memory='18g' \
  --cpus='12' \
  --kubernetes-version=v1.29.0
minikube addons enable ingress
```

Minikube được dùng để đáp ứng yêu cầu triển khai trên Kubernetes cluster. Cụm chạy dạng 1 node, phù hợp với môi trường học tập và demo.

**Minh chứng cần chèn**

![Cluster nodes và Minikube status](screenshots/01-cluster-nodes.png)

### 4.2. Phase 1 - Operators và observability

Script:

```bash
k8s-cd/deploy/01-setup-operators.sh
```

Các thành phần được cài:

| Component | Namespace |
|---|---|
| cert-manager | `cert-manager` |
| Postgres Operator | `postgres` |
| Strimzi Kafka Operator | `kafka` |
| ECK Operator | `elasticsearch` |
| OpenTelemetry Operator | `observability` |
| Loki, Tempo, Promtail | `observability` |
| Prometheus stack | `observability` |
| Grafana Operator | `observability` |
| Keycloak Operator | `keycloak` |

### 4.3. Phase 3 - Data layer

Script:

```bash
k8s-cd/deploy/03-setup-data-layer.sh
```

Data layer được deploy vào namespace ứng dụng, ví dụ `yas-52`:

- PostgreSQL và pgAdmin
- Kafka cluster, Kafka Connect, Debezium connector, AKHQ
- Elasticsearch và Kibana
- Redis
- Keycloak service và realm `Yas`

### 4.4. Phase 4 - Application layer

Script:

```bash
k8s-cd/deploy/04-deploy-apps.sh
```

Các service đang deploy trong demo hiện tại:

| Nhóm | Service |
|---|---|
| Configuration | `yas-configuration` |
| BFF | `backoffice-bff`, `storefront-bff` |
| UI | `backoffice-ui`, `storefront-ui`, `swagger-ui` |
| Core backend | `cart`, `customer`, `inventory`, `media`, `order`, `product`, `search`, `tax`, `sampledata` |

Một số service upstream không cần cho demo hiện tại đã được bỏ khỏi script deploy để giảm tài nguyên và tránh route tới service không tồn tại: `location`, `payment`, `promotion`, `rating`, `recommendation`, `webhook`.

Sau khi deploy `media`, script copy sample image vào container `media` bằng `kubectl cp -c media`.

**Minh chứng cần chèn**

![Pods ứng dụng chạy trong namespace](screenshots/02-app-pods-running.png)

---

## 5. CI Pipeline - GitHub Actions

### 5.1. Mục tiêu

Mỗi service có workflow riêng trong `.github/workflows`. Khi code thay đổi hoặc chạy thủ công, workflow build source, build Docker image và push lên Docker Hub.

**Minh chứng cần chèn**

![GitHub Actions build thành công và Docker Hub có tag image](screenshots/03-ci-dockerhub-tags.png)

### 5.2. Quy tắc tag image

```yaml
if [ "${{ github.ref_name }}" == "main" ]; then
  echo "DOCKER_TAG=latest" >> $GITHUB_ENV
else
  echo "DOCKER_TAG=${{ github.sha }}" >> $GITHUB_ENV
fi
```

Ý nghĩa:

| Branch | Docker tag |
|---|---|
| `main` | `latest` |
| branch khác | commit SHA |

Ví dụ image:

```text
hownamee/yas-product:latest
hownamee/yas-tax:<commit_sha>
```

### 5.3. Build Java service

Các service Spring Boot dùng Maven:

```yaml
- uses: actions/checkout@v4
- uses: ./.github/workflows/actions
- run: mvn clean install -pl <service> -am
- uses: docker/login-action@v3
- uses: docker/build-push-action@v6
  with:
    context: ./<service>
    push: true
    tags: ${{ secrets.DOCKERHUB_USERNAME }}/yas-<service>:${{ env.DOCKER_TAG }}
```

### 5.4. Build frontend

Frontend Next.js dùng Node.js:

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 20
- run: npm ci
- run: npm run build
- run: npm run lint
- run: npx prettier --check .
- uses: docker/build-push-action@v6
```

---

## 6. CD Pipeline - Jenkins

### 6.1. Mục tiêu

Job Jenkins `developer_build` cho phép developer chọn branch riêng cho từng service. Job tính Docker tag tương ứng, deploy chart lên Kubernetes và expose service bằng Ingress host riêng theo build ID.

**Minh chứng cần chèn**

![Jenkins build parameters và console output deploy](screenshots/04-jenkins-developer-build.png)

Ví dụ build Jenkins ID `52`:

```text
Namespace: yas-52
ENV_TAG: dev-52
Storefront: storefront-dev-52.yas.local.com
API: api-dev-52.yas.local.com
Identity: identity-dev-52.yas.local.com
```

### 6.2. Cách tính tag image

Nếu branch là `main`, Jenkins dùng tag `latest`. Nếu branch khác `main`, Jenkins dùng commit hash cuối của branch:

```groovy
if (branchName != 'main' && serviceName != 'swagger-ui') {
    tag = sh(
        script: "git ls-remote https://github.com/Hownameee/yas.git ${branchName} | cut -f1",
        returnStdout: true
    ).trim()
}
```

### 6.3. Deploy bằng Helm

Mỗi service được deploy bằng:

```bash
helm upgrade --install <service> k8s-cd/charts/<service> \
  --namespace <namespace> \
  --set <image.tag>=<tag> \
  --set <ingress.host>=<host>
```

### 6.4. Access information

Cuối job, Jenkins in ra thông tin để thêm vào `/etc/hosts`:

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

---

## 7. Destroy Pipeline

Job `Jenkinsfile-destroy` dùng để xóa môi trường theo build ID.

**Minh chứng cần chèn**

![Jenkins destroy job thành công](screenshots/05-jenkins-destroy.png)

Parameter:

```groovy
string(name: 'TARGET_BUILD_ID', defaultValue: '')
booleanParam(name: 'CONFIRM_DESTROY', defaultValue: false)
```

Logic cleanup:

```bash
helm list -n yas-${TARGET_BUILD_ID} -q | xargs -r helm uninstall -n yas-${TARGET_BUILD_ID}
kubectl delete ns yas-${TARGET_BUILD_ID} --ignore-not-found=true
```

Job yêu cầu nhập `TARGET_BUILD_ID` và tick `CONFIRM_DESTROY` để tránh xóa nhầm.

---

## 8. Service Mesh - Istio và Kiali

Phần này đáp ứng yêu cầu nâng cao 2 điểm:

1. Enable mTLS giữa các service
2. Vẽ flow chart/topology bằng Kiali
3. Retry tự động khi service trả lỗi 500
4. AuthorizationPolicy chỉ cho phép service hợp lệ giao tiếp với nhau
5. Test allow/deny bằng curl từ pod trong cluster

### 8.1. Cài đặt Istio và Kiali

Script:

```bash
k8s-cd/deploy/02-setup-service-mesh.sh
```

Script thực hiện:

- Cài `istio-base`
- Cài `istiod`
- Cài `kiali-server`
- Label namespace ứng dụng để bật sidecar injection
- Label namespace `ingress-nginx` để Ingress cũng chạy trong mesh
- Apply manifest mTLS, DestinationRule, retry, AuthorizationPolicy, Keycloak internal DNS và telemetry monitor

Các manifest chính:

| File | Vai trò |
|---|---|
| `istio/mtls.yaml` | Bật PeerAuthentication STRICT cho namespace |
| `istio/destination-rule.yaml` | Bật ISTIO_MUTUAL cho traffic nội bộ |
| `istio/ingress-mtls.yaml` | Cấu hình mTLS cho ingress-nginx |
| `istio/auth-policy.yaml` | Giới hạn service-to-service |
| `istio/virtual-service-retry-template.yaml` | Retry policy |
| `istio/keycloak-internal-dns.yaml` | Cho service nội bộ gọi Keycloak qua host public |
| `istio/telemetry-monitor.yaml` | Cho Prometheus scrape Istio metrics để Kiali vẽ graph |

### 8.2. mTLS

Namespace ứng dụng dùng `PeerAuthentication` STRICT:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: ${NAMESPACE}
spec:
  mtls:
    mode: STRICT
```

DestinationRule mặc định:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: default
  namespace: ${NAMESPACE}
spec:
  host: "*.${NAMESPACE}.svc.cluster.local"
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
```

Một số workload dùng native protocol như PostgreSQL, Kafka, Kafka Connect, Zookeeper được cấu hình PERMISSIVE để tránh lỗi handshake/protocol khi chạy cùng sidecar.

**Minh chứng cần chèn**

![PeerAuthentication STRICT và DestinationRule ISTIO_MUTUAL](screenshots/06-mtls-strict.png)

### 8.3. Kiali topology

Kiali cần Prometheus metric từ Istio sidecar. Vì vậy project thêm `istio/telemetry-monitor.yaml`:

- `PodMonitor istio-sidecars`: scrape `/stats/prometheus` từ sidecar Envoy
- `ServiceMonitor istiod`: scrape metric control plane

Mở Kiali:

```bash
cd k8s-cd/deploy
./07-open-kiali.sh
```

Sau đó truy cập:

```text
http://localhost:20001/kiali
```

Cấu hình graph:

```text
Namespace: yas-52
Graph: Workload graph
Time range: Last 5m hoặc Last 10m
Display: Traffic, Security
```

Tạo traffic thường:

```bash
YAS_NAMESPACE=yas-52 ENV_TAG=dev-52 COUNT=60 SLEEP_SECONDS=1 ./05-generate-kiali-traffic.sh
```

Tạo traffic cho test Service Mesh:

```bash
YAS_NAMESPACE=yas-52 POD_TTL_SECONDS=600 ./08-service-mesh-one-shot.sh
```

Các flow kỳ vọng trên Kiali:

- `ingress-nginx -> storefront-ui`
- `storefront-ui/storefront-bff -> product`
- `storefront-bff -> media/search/cart/customer`
- `auth-allowed-storefront-bff -> product`
- `auth-blocked-default -> product`
- `retry-test -> product`
- `retry-test -> retry-flaky`

**Minh chứng cần chèn**

![Kiali topology có flow giữa các workload](screenshots/07-kiali-topology.png)

### 8.4. Retry policy

`istio/virtual-service-retry-template.yaml` tạo `VirtualService` retry cho các service đang deploy trong demo:

- `backoffice-bff`
- `backoffice-ui`
- `storefront-bff`
- `storefront-ui`
- `swagger-ui`
- `cart`
- `customer`
- `inventory`
- `media`
- `order`
- `product`
- `search`
- `tax`
- `sampledata`

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

Lưu ý quan trọng: retry là hành vi của **caller sidecar**. Vì vậy evidence đúng phải lấy từ pod caller, không phải từ sidecar của service đích.

Để chứng minh retry, project dùng script `08-service-mesh-one-shot.sh`. Script tạo service demo `retry-flaky`, service này cố ý trả:

```text
500, 500, 200
```

Khi `retry-test` gọi `retry-flaky`, client nhận HTTP `200` sau khi Istio retry các lần lỗi 500 trước đó.

**Minh chứng cần chèn**

![VirtualService retry và evidence retry thành công/thất bại](screenshots/08-retry-evidence.png)

### 8.5. AuthorizationPolicy

`istio/auth-policy.yaml` tạo policy ALLOW cho từng service. Khi một workload có AuthorizationPolicy ALLOW, các request không match rule sẽ bị Envoy chặn bằng `403`.

Ví dụ policy cho `product`:

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-product-callers
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: product
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/ingress-nginx/sa/ingress-nginx
              - cluster.local/ns/${NAMESPACE}/sa/backoffice-bff
              - cluster.local/ns/${NAMESPACE}/sa/storefront-bff
              - cluster.local/ns/${NAMESPACE}/sa/cart
              - cluster.local/ns/${NAMESPACE}/sa/inventory
              - cluster.local/ns/${NAMESPACE}/sa/order
              - cluster.local/ns/${NAMESPACE}/sa/sampledata
              - cluster.local/ns/${NAMESPACE}/sa/search
              - cluster.local/ns/${NAMESPACE}/sa/swagger-ui
```

Bảng policy chính:

| Target service | Caller được phép |
|---|---|
| `backoffice-ui` | `ingress-nginx`, `backoffice-bff` |
| `storefront-ui` | `ingress-nginx`, `storefront-bff` |
| `swagger-ui` | `ingress-nginx` |
| `backoffice-bff` | `ingress-nginx`, `backoffice-ui`, `swagger-ui` |
| `storefront-bff` | `ingress-nginx`, `storefront-ui`, `swagger-ui` |
| `product` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `cart`, `inventory`, `order`, `sampledata`, `search`, `swagger-ui` |
| `media` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `cart`, `product`, `sampledata`, `swagger-ui` |
| `cart` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `order`, `swagger-ui` |
| `customer` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `order`, `swagger-ui` |
| `order` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `swagger-ui` |
| `tax` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `order`, `swagger-ui` |
| `search` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `swagger-ui` |
| `inventory` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `order`, `swagger-ui` |
| `sampledata` | `ingress-nginx`, `backoffice-bff`, `storefront-bff`, `swagger-ui` |

**Minh chứng cần chèn**

![AuthorizationPolicy allow và deny bằng curl pod](screenshots/09-auth-policy-evidence.png)

### 8.6. Keycloak internal DNS

Một lỗi thường gặp là backend trong cluster cần gọi issuer URI:

```text
http://identity-dev-52.yas.local.com/realms/Yas
```

Nhưng domain public này không tự resolve đúng trong cluster. Manifest `istio/keycloak-internal-dns.yaml` tạo `ServiceEntry` và `VirtualService` để map host public của Keycloak về service nội bộ:

```text
keycloak-service.${NAMESPACE}.svc.cluster.local:8080
```

Nhờ vậy frontend vẫn dùng domain public, còn service backend trong mesh vẫn gọi được Keycloak bằng cùng issuer URI.

---

## 9. Hướng dẫn triển khai

### 9.1. Deploy thủ công

```bash
minikube delete
minikube start --driver=docker --disk-size='80000mb' --memory='18g' --cpus='12' --kubernetes-version=v1.29.0
minikube addons enable ingress

cd k8s-cd/deploy
export YAS_NAMESPACE="yas-52"
export ENV_TAG="dev-52"

./01-setup-operators.sh
./02-setup-service-mesh.sh
./03-setup-data-layer.sh
./04-deploy-apps.sh
```

### 9.2. Cập nhật `/etc/hosts`

Lấy IP Minikube:

```bash
minikube ip
```

Ví dụ IP là `192.168.49.2`, thêm vào `/etc/hosts`:

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

### 9.3. Mở Kiali

```bash
cd k8s-cd/deploy
./07-open-kiali.sh
```

Truy cập:

```text
http://localhost:20001/kiali
```

### 9.4. Sinh traffic

Traffic cho app:

```bash
YAS_NAMESPACE=yas-52 ENV_TAG=dev-52 COUNT=60 SLEEP_SECONDS=1 ./05-generate-kiali-traffic.sh
```

Traffic và evidence cho Service Mesh:

```bash
YAS_NAMESPACE=yas-52 POD_TTL_SECONDS=600 ./08-service-mesh-one-shot.sh
```

---

## 10. Kịch bản test và evidence

### 10.1. Kiểm tra cluster

```bash
minikube status
kubectl get nodes -o wide
kubectl get pod -n yas-52
kubectl get ingress -n yas-52
helm list -n yas-52
```

### 10.2. Kiểm tra mTLS

```bash
kubectl get peerauthentication -n yas-52 -o yaml
kubectl get destinationrule -n yas-52 -o yaml
kubectl get ns yas-52 --show-labels
```

Kỳ vọng:

- Namespace có label `istio-injection=enabled`
- `PeerAuthentication` default có `mode: STRICT`
- `DestinationRule` có `tls.mode: ISTIO_MUTUAL`

### 10.3. Kiểm tra AuthorizationPolicy

Chạy:

```bash
cd k8s-cd/deploy
YAS_NAMESPACE=yas-52 POD_TTL_SECONDS=600 ./08-service-mesh-one-shot.sh
cat evidence/auth-policy-test-3.txt
```

Kỳ vọng:

| Test | Kết quả |
|---|---|
| `auth-allowed-storefront-bff -> product` | HTTP `200` |
| `auth-blocked-default -> product` | HTTP `403`, RBAC denied |

### 10.4. Kiểm tra retry policy

Kiểm tra manifest:

```bash
kubectl get virtualservice product-retry -n yas-52 -o yaml
```

Kỳ vọng thấy:

```yaml
retries:
  attempts: 3
  perTryTimeout: 3s
  retryOn: 5xx,connect-failure,refused-stream,gateway-error
```

Chạy evidence:

```bash
cat k8s-cd/deploy/evidence/retry-failure-evidence.txt
cat k8s-cd/deploy/evidence/retry-success-evidence.txt
```

Kỳ vọng:

| Test | Kết quả |
|---|---|
| `retry-test -> product actuator health` | HTTP `500`, retry exhausted |
| `retry-test -> retry-flaky` | HTTP `200` sau retry |

### 10.5. Kiểm tra Kiali

Sau khi chạy `08-service-mesh-one-shot.sh`, vào Kiali:

```text
Namespace: yas-52
Graph: Workload graph
Time range: Last 5m hoặc Last 10m
Display: Traffic, Security
```

Chụp hình khi thấy các flow:

```text
auth-allowed-storefront-bff -> product
auth-blocked-default -> product
retry-test -> product
retry-test -> retry-flaky
```

### 10.6. Kiểm tra truy cập ứng dụng từ browser

Sau khi cập nhật `/etc/hosts`, mở Storefront bằng domain của build hiện tại:

```text
http://storefront-dev-52.yas.local.com
```

**Minh chứng cần chèn**

![Storefront truy cập được sau deploy](screenshots/10-storefront-running.png)

---

## 11. Đối chiếu yêu cầu đồ án

### 11.1. Phần cơ bản

| # | Yêu cầu | Trạng thái | Bằng chứng |
|---|---|---|---|
| 1 | Mỗi service có image tag `main/latest` | Hoàn thành | GitHub Actions và Docker Hub tag |
| 2 | Kubernetes cluster 1 Master + 1 Worker hoặc Minikube | Hoàn thành | `minikube status`, `kubectl get nodes` |
| 3 | CI build image tag bằng commit ID và push Docker Hub | Hoàn thành | Workflow GitHub Actions |
| 4 | CD job chọn branch từng service, expose ra ngoài | Hoàn thành | `Jenkinsfile`, ingress host `dev-<BUILD_ID>` |
| 5 | Job xóa deployment | Hoàn thành | `Jenkinsfile-destroy` |
| 6 | Dev/Staging hoặc phần nâng cao thay thế | Chọn phần nâng cao | Istio Service Mesh |

### 11.2. Phần nâng cao Service Mesh

| # | Yêu cầu | Trạng thái | File/script |
|---|---|---|---|
| 1 | Enable mTLS giữa các service | Hoàn thành | `mtls.yaml`, `destination-rule.yaml` |
| 2 | Vẽ topology bằng Kiali | Hoàn thành | Kiali + `telemetry-monitor.yaml` + script traffic |
| 3.a | Retry khi service trả 500 | Hoàn thành | `virtual-service-retry-template.yaml`, `08-service-mesh-one-shot.sh` |
| 3.b | AuthorizationPolicy giới hạn service-to-service | Hoàn thành | `auth-policy.yaml` |
| 3.c | Test bằng curl từ pod trong cluster | Hoàn thành | Evidence trong `k8s-cd/deploy/evidence/` |

---

## 12. Danh sách screenshot cần nộp

Không cần chụp quá nhiều ảnh. Bộ 10 ảnh dưới đây là đủ gọn nhưng vẫn chứng minh đủ các yêu cầu chính của đồ án.

| # | Tên file | Đặt ở phần | Chụp gì | Chứng minh |
|---|---|---|---|---|
| 01 | `01-cluster-nodes.png` | 4.1 | Terminal có `minikube status` và `kubectl get nodes -o wide` | Kubernetes cluster chạy |
| 02 | `02-app-pods-running.png` | 4.4 | `kubectl get pod -n yas-52` và `helm list -n yas-52` | Ứng dụng đã deploy |
| 03 | `03-ci-dockerhub-tags.png` | 5.1 | Có thể ghép 2 ảnh: GitHub Actions xanh + Docker Hub tag `latest`/commit SHA | CI build và push image |
| 04 | `04-jenkins-developer-build.png` | 6.1 | Có thể ghép 2 ảnh: Jenkins parameter form + console output có `/etc/hosts` | CD job chọn branch và deploy |
| 05 | `05-jenkins-destroy.png` | 7 | Jenkins destroy console thành công | Xóa deployment |
| 06 | `06-mtls-strict.png` | 8.2 | `kubectl get peerauthentication,destinationrule -n yas-52 -o yaml` | mTLS STRICT và ISTIO_MUTUAL |
| 07 | `07-kiali-topology.png` | 8.3 | Kiali Graph namespace `yas-52`, bật Traffic/Security | Topology và mTLS lock |
| 08 | `08-retry-evidence.png` | 8.4 | `kubectl get virtualservice product-retry -n yas-52 -o yaml` + `cat evidence/retry-success-evidence.txt` | Retry policy hoạt động |
| 09 | `09-auth-policy-evidence.png` | 8.5 | `cat evidence/auth-policy-test-3.txt` thấy ALLOWED `200` và BLOCKED `403` | AuthorizationPolicy allow/deny |
| 10 | `10-storefront-running.png` | 10.5 | Browser mở `storefront-dev-52.yas.local.com` | App truy cập được từ ngoài |

Nếu muốn ít hơn nữa, có thể bỏ ảnh `05-jenkins-destroy.png` khi giáo viên không kiểm tra kỹ phần destroy bằng hình. Tuy nhiên bản 10 ảnh là cân bằng nhất.

### 12.1. Lệnh gom evidence nhanh

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

---

## 13. Kết luận

Đồ án đã xây dựng được pipeline CI/CD cho YAS trên Kubernetes và triển khai được phần Service Mesh nâng cao. Hệ thống có thể deploy bằng Jenkins hoặc script CLI, expose qua Ingress, có job destroy để dọn môi trường, và có bộ script riêng để tạo traffic/evidence cho Kiali, mTLS, AuthorizationPolicy và retry.
