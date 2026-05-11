#!/bin/bash

set -e

# Add Istio Helm repository
helm repo add istio https://istio-release.storage.googleapis.com/charts

# Update Helm repositories
helm repo update

# Create namespace for Istio control plane
kubectl create namespace istio-system \
  --dry-run=client -o yaml | kubectl apply -f -

# Install Istio CRDs + RBAC + webhook configs
helm install istio-base istio/base \
  -n istio-system \
  --wait

# Install Istiod control plane
helm install istiod istio/istiod \
  -n istio-system \
  --wait

# Verify installation
kubectl get pods -n istio-system
