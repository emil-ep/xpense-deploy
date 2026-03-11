# Backend Blue-Green Deployment with Argo Rollouts

This backend uses Argo Rollouts for blue-green deployment strategy.

## Files

- `backend-rollout.yaml` - Argo Rollout resource (replaces backend-deployment.yaml)
- `backend-service.yaml` - Contains three services:
  - `xpense-tracker-backend-active` - Points to the active (production) version
  - `xpense-tracker-backend-preview` - Points to the preview (new) version
  - `xpense-tracker-backend` - Generic service (kept for compatibility)

## How Blue-Green Deployment Works

1. **Initial State**: Active service points to the current version (blue)
2. **New Deployment**: When you update the image, Rollout creates new pods (green)
3. **Preview**: Green version is available via preview service for testing
4. **Manual Promotion**: After testing, manually promote green to active
5. **Cleanup**: Old blue version is scaled down after promotion

## Deployment Commands

### View Rollout Status
```bash
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense
```

### Watch Rollout Progress
```bash
kubectl argo rollouts get rollout xpense-tracker-backend -n xpense --watch
```

### Promote to Active (after testing preview)
```bash
kubectl argo rollouts promote xpense-tracker-backend -n xpense
```

### Abort Rollout (if issues found)
```bash
kubectl argo rollouts abort xpense-tracker-backend -n xpense
```

### Retry Failed Rollout
```bash
kubectl argo rollouts retry rollout xpense-tracker-backend -n xpense
```

### Restart Rollout
```bash
kubectl argo rollouts restart rollout xpense-tracker-backend -n xpense
```

## Testing Preview Version

Access the preview version for testing:
```bash
# Port-forward to preview service
kubectl port-forward -n xpense svc/xpense-tracker-backend-preview 8085:8085

# Test the preview endpoint
curl http://localhost:8085/actuator/health
```

## Deployment Workflow

1. **Update the image** in `backend-rollout.yaml` or via CI/CD
2. **ArgoCD syncs** the change and Rollout creates new pods
3. **Test preview** version using the preview service
4. **Promote** if tests pass: `kubectl argo rollouts promote xpense-tracker-backend -n xpense`
5. **Active service** automatically switches to the new version
6. **Old version** is scaled down after 30 seconds (scaleDownDelaySeconds)

## Configuration

- **Replicas**: 2 (defined in rollout spec)
- **Auto Promotion**: Disabled (manual promotion required)
- **Scale Down Delay**: 30 seconds after promotion
- **Revision History**: Keeps last 2 revisions

## Important Notes

- The frontend nginx config points to `xpense-tracker-backend-active` service
- Always test the preview version before promoting
- Auto-promotion is disabled for safety - requires manual approval
- The old deployment file (`backend-deployment.yaml`) should be deleted or renamed to avoid conflicts