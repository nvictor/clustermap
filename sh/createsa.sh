#!/usr/bin/env bash
set -euo pipefail

SA_NAME="clustermap-admin"
NAMESPACE="kube-system"

echo "📌 Creating service account '$SA_NAME' in namespace '$NAMESPACE'..."
kubectl create serviceaccount "$SA_NAME" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "📌 Binding cluster-admin role..."
kubectl create clusterrolebinding "${SA_NAME}-binding" \
  --clusterrole=cluster-admin \
  --serviceaccount="${NAMESPACE}:${SA_NAME}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "📌 Creating secret for token..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SA_NAME}-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: "${SA_NAME}"
type: kubernetes.io/service-account-token
EOF

echo "📌 Waiting for token to be created..."
sleep 2

TOKEN=$(kubectl get secret "${SA_NAME}-token" -n "${NAMESPACE}" -o jsonpath='{.data.token}' | base64 --decode)
CA_CERT=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$(kubectl config current-context | cut -d'/' -f1)\")].cluster.certificate-authority-data}")
SERVER=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$(kubectl config current-context | cut -d'/' -f1)\")].cluster.server}")

echo ""
echo "✅ Service account token created."
echo "👉 Add this to your app config:"
echo "Server: $SERVER"
echo "CA: $CA_CERT"
echo "Token: $TOKEN"
