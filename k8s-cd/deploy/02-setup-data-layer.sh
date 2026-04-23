#!/bin/bash
set -x

helm repo add akhq https://akhq.io/
helm repo update

# Read configuration value from cluster-config.yaml file
read -rd '' DOMAIN POSTGRESQL_REPLICAS POSTGRESQL_USERNAME POSTGRESQL_PASSWORD \
KAFKA_REPLICAS ZOOKEEPER_REPLICAS ELASTICSEARCH_REPLICAS REDIS_PASSWORD \
BOOTSTRAP_ADMIN_USERNAME BOOTSTRAP_ADMIN_PASSWORD \
KEYCLOAK_BACKOFFICE_REDIRECT_URL KEYCLOAK_STOREFRONT_REDIRECT_URL \
< <(yq -r '.domain, .postgresql.replicas, .postgresql.username,
 .postgresql.password, .kafka.replicas, .zookeeper.replicas,
 .elasticsearch.replicas, .redis.password,
 .keycloak.bootstrapAdmin.username, .keycloak.bootstrapAdmin.password,
 .keycloak.backofficeRedirectUrl, .keycloak.storefrontRedirectUrl' ./cluster-config.yaml)

NAMESPACE="${YAS_NAMESPACE:-yas}"

# Construct dynamic domains
if [ -n "$ENV_TAG" ]; then
  IDENTITY_HOST="identity-$ENV_TAG.$DOMAIN"
  PGADMIN_HOST="pgadmin-$ENV_TAG.$DOMAIN"
  AKHQ_HOST="akhq-$ENV_TAG.$DOMAIN"
  KIBANA_HOST="kibana-$ENV_TAG.$DOMAIN"
  BACKOFFICE_REDIRECT_URL="http://backoffice-$ENV_TAG.$DOMAIN"
  STOREFRONT_REDIRECT_URL="http://storefront-$ENV_TAG.$DOMAIN"
  API_REDIRECT_URL="http://api-$ENV_TAG.$DOMAIN"
else
  IDENTITY_HOST="identity.$DOMAIN"
  PGADMIN_HOST="pgadmin.$DOMAIN"
  AKHQ_HOST="akhq.$DOMAIN"
  KIBANA_HOST="kibana.$DOMAIN"
  BACKOFFICE_REDIRECT_URL="$KEYCLOAK_BACKOFFICE_REDIRECT_URL"
  STOREFRONT_REDIRECT_URL="$KEYCLOAK_STOREFRONT_REDIRECT_URL"
  API_REDIRECT_URL="http://api.$DOMAIN"
fi

# Create yas namespace if not exists
kubectl create namespace "$NAMESPACE" || true

# Install postgresql
helm upgrade --install postgres ./postgres/postgresql \
--namespace "$NAMESPACE" \
--set replicas="$POSTGRESQL_REPLICAS" \
--set username="$POSTGRESQL_USERNAME" \
--set password="$POSTGRESQL_PASSWORD"

# Install pgadmin
pg_admin_hostname="$PGADMIN_HOST" yq -i '.hostname=env(pg_admin_hostname)' ./postgres/pgadmin/values.yaml
helm upgrade --install pgadmin ./postgres/pgadmin \
--namespace "$NAMESPACE"

# Install zookeeper
helm upgrade --install zookeeper ./zookeeper \
 --namespace "$NAMESPACE"

# Install kafka and postgresql connector
helm upgrade --install kafka-cluster ./kafka/kafka-cluster \
--namespace "$NAMESPACE" \
--set kafka.replicas="$KAFKA_REPLICAS" \
--set zookeeper.replicas="$ZOOKEEPER_REPLICAS" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD"

# Install akhq
akhq_hostname="$AKHQ_HOST" yq -i '.hostname=env(akhq_hostname)' ./kafka/akhq.values.yaml
helm upgrade --install akhq akhq/akhq \
--namespace "$NAMESPACE" \
--values ./kafka/akhq.values.yaml

# Install elasticsearch-cluster
helm upgrade --install elasticsearch-cluster ./elasticsearch/elasticsearch-cluster \
--namespace "$NAMESPACE" \
--set elasticsearch.replicas="$ELASTICSEARCH_REPLICAS" \
--set kibana.ingress.hostname="$KIBANA_HOST"

# Install Redis
helm upgrade --install redis \
  --set auth.password="$REDIS_PASSWORD" \
  oci://registry-1.docker.io/bitnamicharts/redis -n "$NAMESPACE"

# Install Keycloak CRDs
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloaks.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/keycloakrealmimports.k8s.keycloak.org-v1.yml
kubectl apply -f https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/26.0.2/kubernetes/kubernetes.yml -n "$NAMESPACE"

# Install keycloak
helm upgrade --install keycloak ./keycloak/keycloak \
--namespace "$NAMESPACE" \
--set hostname="$IDENTITY_HOST" \
--set postgresql.username="$POSTGRESQL_USERNAME" \
--set postgresql.password="$POSTGRESQL_PASSWORD" \
--set bootstrapAdmin.username="$BOOTSTRAP_ADMIN_USERNAME" \
--set bootstrapAdmin.password="$BOOTSTRAP_ADMIN_PASSWORD" \
--set backofficeRedirectUrl="$BACKOFFICE_REDIRECT_URL" \
--set storefrontRedirectUrl="$STOREFRONT_REDIRECT_URL" \
--set apiRedirectUrl="$API_REDIRECT_URL" \
--set global.domain="$DOMAIN" \
--set global.envTag="$ENV_TAG"

echo ">>> Xong Giai đoạn 2.1: Data Instances đã được cài vào namespace '$NAMESPACE' với domain prefix '$ENV_TAG'."
