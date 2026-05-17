#!/bin/bash
set -euo pipefail

LOCAL_PORT="${LOCAL_PORT:-20001}"

echo ">>> Open Kiali at: http://localhost:$LOCAL_PORT/kiali"
echo ">>> Recommended graph settings: Namespace=yas-52, Workload graph, Last 10m, Display=Traffic/Security."
echo ">>> Press Ctrl+C to stop port-forward."
kubectl port-forward svc/kiali -n istio-system "$LOCAL_PORT:20001"
