# ArgoCD Application & Argo Rollouts Setup Guide

## Overview

This guide provides step-by-step instructions to:
1. Install and configure ArgoCD
2. Install Argo Rollouts
3. Deploy the xpense-tracker application using ArgoCD
4. Manage blue-green deployments with Argo Rollouts

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         ArgoCD                              │
│  ┌──────────────┐         ┌─────────────────────┐         │
│  │   ArgoCD     │ Syncs   │  GitHub Repository  │         │
│  │ Application  │────────▶│  (xpense-deploy)    │         │
│  └──────────────┘         └─────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    │ Deploys to
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (xpense namespace)          │
│                                                             │
│  ┌──────────────────┐  ┌──────────────────┐               │
│  │ Backend Rollout  │  │    Frontend      │               │
│  │  (Blue-Green)    │  │   Deployment     │               │
│  └────────┬─────────┘  └──────────────────┘               │
│           │                                                 │
│  ┌────────┴─────────┐                                      │
│  │                  │                                      │
│  ▼                  ▼                                      │
│ Active Service   Preview Service                           │
│ (Production)     (Testing)                                 │
│                                                             │
│  ┌──────────────────┐                                      │
│  │   PostgreSQL     │                                      │
│  └──────────────────┘                                      │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ Managed by
                    ▼
        ┌───────────────────────┐
        │  Argo Rollouts        │
        │  Controller           │
        └───────────────────────┘
```

## Prerequisites

- Kubernetes cluster (v1.19+)
- `kubectl` CLI installed and configured
- `git` installed
- Access to your GitHub repository

---

## Part 1: Install ArgoCD

### Step 1: Create ArgoCD Namespace

```bash
kubectl create namespace argocd
```

### Step 2: Install ArgoCD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Step 3: Wait for ArgoCD Pods to be Ready

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

### Step 4: Access ArgoCD UI

**Option A: Port Forward (for local access)**
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Access at: https://localhost:8080

**Option B: Expose via LoadBalancer (for cloud)**
```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

### Step 5: Get Initial Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

**Login credentials:**
- Username: `admin`
- Password: (output from above command)

### Step 6: Install ArgoCD CLI (Optional but Recommended)

**macOS:**
```bash
brew install argocd
```

**Linux:**
```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

**Windows (using PowerShell):**
```powershell
$version = (Invoke-RestMethod https://api.github.com/repos/argoproj/argo-cd/releases/latest).tag_name
$url = "https://github.com/argoproj/argo-cd/releases/download/" + $version + "/argocd-windows-amd64.exe"
$output = "argocd.exe"
Invoke-WebRequest -Uri $url -OutFile $output
```

### Step 7: Login via CLI

```bash
argocd login localhost:8080 --username admin --password <password-from-step-5> --insecure
```

---

## Part 2: Install Argo Rollouts

### Step 1: Install Argo Rollouts Controller

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

### Step 2: Verify Argo Rollouts Installation

```bash
kubectl get pods -n argo-rollouts
```

Expected output:
```
NAME                             READY   STATUS    RESTARTS   AGE
argo-rollouts-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

### Step 3: Install Argo Rollouts kubectl Plugin

**macOS:**
```bash
brew install argoproj/tap/kubectl-argo-rollouts
```

**Linux:**
```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

**Windows (using PowerShell):**
```powershell
Invoke-WebRequest -Uri "https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-windows-amd64" -OutFile kubectl-argo-rollouts.exe
```

### Step 4: Verify Plugin Installation

```bash
kubectl argo rollouts version
```

---

## Part 3: Deploy Application with ArgoCD

### Step 1: Create Application Namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

### Step 2: Create Application Secrets

Create the required secrets before deploying:

```bash
# Backend secret (update with your values)
kubectl create secret generic xpense-backend-secret \
  -n xpense \
  --from-literal=POSTGRES_PASSWORD=your-postgres-password

# PostgreSQL secret (update with your values)
kubectl create secret generic xpense-postgres-secret \
  -n xpense \
  --from-literal=POSTGRES_PASSWORD=your-postgres-password
```

### Step 3: Create ArgoCD Application

```bash
kubectl apply -f argocd/application.yaml
```

### Step 4: Verify Application Creation

```bash
# Via kubectl
kubectl get application -n argocd

# Via ArgoCD CLI
argocd app list

# Get detailed status
argocd app get xpense-tracker
```

### Step 5: Sync the Application

**Option A: Via CLI**
```bash
argocd app sync xpense-tracker
```

**Option B: Via UI**
1. Open ArgoCD UI (https://localhost:8080)
2. Click on `xpense-tracker` application
3. Click "SYNC" button
4. Click "SYNCHRONIZE"

### Step 6: Monitor Deployment

```bash
# Watch application status
argocd app get xpense-tracker --watch

# Check pods in xpense namespace
kubectl get pods -n xpense

# Check all resources
kubectl get all -n xpense
```

---

## Part 4: Working with Argo Rollouts

### View Rollout Status

```bash
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense
```

### Watch Rollout in Real-time

```bash
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense --watch
```

### Access Rollouts Dashboard (Optional)

```bash
kubectl argo rollouts dashboard
```
Access at: http://localhost:3100

---

## Part 5: Performing Blue-Green Deployment

### Step 1: Update Backend Image

Edit `k8s/backend/backend-rollout.yaml` and update the image tag:

```yaml
spec:
  template:
    spec:
      containers:
        - name: backend
          image: ghcr.io/emil-ep/xpense-backend:1.0.15  # Update version here
```

### Step 2: Commit and Push Changes

```bash
git add k8s/backend/backend-rollout.yaml
git commit -m "Update backend to version 1.0.15"
git push origin master
```

### Step 3: ArgoCD Auto-Sync

ArgoCD will automatically detect the change and sync (if auto-sync is enabled). Monitor:

```bash
argocd app get xpense-tracker --watch
```

### Step 4: Monitor Rollout Progress

```bash
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense --watch
```

You'll see:
- **Blue** (current/active) version running
- **Green** (new/preview) version being deployed

### Step 5: Test Preview Version

```bash
# Port-forward to preview service
kubectl port-forward -n xpense svc/xpense-tracker-backend-preview 8085:8085

# In another terminal, test the preview
curl http://localhost:8085/actuator/health
```

### Step 6: Promote to Active (After Testing)

```bash
kubectl argo rollouts promote xpense-tracker-backend -n xpense
```

### Step 7: Verify Promotion

```bash
# Check rollout status
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense

# Verify active service points to new version
kubectl get pods -n xpense -l app=xpense-tracker-backend
```

---

## Part 6: Rollback Procedures

### Abort Current Rollout

If issues are found during preview:

```bash
kubectl argo rollouts abort xpense-tracker-backend -n xpense
```

### Rollback to Previous Version

```bash
# Undo the rollout
kubectl argo rollouts undo xpense-tracker-backend -n xpense

# Or rollback to specific revision
kubectl argo rollouts undo xpense-tracker-backend -n xpense --to-revision=2
```

### Retry Failed Rollout

```bash
kubectl argo rollouts retry rollout xpense-tracker-backend -n xpense
```

### Restart Rollout

```bash
kubectl argo rollouts restart rollout xpense-tracker-backend -n xpense
```

---

## Part 7: Useful Commands Reference

### ArgoCD Commands

```bash
# List all applications
argocd app list

# Get application details
argocd app get xpense-tracker

# Sync application
argocd app sync xpense-tracker

# Delete application
argocd app delete xpense-tracker

# View application logs
argocd app logs xpense-tracker

# Refresh application (detect changes)
argocd app get xpense-tracker --refresh

# Hard refresh (force refresh)
argocd app get xpense-tracker --refresh --hard

# View application history
argocd app history xpense-tracker

# Rollback to previous version
argocd app rollback xpense-tracker

# Set application parameters
argocd app set xpense-tracker --parameter key=value
```

### Argo Rollouts Commands

```bash
# List all rollouts
kubectl argo rollouts list rollouts -n xpense

# Get rollout status
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense

# Watch rollout progress
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense --watch

# Promote rollout
kubectl argo rollouts promote xpense-tracker-backend -n xpense

# Abort rollout
kubectl argo rollouts abort xpense-tracker-backend -n xpense

# Restart rollout
kubectl argo rollouts restart rollout xpense-tracker-backend -n xpense

# View rollout history
kubectl argo rollouts history rollout xpense-tracker-backend -n xpense

# Undo rollout
kubectl argo rollouts undo xpense-tracker-backend -n xpense

# Set image (manual update)
kubectl argo rollouts set image xpense-tracker-backend \
  backend=ghcr.io/emil-ep/xpense-backend:1.0.16 -n xpense

# Pause rollout
kubectl argo rollouts pause xpense-tracker-backend -n xpense

# Resume rollout
kubectl argo rollouts resume xpense-tracker-backend -n xpense
```

### Kubernetes Commands

```bash
# View all resources in namespace
kubectl get all -n xpense

# View rollout resource
kubectl get rollout -n xpense

# Describe rollout
kubectl describe rollout xpense-tracker-backend -n xpense

# View services
kubectl get svc -n xpense

# View pods with labels
kubectl get pods -n xpense -l app=xpense-tracker-backend --show-labels

# View events
kubectl get events -n xpense --sort-by='.lastTimestamp'

# View logs
kubectl logs -n xpense -l app=xpense-tracker-backend --tail=50

# Follow logs
kubectl logs -n xpense -l app=xpense-tracker-backend -f

# Execute command in pod
kubectl exec -it -n xpense <pod-name> -- /bin/sh
```

---

## Part 8: Troubleshooting

### ArgoCD Application Not Syncing

```bash
# Check application status
argocd app get xpense-tracker

# View sync errors
kubectl describe application xpense-tracker -n argocd

# Force refresh
argocd app get xpense-tracker --refresh --hard

# Manual sync
argocd app sync xpense-tracker --force

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

### Rollout Stuck in Progressing State

```bash
# Check rollout events
kubectl describe rollout xpense-tracker-backend -n xpense

# Check pod status
kubectl get pods -n xpense -l app=xpense-tracker-backend

# View pod logs
kubectl logs -n xpense -l app=xpense-tracker-backend --tail=50

# Check rollout controller logs
kubectl logs -n argo-rollouts -l app.kubernetes.io/name=argo-rollouts

# Abort and retry
kubectl argo rollouts abort xpense-tracker-backend -n xpense
kubectl argo rollouts retry rollout xpense-tracker-backend -n xpense
```

### Preview Service Not Accessible

```bash
# Verify preview service exists
kubectl get svc xpense-tracker-backend-preview -n xpense

# Check service endpoints
kubectl get endpoints xpense-tracker-backend-preview -n xpense

# Verify pods are running
kubectl get pods -n xpense -l app=xpense-tracker-backend

# Describe service
kubectl describe svc xpense-tracker-backend-preview -n xpense

# Test service connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n xpense -- \
  curl http://xpense-tracker-backend-preview:8085/actuator/health
```

### Image Pull Errors

```bash
# Check pod events
kubectl describe pod <pod-name> -n xpense

# Verify image exists
docker pull ghcr.io/emil-ep/xpense-backend:1.0.14

# Check image pull secrets (if using private registry)
kubectl get secrets -n xpense
```

### Database Connection Issues

```bash
# Check PostgreSQL pod
kubectl get pods -n xpense -l app=postgres

# View PostgreSQL logs
kubectl logs -n xpense -l app=postgres

# Test database connectivity from backend pod
kubectl exec -it -n xpense <backend-pod-name> -- \
  curl -v telnet://xpense-postgres:5432

# Verify secrets
kubectl get secret xpense-backend-secret -n xpense -o yaml
kubectl get secret xpense-postgres-secret -n xpense -o yaml
```

---

## Configuration Details

### ArgoCD Application Configuration

File: `argocd/application.yaml`

- **Application Name**: xpense-tracker
- **Repository**: https://github.com/emil-ep/xpense-deploy
- **Branch**: master
- **Path**: k8s
- **Destination Namespace**: xpense
- **Auto-sync**: Enabled
- **Self-heal**: Enabled
- **Prune**: Enabled (removes resources deleted from Git)

### Rollout Configuration

File: `k8s/backend/backend-rollout.yaml`

- **Strategy**: Blue-Green
- **Replicas**: 1
- **Auto-promotion**: Disabled (manual approval required)
- **Scale-down delay**: 30 seconds
- **Revision history**: 2 revisions kept
- **Active Service**: xpense-tracker-backend-active
- **Preview Service**: xpense-tracker-backend-preview

### Services

1. **xpense-tracker-backend-active**
   - Production traffic
   - Points to stable/active version
   - Used by frontend

2. **xpense-tracker-backend-preview**
   - Testing new version
   - Points to preview/green version
   - Used for validation before promotion

3. **xpense-tracker-backend**
   - Generic service
   - Kept for compatibility

---

## Deployment Workflow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Developer Updates Image Tag in backend-rollout.yaml     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Git Commit & Push to master branch                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. ArgoCD Detects Change & Auto-Syncs                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Argo Rollouts Creates New Pods (Green)                  │
│    - Blue (old) version still serving traffic               │
│    - Green (new) version available on preview service       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Test Preview Version                                     │
│    kubectl port-forward svc/...-preview 8085:8085          │
│    curl http://localhost:8085/actuator/health              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Manual Promotion Decision                                │
│    ├─ Tests Pass: kubectl argo rollouts promote ...        │
│    └─ Tests Fail: kubectl argo rollouts abort ...          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. Active Service Switches to Green                         │
│    - Production traffic now on new version                  │
│    - Blue version scaled down after 30 seconds              │
└─────────────────────────────────────────────────────────────┘
```

---

## Best Practices

### 1. Testing Strategy
- Always test preview version thoroughly before promotion
- Run smoke tests on preview service
- Monitor metrics (CPU, memory, error rates)
- Test critical user flows

### 2. Version Management
- Use semantic versioning for image tags (e.g., 1.0.14)
- Never use `latest` tag in production
- Tag images with Git commit SHA for traceability
- Keep revision history for quick rollbacks

### 3. Monitoring & Observability
- Set up alerts for failed rollouts
- Monitor application metrics during deployment
- Use ArgoCD notifications for deployment events
- Log all promotion decisions

### 4. Security
- Use secrets management (Sealed Secrets, External Secrets)
- Never commit secrets to Git
- Regularly rotate credentials
- Use RBAC for ArgoCD access control

### 5. Git Workflow
- Use feature branches for changes
- Require PR reviews before merging to master
- Document changes in commit messages
- Tag releases in Git

### 6. Backup & Recovery
- Regular backups of ArgoCD configuration
- Export application manifests periodically
- Document rollback procedures
- Test disaster recovery scenarios

### 7. Performance
- Set appropriate resource limits
- Use horizontal pod autoscaling when needed
- Monitor database connection pools
- Optimize container images

---

## Quick Start Checklist

Use this checklist for initial setup:

- [ ] Install ArgoCD in cluster
- [ ] Access ArgoCD UI and change admin password
- [ ] Install ArgoCD CLI
- [ ] Install Argo Rollouts controller
- [ ] Install Argo Rollouts kubectl plugin
- [ ] Create application namespace
- [ ] Create required secrets
- [ ] Apply ArgoCD application manifest
- [ ] Verify application sync
- [ ] Test preview service access
- [ ] Perform first blue-green deployment
- [ ] Document custom configurations

---

## Environment-Specific Configurations

### Development Environment

```bash
# Use shorter scale-down delay
scaleDownDelaySeconds: 10

# Enable auto-promotion for faster iteration
autoPromotionEnabled: true
```

### Staging Environment

```bash
# Moderate scale-down delay
scaleDownDelaySeconds: 30

# Manual promotion with automated tests
autoPromotionEnabled: false
```

### Production Environment

```bash
# Longer scale-down delay for safety
scaleDownDelaySeconds: 60

# Always require manual promotion
autoPromotionEnabled: false

# Increase replicas
replicas: 3
```

---

## Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Backend Rollout Details](k8s/backend/ROLLOUT-README.md)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GitOps Principles](https://www.gitops.tech/)

---

## Support & Contribution

For issues or questions:
1. Check the troubleshooting section above
2. Review ArgoCD/Argo Rollouts documentation
3. Check application logs and events
4. Create an issue in the repository

---

## License

This project follows the same license as the main xpense-tracker application.

---

**Last Updated**: 2026-04-24
**Version**: 1.0.0