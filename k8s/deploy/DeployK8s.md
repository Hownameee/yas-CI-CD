helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443

cd k8s/deploy/
./deploy-yas-configuration.sh
./setup-cluster.sh
./setup-redis.sh
./setup-keycloak.sh
./deploy-yas-applications.sh

kubectl get nodes -o wide

sudo nano /etc/hosts

192.168.56.101 pgoperator.yas.local.com
192.168.56.101 pgadmin.yas.local.com
192.168.56.101 akhq.yas.local.com
192.168.56.101 kibana.yas.local.com
192.168.56.101 identity.yas.local.com
192.168.56.101 backoffice.yas.local.com
192.168.56.101 storefront.yas.local.com
192.168.56.101 grafana.yas.local.com
192.168.56.101 api.yas.local.com



# Xóa các service của YAS và các infra đi kèm
helm uninstall -n yas $(helm list -n yas -q)
helm uninstall -n postgres $(helm list -n postgres -q)
helm uninstall -n elasticsearch $(helm list -n elasticsearch -q)
helm uninstall -n kafka $(helm list -n kafka -q)
helm uninstall -n keycloak $(helm list -n keycloak -q)
helm uninstall -n observability $(helm list -n observability -q)
helm uninstall -n zookeeper $(helm list -n zookeeper -q)
helm uninstall -n redis $(helm list -n redis -q)
helm uninstall -n ingress-nginx $(helm list -n ingress-nginx -q)
helm uninstall -n cert-manager $(helm list -n cert-manager -q)

kubectl delete crd $(kubectl get crd -o name | grep -E "zalan.do|strimzi|elastic|keycloak|cert-manager|opentelemetry")

kubectl delete ns yas postgres elasticsearch kafka keycloak observability zookeeper redis ingress-nginx cert-manager

kubectl delete pvc --all -A
