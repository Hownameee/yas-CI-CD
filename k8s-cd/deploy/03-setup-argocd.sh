#!/bin/bash
set -euo pipefail
set -x

echo ">>> Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo ">>> Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 7.1.0 \
  -f ./argo/values.yaml \
  --wait

echo ">>> ArgoCD has been installed in namespace 'argocd'."
