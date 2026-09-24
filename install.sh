#!/bin/bash

# Xpense Tracker Application Installation Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Xpense Tracker Installer${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
echo -e "${GREEN}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi
echo "  ✓ kubectl found"

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
echo "  ✓ Kubernetes cluster accessible"

if ! kubectl get namespace argocd &> /dev/null; then
    echo -e "${RED}Error: ArgoCD is not installed. Install ArgoCD before running this script.${NC}"
    echo "  See: https://argo-cd.readthedocs.io/en/stable/getting_started/"
    exit 1
fi
echo "  ✓ ArgoCD found"

if ! kubectl get namespace argo-rollouts &> /dev/null; then
    echo -e "${RED}Error: Argo Rollouts is not installed. Install Argo Rollouts before running this script.${NC}"
    echo "  See: https://argoproj.github.io/argo-rollouts/installation/"
    exit 1
fi
echo "  ✓ Argo Rollouts found"

echo ""

# ── Step 1: Collect secrets ───────────────────────────────────────────────────
echo -e "${GREEN}Step 1: Configuring Application Secrets${NC}"
echo "--------------------------------------"
echo ""

# ── PostgreSQL ────────────────────────────────────────────────────────────────
read -sp "Enter PostgreSQL password (for xpense_admin): " POSTGRES_PASSWORD
echo ""
read -sp "Confirm PostgreSQL password: " POSTGRES_PASSWORD_CONFIRM
echo ""

if [ "$POSTGRES_PASSWORD" != "$POSTGRES_PASSWORD_CONFIRM" ]; then
    echo -e "${RED}Error: Passwords do not match${NC}"
    exit 1
fi
if [ -z "$POSTGRES_PASSWORD" ]; then
    echo -e "${RED}Error: Password cannot be empty${NC}"
    exit 1
fi

# ── JWT signing key ───────────────────────────────────────────────────────────
echo ""
read -sp "Enter JWT signing key (base64-encoded, min 32 bytes) — leave blank to auto-generate: " JWT_SIGNING_KEY
echo ""

if [ -z "$JWT_SIGNING_KEY" ]; then
    echo -e "${YELLOW}No JWT key provided — generating a random one...${NC}"
    JWT_SIGNING_KEY=$(openssl rand -hex 32 | tr -d '\n' | base64 | tr -d '\n')
    echo -e "${YELLOW}Generated JWT key (save this — needed if you redeploy): ${JWT_SIGNING_KEY}${NC}"
fi

# ── Internal service credentials ──────────────────────────────────────────────
echo ""
read -sp "Enter internal service username [service]: " INTERNAL_USERNAME
echo ""
INTERNAL_USERNAME=${INTERNAL_USERNAME:-service}

read -sp "Enter internal service password [service]: " INTERNAL_PASSWORD
echo ""
INTERNAL_PASSWORD=${INTERNAL_PASSWORD:-service}

# ── Instana APM ───────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Instana APM Configuration${NC}"
echo "  Required for blue-green promotion health analysis (AnalysisTemplate)."
echo ""
read -sp "Enter Instana API token: " INSTANA_API_TOKEN
echo ""
read -p "Enter Instana tenant URL (e.g. https://mytenant.instana.io): " INSTANA_HOST
read -p "Enter Kubernetes cluster name (as it appears in Instana): " INSTANA_CLUSTER_NAME

echo ""

# ── Step 2: Create namespace ──────────────────────────────────────────────────
echo -e "${GREEN}Step 2: Creating Namespace${NC}"
echo "--------------------------"
echo ""

echo "Creating xpense namespace..."
kubectl apply -f k8s/namespace.yaml

# Delete the Kafka PVC if it already exists so Kafka starts with a clean
# data directory. The kafka-deployment.yaml pins CLUSTER_ID, so Kafka will
# re-format the volume with the same ID on every fresh install rather than
# crashing with "cluster.id mismatch" from a previous installation.
if kubectl get pvc kafka-data -n xpense &> /dev/null; then
    echo "Removing stale Kafka PVC (kafka-data)..."
    kubectl delete pvc kafka-data -n xpense --wait=true
fi

echo ""

# ── Step 3: Create application secrets ───────────────────────────────────────
# Use `kubectl create ... | kubectl replace -f -` (not apply) so that the full
# secret is always written regardless of what is currently on the cluster.
# `kubectl apply` does a strategic merge and can silently lose keys if the
# resource already exists with data:{} (e.g. written by a prior ArgoCD sync).
echo -e "${GREEN}Step 3: Creating Application Secrets${NC}"
echo "-------------------------------------"
echo ""

apply_secret() {
    # $@ — all arguments forwarded to `kubectl create secret generic`
    # Tries replace first (resource exists); falls back to create (fresh install).
    kubectl create secret generic "$@" --dry-run=client -o yaml \
        | kubectl replace -f - 2>/dev/null \
        || kubectl create secret generic "$@"
}

echo "Creating PostgreSQL secret..."
apply_secret postgres-secret \
  -n xpense \
  --from-literal=POSTGRES_USER="xpense_admin" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB="xpense_tracker"

echo "Creating backend secret..."
apply_secret xpense-backend-secret \
  -n xpense \
  --from-literal=TRACKER_DATASOURCE_USERNAME="xpense_admin" \
  --from-literal=TRACKER_DATASOURCE_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=MF_DATASOURCE_USERNAME="xpense_admin" \
  --from-literal=MF_DATASOURCE_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=INTERNAL_SERVICE_USERNAME="${INTERNAL_USERNAME}" \
  --from-literal=INTERNAL_SERVICE_PASSWORD="${INTERNAL_PASSWORD}" \
  --from-literal=TOKEN_SIGNING_KEY="${JWT_SIGNING_KEY}"

echo "Creating scheduler secret..."
apply_secret xpense-scheduler-secret \
  -n xpense \
  --from-literal=TRACKER_DATASOURCE_USERNAME="xpense_admin" \
  --from-literal=TRACKER_DATASOURCE_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=MF_DATASOURCE_USERNAME="xpense_admin" \
  --from-literal=MF_DATASOURCE_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=TRACKER_SERVICE_USERNAME="${INTERNAL_USERNAME}" \
  --from-literal=TRACKER_SERVICE_PASSWORD="${INTERNAL_PASSWORD}"

echo "Creating consumer secret..."
apply_secret xpense-consumer-secret \
  -n xpense \
  --from-literal=MF_DATASOURCE_USERNAME="xpense_admin" \
  --from-literal=MF_DATASOURCE_PASSWORD="${POSTGRES_PASSWORD}"

# Verify the Postgres secret was written correctly before going further.
# An empty POSTGRES_PASSWORD causes the container to refuse to start.
PG_PW_CHECK=$(kubectl get secret postgres-secret -n xpense \
    -o jsonpath='{.data.POSTGRES_PASSWORD}' 2>/dev/null || true)
if [ -z "$PG_PW_CHECK" ]; then
    echo -e "${RED}Error: postgres-secret is missing POSTGRES_PASSWORD — aborting.${NC}"
    echo "This usually means the 'kubectl create secret' step failed silently."
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Application secrets created${NC}"
echo ""

# ── Step 4: Create Instana secrets ────────────────────────────────────────────
echo -e "${GREEN}Step 4: Creating Instana Secrets${NC}"
echo "--------------------------------"
echo ""

# instana-credentials — used by the AnalysisTemplate in the xpense namespace
# to supply the tenant host and cluster name to the Instana metrics provider.
echo "Creating instana-credentials secret (xpense namespace)..."
apply_secret instana-credentials \
  -n xpense \
  --from-literal=host="${INSTANA_HOST}" \
  --from-literal=clusterName="${INSTANA_CLUSTER_NAME}"

# instana-api-token — injected as INSTANA_API_TOKEN env var into the
# argo-rollouts controller so the Instana metrics provider plugin can
# authenticate to the Instana REST API during promotion analysis.
echo "Creating instana-api-token secret (argo-rollouts namespace)..."
apply_secret instana-api-token \
  -n argo-rollouts \
  --from-literal=INSTANA_API_TOKEN="${INSTANA_API_TOKEN}"

echo "Patching argo-rollouts controller to inject INSTANA_API_TOKEN..."
kubectl patch deployment argo-rollouts \
  -n argo-rollouts \
  --type=json \
  -p='[{
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "INSTANA_API_TOKEN",
      "valueFrom": {
        "secretKeyRef": {
          "name": "instana-api-token",
          "key": "INSTANA_API_TOKEN"
        }
      }
    }
  }]' 2>/dev/null || \
kubectl patch deployment argo-rollouts \
  -n argo-rollouts \
  --type=merge \
  -p='{"spec":{"template":{"spec":{"containers":[{"name":"argo-rollouts","env":[{"name":"INSTANA_API_TOKEN","valueFrom":{"secretKeyRef":{"name":"instana-api-token","key":"INSTANA_API_TOKEN"}}}]}]}}}}'

echo ""
echo -e "${GREEN}✓ Instana secrets created${NC}"
echo ""

# ── Step 5: Deploy via ArgoCD ─────────────────────────────────────────────────
echo -e "${GREEN}Step 5: Deploying Application via ArgoCD${NC}"
echo "---------------------------------------"
echo ""

echo "Creating ArgoCD application..."
kubectl apply -f argocd/application.yaml

echo ""
echo -e "${GREEN}✓ ArgoCD Application created${NC}"
echo ""

echo "Waiting for ArgoCD to sync (this may take 1-2 minutes)..."
sleep 5

for i in {1..60}; do
    SYNC_STATUS=$(kubectl get application xpense-tracker -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    if [ "$SYNC_STATUS" = "Synced" ]; then
        echo -e "${GREEN}✓ Application synced successfully${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# ── Step 6: Wait for pods ─────────────────────────────────────────────────────
echo -e "${GREEN}Step 6: Waiting for Pods to be Ready${NC}"
echo "-----------------------------------"
echo ""

echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n xpense --timeout=180s 2>/dev/null || true

echo "Waiting for Kafka to be ready..."
kubectl wait --for=condition=ready pod -l app=kafka -n xpense --timeout=180s 2>/dev/null || true

echo "Waiting for backend to be ready..."
kubectl wait --for=condition=ready pod -l app=xpense-tracker-backend -n xpense --timeout=180s 2>/dev/null || true

echo "Waiting for frontend to be ready..."
kubectl wait --for=condition=ready pod -l app=xpense-tracker-frontend -n xpense --timeout=180s 2>/dev/null || true

echo ""
echo -e "${GREEN}✓ All pods are ready${NC}"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
INGRESS_HOST=$(kubectl get ingress xpense-ingress -n xpense -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "xpense.local")
FRONTEND_NODEPORT=$(kubectl get svc xpense-tracker-frontend -n xpense -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
BACKEND_ACTIVE_NODEPORT=$(kubectl get svc xpense-tracker-backend-active -n xpense -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
BACKEND_PREVIEW_NODEPORT=$(kubectl get svc xpense-tracker-backend-preview -n xpense -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Installation Complete! 🎉${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Access URLs:${NC}"
echo ""
echo "  Via Ingress (if configured):"
echo "    Application: http://${INGRESS_HOST}/"
echo ""
echo "  Via NodePort:"
echo "    Frontend:          http://${NODE_IP}:${FRONTEND_NODEPORT}"
echo "    Backend (Active):  http://${NODE_IP}:${BACKEND_ACTIVE_NODEPORT}"
echo "    Backend (Preview): http://${NODE_IP}:${BACKEND_PREVIEW_NODEPORT}"
echo ""
echo -e "${GREEN}ArgoCD:${NC}"
echo "  Application: kubectl get application xpense-tracker -n argocd"
echo "  UI Access:   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  URL:         https://localhost:8080"
echo ""
echo -e "${GREEN}Argo Rollouts:${NC}"
echo "  View rollout:  kubectl argo rollouts get rollout xpense-tracker-backend -n xpense"
echo "  Watch rollout: kubectl argo rollouts get rollout xpense-tracker-backend -n xpense --watch"
echo "  Dashboard:     kubectl argo rollouts dashboard"
echo ""
echo -e "${GREEN}Useful Commands:${NC}"
echo "  View pods:           kubectl get pods -n xpense"
echo "  View all resources:  kubectl get all -n xpense"
echo "  View logs:           kubectl logs -f <pod-name> -n xpense"
echo "  Uninstall:           ./uninstall.sh"
echo ""
echo -e "${YELLOW}Note:${NC} If using Ingress, add '${INGRESS_HOST}' to your /etc/hosts file:"
echo "  echo \"${NODE_IP} ${INGRESS_HOST}\" | sudo tee -a /etc/hosts"
echo ""
echo -e "${YELLOW}For detailed documentation, see: ARGOCD-ROLLOUTS-SETUP.md${NC}"
