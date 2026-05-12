# Xpense Tracker Installation Guide

This guide provides quick installation and uninstallation instructions using the automated scripts.

## Quick Start

### Prerequisites

- Kubernetes cluster (v1.19+)
- `kubectl` CLI installed and configured
- Cluster access with appropriate permissions

### Installation

Run the installation script:

```bash
./install.sh
```

The script will guide you through the installation process with the following options:

1. **Full installation** (ArgoCD + Argo Rollouts + Application) - Recommended for new setups
2. **Install ArgoCD only** - If you only need ArgoCD
3. **Install Argo Rollouts only** - If you only need Argo Rollouts
4. **Install Application only** - If ArgoCD is already installed

### What Gets Installed

#### Option 1: Full Installation
- ArgoCD (GitOps controller)
- Argo Rollouts (Blue-Green deployment controller)
- Xpense Tracker application (Frontend, Backend, PostgreSQL)

#### During Installation
You will be prompted to:
- Choose installation option
- Enter PostgreSQL password (for database security)

### Uninstallation

Run the uninstallation script:

```bash
./uninstall.sh
```

The script provides multiple uninstallation options:

1. **Remove Application only** - Keeps ArgoCD and Argo Rollouts
2. **Remove Application and ArgoCD** - Keeps Argo Rollouts
3. **Remove Application and Argo Rollouts** - Keeps ArgoCD
4. **Remove everything** - Complete cleanup
5. **Remove ArgoCD only**
6. **Remove Argo Rollouts only**

## Installation Examples

### Example 1: Fresh Installation

```bash
# Run the installer
./install.sh

# Choose option 1 (Full installation)
# Enter PostgreSQL password when prompted
# Wait for installation to complete
```

### Example 2: Application Only (ArgoCD Already Installed)

```bash
# Run the installer
./install.sh

# Choose option 4 (Install Application only)
# Enter PostgreSQL password when prompted
```

### Example 3: Uninstall Application Only

```bash
# Run the uninstaller
./uninstall.sh

# Choose option 1 (Remove Application only)
# Confirm with 'yes'
```

## Post-Installation

### Access the Application

After successful installation, you'll see access URLs:

**Via Ingress (if configured):**
```
http://xpense.local/
```

**Via NodePort:**
```
Frontend: http://<node-ip>:<frontend-port>
Backend:  http://<node-ip>:<backend-port>
```

### Access ArgoCD UI

```bash
# Port forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open in browser
https://localhost:8080

# Login credentials
Username: admin
Password: <shown during installation>
```

### Access Argo Rollouts Dashboard

```bash
# Start the dashboard
kubectl argo rollouts dashboard

# Open in browser
http://localhost:3100
```

## Useful Commands

### Check Installation Status

```bash
# Check all pods
kubectl get pods -n xpense

# Check ArgoCD application
kubectl get application xpense-tracker -n argocd

# Check rollout status
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense
```

### View Logs

```bash
# Frontend logs
kubectl logs -f -l app=xpense-tracker-frontend -n xpense

# Backend logs
kubectl logs -f -l app=xpense-tracker-backend -n xpense

# PostgreSQL logs
kubectl logs -f -l app=postgres -n xpense
```

### Monitor Deployment

```bash
# Watch rollout progress
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense --watch

# Watch ArgoCD sync
argocd app get xpense-tracker --watch
```

## Troubleshooting

### Installation Fails

1. Check cluster connectivity:
   ```bash
   kubectl cluster-info
   ```

2. Check prerequisites:
   ```bash
   kubectl version
   ```

3. View installation logs (script output)

### Pods Not Starting

1. Check pod status:
   ```bash
   kubectl get pods -n xpense
   ```

2. Describe problematic pod:
   ```bash
   kubectl describe pod <pod-name> -n xpense
   ```

3. Check pod logs:
   ```bash
   kubectl logs <pod-name> -n xpense
   ```

### ArgoCD Not Syncing

1. Check application status:
   ```bash
   kubectl get application xpense-tracker -n argocd
   ```

2. View sync errors:
   ```bash
   kubectl describe application xpense-tracker -n argocd
   ```

3. Force sync:
   ```bash
   argocd app sync xpense-tracker --force
   ```

## Advanced Configuration

For detailed configuration and advanced deployment strategies, see:
- [ARGOCD-ROLLOUTS-SETUP.md](ARGOCD-ROLLOUTS-SETUP.md) - Complete setup guide
- [k8s/backend/ROLLOUT-README.md](k8s/backend/ROLLOUT-README.md) - Rollout configuration

## Script Features

### install.sh Features
- ✓ Prerequisite checking
- ✓ Flexible installation options
- ✓ Automatic secret creation
- ✓ Progress monitoring
- ✓ Post-installation information
- ✓ Error handling

### uninstall.sh Features
- ✓ Safe uninstallation with confirmation
- ✓ Selective component removal
- ✓ Cleanup verification
- ✓ Status reporting

## Security Notes

- PostgreSQL password is stored as Kubernetes secret
- Secrets are not committed to Git
- ArgoCD admin password is auto-generated
- Change default passwords after installation

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review [ARGOCD-ROLLOUTS-SETUP.md](ARGOCD-ROLLOUTS-SETUP.md)
3. Check pod logs and events
4. Verify cluster resources

---

**Last Updated**: 2026-05-12
