#!/bin/bash

set -e

# Example:
# export YAS_NAMESPACE="yas-13"
# export ENV_TAG="dev-13"

if [ -z "$YAS_NAMESPACE" ]; then
  echo "YAS_NAMESPACE variable is not set"
  exit 1
fi

NAMESPACE="${YAS_NAMESPACE}"

# Create namespace
kubectl create namespace ${NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

# Enable automatic sidecar injection
kubectl label namespace ${NAMESPACE} \
  istio-injection=enabled \
  --overwrite

# Optional env label
if [ ! -z "$ENV_TAG" ]; then
  kubectl label namespace ${NAMESPACE} \
    env=${ENV_TAG} \
    --overwrite
fi

echo "Namespace ${NAMESPACE} created"
echo "Istio injection enabled"

# ---------------------------------------
# Apply PeerAuthentication dynamically
# ---------------------------------------

yq eval '
  .metadata.namespace = env(YAS_NAMESPACE)
' peer-authentication.yaml | kubectl apply -f -

echo "PeerAuthentication applied"

# ---------------------------------------
# Apply DestinationRule dynamically
# ---------------------------------------

yq eval '
  .metadata.namespace = env(YAS_NAMESPACE) |
  .spec.host = "*." + env(YAS_NAMESPACE) + ".svc.cluster.local"
' destination-rule.yaml | kubectl apply -f -

echo "DestinationRule applied"

# ---------------------------------------
# Verify resources
# ---------------------------------------

kubectl get peerauthentication -n ${NAMESPACE}

kubectl get destinationrule -n ${NAMESPACE}