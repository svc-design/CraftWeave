#!/bin/bash
# make_Kong_Gateway_offline_package.sh
# This script prepares all necessary resources for Kong Gateway offline installation

set -e

# Define variables
KONG_RESOURCES_DIR="kong-offline-resources"
GATEWAY_API_VERSION="v1.1.0"
KONG_GATEWAY_VERSION="3.6"  # Kong Helm chart version

# Create output directory
mkdir -p "${KONG_RESOURCES_DIR}"

echo "Downloading Gateway API CRDs..."
curl -L "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" \
  -o "${KONG_RESOURCES_DIR}/gateway-api.yaml"

echo "Creating Kong Gateway configuration YAML..."
cat > "${KONG_RESOURCES_DIR}/kong-gateway.yaml" <<EOF
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kong
  annotations:
    konghq.com/gatewayclass-unmanaged: 'true'
spec:
  controllerName: konghq.com/kic-gateway-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: kong
spec:
  gatewayClassName: kong
  listeners:
  - name: proxy
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF

echo "Creating service patch files..."
# NodePort patch
cat > "${KONG_RESOURCES_DIR}/svc-patch-nodeport.json" <<EOF
{
  "spec": {
    "type": "NodePort",
    "ports": [
      {
        "port": 80,
        "targetPort": 8000,
        "protocol": "TCP",
        "name": "http",
        "nodePort": 80
      },
      {
        "port": 443,
        "targetPort": 8443,
        "protocol": "TCP",
        "name": "https",
        "nodePort": 443
      }
    ]
  }
}
EOF

# ExternalIPs patch (IP should be replaced with actual IP during installation)
cat > "${KONG_RESOURCES_DIR}/svc-patch-externalips.json" <<EOF
{
  "spec": {
    "externalIPs": [
      "REPLACE_WITH_ACTUAL_IP"
    ]
  }
}
EOF

echo "Creating Kong installation script..."
cat > "${KONG_RESOURCES_DIR}/install-kong.sh" <<'EOF'
#!/bin/bash
# install-kong.sh
# This script installs Kong Gateway on a K3s cluster

set -e

KONG_NAMESPACE="kong"
RESOURCES_DIR="/var/lib/rancher/k3s/server/manifests/kong-resources"

echo "Installing Kong Gateway..."

# Apply Gateway API CRDs
kubectl apply -f "${RESOURCES_DIR}/gateway-api.yaml"

# Add Kong Helm repo
helm repo add kong https://charts.konghq.com
helm repo update

# Install Kong
helm upgrade --install kong kong/ingress \
  --namespace "${KONG_NAMESPACE}" \
  --create-namespace \
  --version "${KONG_GATEWAY_VERSION:-3.6}"

# Wait for Kong to be ready
echo "Waiting for Kong Gateway to be ready..."
kubectl wait --namespace "${KONG_NAMESPACE}" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=app \
  --timeout=300s

# Apply service patches
echo "Patching Kong services..."
kubectl patch svc kong-gateway-proxy \
  -n "${KONG_NAMESPACE}" \
  --type='merge' \
  -p "$(cat "${RESOURCES_DIR}/svc-patch-nodeport.json")"

# Replace placeholder IP with actual IP (if provided)
if [ -n "${EXTERNAL_IP}" ]; then
  sed "s/REPLACE_WITH_ACTUAL_IP/${EXTERNAL_IP}/" \
    "${RESOURCES_DIR}/svc-patch-externalips.json" \
    > "${RESOURCES_DIR}/svc-patch-externalips-tmp.json"

  kubectl patch svc kong-gateway-proxy \
    -n "${KONG_NAMESPACE}" \
    --type='merge' \
    -p "$(cat "${RESOURCES_DIR}/svc-patch-externalips-tmp.json")"

  rm "${RESOURCES_DIR}/svc-patch-externalips-tmp.json"
fi

# Apply Gateway configuration
kubectl apply -f "${RESOURCES_DIR}/kong-gateway.yaml"

echo "Kong Gateway installed successfully!"
echo "Kong Gateway Proxy is accessible on port 80 and 443"
EOF

# Make the script executable
chmod +x "${KONG_RESOURCES_DIR}/install-kong.sh"

echo "Creating Helm chart archive..."
helm repo add kong https://charts.konghq.com
helm repo update
helm pull kong/ingress --version "${KONG_GATEWAY_VERSION}" -d "${KONG_RESOURCES_DIR}"

echo "Kong Gateway offline package created in: ${KONG_RESOURCES_DIR}"
echo "Contents:"
tree "${KONG_RESOURCES_DIR}"

# Create tarball
tar czvf kong-offline-package.tar.gz "${KONG_RESOURCES_DIR}"

echo "Kong Gateway offline package created: kong-offline-package.tar.gz"
