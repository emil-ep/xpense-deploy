#!/bin/bash

# Xpense Tracker Application Info Script
# Displays installation details and access URLs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Xpense Tracker Application Info${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if namespace exists
if ! kubectl get namespace xpense &> /dev/null; then
    echo -e "${RED}Error: xpense namespace not found${NC}"
    echo "The application may not be installed yet."
    echo "Run ./install.sh to install the application."
    exit 1
fi

# Get node IP
NODE_IP=$(kubectl get nodes \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
  2>/dev/null || echo "localhost")

# Get NodePorts
FRONTEND_NODEPORT=$(kubectl get svc xpense-tracker-frontend -n xpense \
  -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
BACKEND_ACTIVE_NODEPORT=$(kubectl get svc xpense-tracker-backend-active -n xpense \
  -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
BACKEND_PREVIEW_NODEPORT=$(kubectl get svc xpense-tracker-backend-preview -n xpense \
  -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")

# Get the API URL the frontend is currently configured to use
CURRENT_API_URL=$(kubectl get configmap xpense-frontend-config -n xpense \
  -o jsonpath='{.data.REACT_APP_API_BASE_URL}' 2>/dev/null || echo "N/A")

# Display access URLs
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                        ║${NC}"
echo -e "${GREEN}║  🌐  Access the Xpense Tracker Application:           ║${NC}"
echo -e "${GREEN}║                                                        ║${NC}"
if [ "$FRONTEND_NODEPORT" != "N/A" ]; then
    printf "${GREEN}║  Frontend:         ${YELLOW}%-38s${GREEN}║${NC}\n" "http://${NODE_IP}:${FRONTEND_NODEPORT}"
else
    printf "${GREEN}║  Frontend:         ${RED}%-38s${GREEN}║${NC}\n" "service not found"
fi
if [ "$BACKEND_ACTIVE_NODEPORT" != "N/A" ]; then
    printf "${GREEN}║  Backend (active): ${YELLOW}%-38s${GREEN}║${NC}\n" "http://${NODE_IP}:${BACKEND_ACTIVE_NODEPORT}"
else
    printf "${GREEN}║  Backend (active): ${RED}%-38s${GREEN}║${NC}\n" "ClusterIP — not externally reachable"
fi
if [ "$BACKEND_PREVIEW_NODEPORT" != "N/A" ]; then
    printf "${GREEN}║  Backend (preview):${YELLOW}%-38s${GREEN}║${NC}\n" "http://${NODE_IP}:${BACKEND_PREVIEW_NODEPORT}"
else
    printf "${GREEN}║  Backend (preview):${RED}%-38s${GREEN}║${NC}\n" "ClusterIP — not externally reachable"
fi
echo -e "${GREEN}║                                                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}Frontend API URL (from configmap):${NC} ${YELLOW}${CURRENT_API_URL}${NC}"
echo ""

# Pod Status
echo -e "${CYAN}Pod Status:${NC}"
echo "----------------------------"
kubectl get pods -n xpense -o wide 2>/dev/null || echo "No pods found"
echo ""

# Backend Rollout Status
echo -e "${CYAN}Backend Rollout Status:${NC}"
echo "----------------------------"
kubectl get rollout xpense-tracker-backend -n xpense 2>/dev/null || echo "No rollout found"
echo ""

# Service Information
echo -e "${CYAN}Services:${NC}"
echo "----------------------------"
kubectl get svc -n xpense 2>/dev/null || echo "No services found"
echo ""

# ArgoCD Application Status (if exists)
if kubectl get application xpense-tracker -n argocd &> /dev/null 2>&1; then
    echo -e "${CYAN}ArgoCD Application:${NC}"
    echo "----------------------------"
    SYNC_STATUS=$(kubectl get application xpense-tracker -n argocd \
      -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
    HEALTH_STATUS=$(kubectl get application xpense-tracker -n argocd \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    echo -e "Sync Status:   ${YELLOW}${SYNC_STATUS}${NC}"
    echo -e "Health Status: ${YELLOW}${HEALTH_STATUS}${NC}"
    echo ""
fi

# Useful Commands
echo -e "${CYAN}Useful Commands:${NC}"
echo "----------------------------"
echo "  View pods:              kubectl get pods -n xpense"
echo "  View services:          kubectl get svc -n xpense"
echo "  View rollout:           kubectl get rollout xpense-tracker-backend -n xpense"
echo "  Watch rollout:          kubectl argo rollouts get rollout xpense-tracker-backend -n xpense --watch"
echo "  Logs (frontend):        kubectl logs -f deployment/xpense-tracker-frontend -n xpense"
echo "  Logs (backend):         kubectl logs -f -l app=xpense-tracker-backend -n xpense"
echo "  Restart frontend:       kubectl rollout restart deployment/xpense-tracker-frontend -n xpense"
echo "  Restart backend:        kubectl patch rollout xpense-tracker-backend -n xpense --type merge -p '{\"spec\":{\"restartAt\":\"'\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"'\"}}'"
echo "  ArgoCD UI:              kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Uninstall:              ./uninstall.sh"
echo ""

echo -e "${GREEN}For more details, check the documentation in ARGOCD-ROLLOUTS-SETUP.md${NC}"
echo ""
