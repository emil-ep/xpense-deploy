#!/bin/bash

# Xpense Tracker Application Installation Script
# This script automates the complete installation process including ArgoCD and Argo Rollouts

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

# Check prerequisites
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

echo ""

# Check if ArgoCD is already installed
ARGOCD_INSTALLED=false
if kubectl get namespace argocd &> /dev/null; then
    ARGOCD_INSTALLED=true
    echo -e "${YELLOW}ArgoCD is already installed${NC}"
else
    echo -e "${YELLOW}ArgoCD is not installed${NC}"
fi

# Check if Argo Rollouts is already installed
ROLLOUTS_INSTALLED=false
if kubectl get namespace argo-rollouts &> /dev/null; then
    ROLLOUTS_INSTALLED=true
    echo -e "${YELLOW}Argo Rollouts is already installed${NC}"
else
    echo -e "${YELLOW}Argo Rollouts is not installed${NC}"
fi

echo ""

# Ask what to install
echo -e "${YELLOW}Installation Options:${NC}"
echo "  1) Full installation (ArgoCD + Argo Rollouts + Application)"
echo "  2) Install ArgoCD only"
echo "  3) Install Argo Rollouts only"
echo "  4) Install Application only (requires ArgoCD)"
echo ""
read -p "Choose installation option (1-4) [1]: " INSTALL_OPTION
INSTALL_OPTION=${INSTALL_OPTION:-1}

echo ""

# Step 1: Install ArgoCD
if [ "$INSTALL_OPTION" = "1" ] || [ "$INSTALL_OPTION" = "2" ]; then
    if [ "$ARGOCD_INSTALLED" = false ]; then
        echo -e "${GREEN}Step 1: Installing ArgoCD${NC}"
        echo "------------------------"
        echo ""
        
        echo "Creating ArgoCD namespace..."
        kubectl create namespace argocd
        
        echo "Installing ArgoCD..."
        kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        
        echo "Waiting for ArgoCD to be ready (this may take 1-2 minutes)..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
        
        echo ""
        echo -e "${GREEN}✓ ArgoCD installed successfully${NC}"
        
        # Get initial admin password
        ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        
        echo ""
        echo -e "${YELLOW}ArgoCD Admin Credentials:${NC}"
        echo "  Username: admin"
        echo "  Password: ${ARGOCD_PASSWORD}"
        echo ""
        echo -e "${YELLOW}Access ArgoCD UI:${NC}"
        echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
        echo "  Then open: https://localhost:8080"
        echo ""
        
        ARGOCD_INSTALLED=true
    else
        echo -e "${YELLOW}Skipping ArgoCD installation (already installed)${NC}"
        echo ""
    fi
fi

# Step 2: Install Argo Rollouts
if [ "$INSTALL_OPTION" = "1" ] || [ "$INSTALL_OPTION" = "3" ]; then
    if [ "$ROLLOUTS_INSTALLED" = false ]; then
        echo -e "${GREEN}Step 2: Installing Argo Rollouts${NC}"
        echo "-------------------------------"
        echo ""
        
        echo "Creating Argo Rollouts namespace..."
        kubectl create namespace argo-rollouts
        
        echo "Installing Argo Rollouts controller..."
        kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
        
        echo "Waiting for Argo Rollouts to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argo-rollouts -n argo-rollouts --timeout=120s
        
        echo ""
        echo -e "${GREEN}✓ Argo Rollouts installed successfully${NC}"
        echo ""
        
        ROLLOUTS_INSTALLED=true
    else
        echo -e "${YELLOW}Skipping Argo Rollouts installation (already installed)${NC}"
        echo ""
    fi
fi

# Step 3: Setup Application
if [ "$INSTALL_OPTION" = "1" ] || [ "$INSTALL_OPTION" = "4" ]; then
    if [ "$ARGOCD_INSTALLED" = false ]; then
        echo -e "${RED}Error: ArgoCD must be installed to deploy the application${NC}"
        echo "Please run the installer again and choose option 1 or 2 first."
        exit 1
    fi
    
    echo -e "${GREEN}Step 3: Configuring Application Secrets${NC}"
    echo "--------------------------------------"
    echo ""
    
    # Prompt for PostgreSQL password
    read -sp "Enter PostgreSQL password: " POSTGRES_PASSWORD
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
    
    echo ""
    
    # Step 4: Create namespace and secrets
    echo -e "${GREEN}Step 4: Creating Namespace and Secrets${NC}"
    echo "-------------------------------------"
    echo ""
    
    echo "Creating xpense namespace..."
    kubectl apply -f k8s/namespace.yaml
    
    echo "Creating backend secret..."
    kubectl create secret generic xpense-backend-secret \
      -n xpense \
      --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo "Creating PostgreSQL secret..."
    kubectl create secret generic xpense-postgres-secret \
      -n xpense \
      --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo ""
    echo -e "${GREEN}✓ Secrets created${NC}"
    echo ""
    
    # Step 5: Deploy application via ArgoCD
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
    
    # Wait for sync
    for i in {1..60}; do
        SYNC_STATUS=$(kubectl get application xpense-tracker -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        HEALTH_STATUS=$(kubectl get application xpense-tracker -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        if [ "$SYNC_STATUS" = "Synced" ]; then
            echo -e "${GREEN}✓ Application synced successfully${NC}"
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""
    
    # Step 6: Wait for pods to be ready
    echo -e "${GREEN}Step 6: Waiting for Pods to be Ready${NC}"
    echo "-----------------------------------"
    echo ""
    
    echo "Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgres -n xpense --timeout=180s 2>/dev/null || true
    
    echo "Waiting for backend to be ready..."
    kubectl wait --for=condition=ready pod -l app=xpense-tracker-backend -n xpense --timeout=180s 2>/dev/null || true
    
    echo "Waiting for frontend to be ready..."
    kubectl wait --for=condition=ready pod -l app=xpense-tracker-frontend -n xpense --timeout=180s 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}✓ All pods are ready${NC}"
    echo ""
fi

# Display final information
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Installation Complete! 🎉${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ "$INSTALL_OPTION" = "1" ] || [ "$INSTALL_OPTION" = "4" ]; then
    # Get ingress info
    INGRESS_HOST=$(kubectl get ingress xpense-ingress -n xpense -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "xpense.local")
    
    # Get NodePort info
    FRONTEND_NODEPORT=$(kubectl get svc xpense-tracker-frontend -n xpense -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    BACKEND_ACTIVE_NODEPORT=$(kubectl get svc xpense-tracker-backend-active -n xpense -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    BACKEND_PREVIEW_NODEPORT=$(kubectl get svc xpense-tracker-backend-preview -n xpense -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    
    # Get node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")
    
    echo -e "${GREEN}Access URLs:${NC}"
    echo ""
    echo "  Via Ingress (if configured):"
    echo "    Application: http://${INGRESS_HOST}/"
    echo ""
    echo "  Via NodePort:"
    echo "    Frontend:        http://${NODE_IP}:${FRONTEND_NODEPORT}"
    echo "    Backend (Active): http://${NODE_IP}:${BACKEND_ACTIVE_NODEPORT}"
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
fi

echo -e "${GREEN}Useful Commands:${NC}"
echo "  View pods:           kubectl get pods -n xpense"
echo "  View all resources:  kubectl get all -n xpense"
echo "  View logs:           kubectl logs -f <pod-name> -n xpense"
echo "  Uninstall:           ./uninstall.sh"
echo ""

if [ "$INSTALL_OPTION" = "1" ] || [ "$INSTALL_OPTION" = "4" ]; then
    echo -e "${YELLOW}Note:${NC} If using Ingress, add '${INGRESS_HOST}' to your /etc/hosts file:"
    echo "  echo \"${NODE_IP} ${INGRESS_HOST}\" | sudo tee -a /etc/hosts"
    echo ""
fi

echo -e "${GREEN}Installation completed successfully!${NC}"
echo ""
echo -e "${YELLOW}For detailed documentation, see: ARGOCD-ROLLOUTS-SETUP.md${NC}"
