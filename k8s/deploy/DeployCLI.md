# Deploy yas k8s

## 1. Cài đặt Ingress NGINX Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443
```

## 2. Triển khai Hệ thống YAS và Infrastructure

```bash
cd k8s/deploy/
./deploy-yas-configuration.sh
./setup-cluster.sh
./setup-redis.sh
./setup-keycloak.sh
./deploy-yas-applications.sh
```

## 3. Cấu hình Local DNS (Mapping Domain)

```bash
# Kiểm tra IP của Node
kubectl get nodes -o wide

# Thêm cấu hình vào file hosts
sudo nano /etc/hosts
```

*Thêm nội dung sau vào file `/etc/hosts`:*

```text
192.168.56.101 pgoperator.yas.local.com
192.168.56.101 pgadmin.yas.local.com
192.168.56.101 akhq.yas.local.com
192.168.56.101 kibana.yas.local.com
192.168.56.101 identity.yas.local.com
192.168.56.101 backoffice.yas.local.com
192.168.56.101 storefront.yas.local.com
192.168.56.101 grafana.yas.local.com
192.168.56.101 api.yas.local.com
```

### 4. Gỡ bỏ Hệ thống (Teardown & Cleanup)

```bash
# 1. Xóa các ứng dụng bằng Helm một cách an toàn (tránh lỗi nếu namespace trống)
NAMESPACES="yas postgres elasticsearch kafka keycloak observability zookeeper redis ingress-nginx cert-manager"
for ns in $NAMESPACES; do
  helm list -n $ns -q | xargs -r helm uninstall -n $ns
done

# 2. Xóa các Custom Resource Definitions (CRDs)
kubectl delete crd $(kubectl get crd -o name | grep -E "zalan.do|strimzi|elastic|keycloak|cert-manager|opentelemetry")

# 3. Xóa toàn bộ dữ liệu (Persistent Volume Claims) TRƯỚC KHI xóa namespace
kubectl delete pvc --all -A

# 4. Xóa các Namespaces (Bước này sẽ quét sạch các ConfigMap, Secret, Service còn sót lại)
kubectl delete ns $NAMESPACES --ignore-not-found=true

# 5. (Tùy chọn) Xóa bỏ các Persistent Volumes (PV) bị mồ côi nếu StorageClass không tự dọn
kubectl delete pv --all
```
