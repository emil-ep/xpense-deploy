#!/bin/bash

# Xpense Tracker Application Uninstallation Script
# This script removes the application and optionally ArgoCD and Argo Rollouts

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

# Check what's installed
APP_INSTALLED=false
ARGOCD_INSTALLED=false
ROLLOUTS_INSTALLED=false

if kubectl get namespace xpense &> /dev/null; then
    APP_INSTALLED=true
    echo -e "${YELLOW}Xpense application is installed${NC}"
fi

if kubectl get namespace argocd &> /dev/null; then
    ARGOCD_INSTALLED=true
    echo -e "${YELLOW}ArgoCD is installed${NC}"
fi

if kubectl get namespace argo-rollouts &> /dev/null; then
    ROLLOUTS_INSTALLED=true
    echo -e "${YELLOW}Argo Rollouts is installed${NC}"
fi

if [ "$APP_INSTALLED" = false ] && [ "$ARGOCD_INSTALLED" = false ] && [ "$ROLLOUTS_INSTALLED" = false ]; then
    echo -e "${GREEN}Nothing to uninstall. System is clean.${NC}"
    exit 0
fi

echo ""

# Ask what to uninstall
echo -e "${YELLOW}Uninstallation Options:${NC}"
echo "  1) Remove Application only (keep ArgoCD and Argo Rollouts)"
echo "  2) Remove Application and ArgoCD (keep Argo Rollouts)"
echo "  3) Remove Application and Argo Rollouts (keep ArgoCD)"
echo "  4) Remove everything (Application + ArgoCD + Argo Rollouts)"
echo "  5) Remove ArgoCD only"
echo "  6) Remove Argo Rollouts only"
echo ""
read -p "Choose uninstallation option (1-6) [1]: " UNINSTALL_OPTION
UNINSTALL_OPTION=${UNINSTALL_OPTION:-1}

echo ""

# Confirmation
echo -e "${RED}WARNING: This action cannot be undone!${NC}"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Uninstallation cancelled.${NC}"
    exit 0
fi

echo ""

# Step 1: Remove Application
if [ "$UNINSTALL_OPTION" = "1" ] || [ "$UNINSTALL_OPTION" = "2" ] || [ "$UNINSTALL_OPTION" = "3" ] || [ "$UNINSTALL_OPTION" = "4" ]; then
    if [ "$APP_INSTALLED" = true ]; then
        echo -e "${GREEN}Step 1: Removing Xpense Application${NC}"
        echo "----------------------------------"
        echo ""
        
        # Remove ArgoCD application if it exists
        if kubectl get application xpense-tracker -n argocd &> /dev/null; then
            echo "Removing ArgoCD application..."
            kubectl delete application xpense-tracker -n argocd
            echo "  ✓ ArgoCD application removed"
        fi
        
        # Remove all resources in xpense namespace
        echo "Removing xpense namespace and all resources..."
        kubectl delete namespace xpense --timeout=120s
        
        echo ""
        echo -e "${GREEN}✓ Application removed successfully${NC}"
        echo ""
    else
        echo -e "${YELLOW}Application not installed, skipping...${NC}"
        echo ""
    fi
fi

# Step 2: Remove ArgoCD
if [ "$UNINSTALL_OPTION" = "2" ] || [ "$UNINSTALL_OPTION" = "4" ] || [ "$UNINSTALL_OPTION" = "5" ]; then
    if [ "$ARGOCD_INSTALLED" = true ]; then
        echo -e "${GREEN}Step 2: Removing ArgoCD${NC}"
        echo "---------------------"
        echo ""
        
        echo "Removing ArgoCD resources..."
        kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>/dev/null || true
        
        echo "Removing ArgoCD namespace..."
        kubectl delete namespace argocd --timeout=120s
        
        echo ""
        echo -e "${GREEN}✓ ArgoCD removed successfully${NC}"
        echo ""
    else
        echo -e "${YELLOW}ArgoCD not installed, skipping...${NC}"
        echo ""
    fi
fi

# Step 3: Remove Argo Rollouts
if [ "$UNINSTALL_OPTION" = "3" ] || [ "$UNINSTALL_OPTION" = "4" ] || [ "$UNINSTALL_OPTION" = "6" ]; then
    if [ "$ROLLOUTS_INSTALLED" = true ]; then
        echo -e "${GREEN}Step 3: Removing Argo Rollouts${NC}"
        echo "----------------------------"
        echo ""
        
        echo "Removing Argo Rollouts resources..."
        kubectl delete -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml 2>/dev/null || true
        
        echo "Removing Argo Rollouts namespace..."
        kubectl delete namespace argo-rollouts --timeout=120s
        
        echo ""
        echo -e "${GREEN}✓ Argo Rollouts removed successfully${NC}"
        echo ""
    else
        echo -e "${YELLOW}Argo Rollouts not installed, skipping...${NC}"
        echo ""
    fi
fi

# Display final information
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Uninstallation Complete! ✓${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${GREEN}Summary:${NC}"
echo ""

if [ "$UNINSTALL_OPTION" = "1" ] || [ "$UNINSTALL_OPTION" = "2" ] || [ "$UNINSTALL_OPTION" = "3" ] || [ "$UNINSTALL_OPTION" = "4" ]; then
    if [ "$APP_INSTALLED" = true ]; then
        echo "  ✓ Xpense application removed"
    fi
fi

if [ "$UNINSTALL_OPTION" = "2" ] || [ "$UNINSTALL_OPTION" = "4" ] || [ "$UNINSTALL_OPTION" = "5" ]; then
    if [ "$ARGOCD_INSTALLED" = true ]; then
        echo "  ✓ ArgoCD removed"
    fi
fi

if [ "$UNINSTALL_OPTION" = "3" ] || [ "$UNINSTALL_OPTION" = "4" ] || [ "$UNINSTALL_OPTION" = "6" ]; then
    if [ "$ROLLOUTS_INSTALLED" = true ]; then
        echo "  ✓ Argo Rollouts removed"
    fi
fi

echo ""

# Check what remains
REMAINING=false

if [ "$UNINSTALL_OPTION" != "4" ] && [ "$UNINSTALL_OPTION" != "5" ]; then
    if kubectl get namespace argocd &> /dev/null; then
        echo -e "${YELLOW}ArgoCD is still installed${NC}"
        REMAINING=true
    fi
fi

if [ "$UNINSTALL_OPTION" != "4" ] && [ "$UNINSTALL_OPTION" != "6" ]; then
    if kubectl get namespace argo-rollouts &> /dev/null; then
        echo -e "${YELLOW}Argo Rollouts is still installed${NC}"
        REMAINING=true
    fi
fi

if [ "$REMAINING" = true ]; then
    echo ""
    echo -e "${YELLOW}To remove remaining components, run ./uninstall.sh again${NC}"
fi

echo ""
echo -e "${GREEN}Uninstallation completed successfully!${NC}"
echo ""
echo -e "${YELLOW}To reinstall, run: ./install.sh${NC}"
