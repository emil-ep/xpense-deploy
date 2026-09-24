#!/bin/bash

# Xpense Tracker Application Uninstallation Script

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
echo -e "${BLUE}  Xpense Tracker Uninstaller${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# ── Check what is installed ───────────────────────────────────────────────────
if ! kubectl get namespace xpense &> /dev/null; then
    echo -e "${GREEN}Nothing to uninstall. The xpense namespace does not exist.${NC}"
    exit 0
fi

echo -e "${YELLOW}The following will be removed:${NC}"
echo "  • ArgoCD application: xpense-tracker"
echo "  • Namespace: xpense (all application resources and secrets)"
echo ""
echo -e "${RED}WARNING: This action cannot be undone!${NC}"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Uninstallation cancelled.${NC}"
    exit 0
fi

echo ""

# ── Remove ArgoCD application ─────────────────────────────────────────────────
if kubectl get application xpense-tracker -n argocd &> /dev/null 2>&1; then
    echo "Removing ArgoCD application..."
    kubectl delete application xpense-tracker -n argocd
    echo -e "  ${GREEN}✓ ArgoCD application removed${NC}"
fi

# ── Remove xpense namespace ───────────────────────────────────────────────────
echo "Removing xpense namespace and all resources..."
kubectl delete namespace xpense --timeout=120s
echo -e "  ${GREEN}✓ xpense namespace removed${NC}"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Uninstallation Complete! ✓${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}To reinstall, run: ./install.sh${NC}"
