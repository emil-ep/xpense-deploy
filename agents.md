# xpense-tracker-deploy — Agent Context

This document exists so that an AI agent (or a human) can correctly maintain
`install.sh` and the surrounding Kubernetes manifests without accidentally
omitting required secrets or configuration. Update it whenever a new secret,
environment variable, or external dependency is added to any service.

---

## What this repository does

`xpense-tracker-deploy` is the **GitOps delivery repository** for the Xpense
Tracker platform. It contains:

| Path | Purpose |
|---|---|
| `k8s/` | All Kubernetes manifests (namespace, workloads, services, config, secrets) |
| `argocd/application.yaml` | ArgoCD Application CR — points ArgoCD at this repo |
| `install.sh` | One-shot installer: collects credentials, creates secrets, deploys via ArgoCD |
| `uninstall.sh` | Removes the ArgoCD application and `xpense` namespace |
| `ARGOCD-ROLLOUTS-SETUP.md` | Manual reference for ArgoCD + Argo Rollouts operations |

ArgoCD watches the `master` branch and auto-syncs any change to `k8s/`. All
secrets are **created by `install.sh`** — they are never committed to Git.
The secret stub YAML files in `k8s/` carry `argocd.argoproj.io/sync-options: Skip`
so ArgoCD never overwrites the live secrets.

---

## Infrastructure components

### PostgreSQL (`k8s/postgres/`)
- Image: `ghcr.io/baosystems/postgis:16-3.4`
- Started from `postgres-secret` (credentials) + `postgres-init-script` ConfigMap
- The init script creates the `mf` database on first start
- Two databases used by the application:
  - `xpense_tracker` — main tracker data
  - `mf` — mutual fund data consumed by xpense-consumer and xpense-scheduler

### Kafka (`k8s/kafka/`)
- Image: `apache/kafka:3.7.0`
- Single-node KRaft mode (combined broker + controller, `nodeId=1`)
- `CLUSTER_ID` is pinned to `MkU3OEVBNTcwNTJENDM2Qk` — prevents cluster.id
  mismatch on reinstalls where the PVC already holds metadata
- `KAFKA_CONTROLLER_QUORUM_VOTERS` uses `1@localhost:9093` so the controller
  listener is reachable within the pod regardless of the pod hostname
- The `kafka-data` PVC is deleted by `install.sh` on every install so Kafka
  always formats the volume with the pinned cluster ID

### Backend (`k8s/backend/`)
- Image: `ghcr.io/emil-ep/xpense-backend:<version>`
- Deployed as an **Argo Rollouts Rollout** (blue-green strategy)
- Manual promotion required (`autoPromotionEnabled: false`)
- Post-promotion health gate uses the `instana-bluegreen-health` AnalysisTemplate
- Reads from `xpense-backend-config` (ConfigMap) + `xpense-backend-secret` (Secret)
- Spring profile: `k8s`
- Port: `8085`
- Uploads stored on PVC `xpense-backend-uploads`

### Frontend (`k8s/frontend/`)
- Standard Deployment + nginx

### xpense-scheduler (`k8s/scheduler/`)
- Image: `ghcr.io/emil-ep/xpense-scheduler:latest`
- init containers wait for Kafka (port 9092) and Postgres (port 5432)
- Reads from `xpense-scheduler-config` + `xpense-scheduler-secret`
- Spring profile: `k8s`
- Port: `8086`

### xpense-consumer (`k8s/consumer/`)
- Image: `ghcr.io/emil-ep/xpense-consumer:latest`
- init containers wait for Kafka and Postgres
- Reads from `xpense-consumer-config` + `xpense-consumer-secret`
- Spring profile: `k8s`
- Port: `8089`

---

## Secrets matrix

This is the definitive list of every secret `install.sh` must create. If a
new secret is needed, add it here **and** to `install.sh`.

### `postgres-secret` (namespace: `xpense`)

| Key | Value | Collected from |
|---|---|---|
| `POSTGRES_USER` | `xpense_admin` | hardcoded |
| `POSTGRES_PASSWORD` | user-supplied | installer prompt |
| `POSTGRES_DB` | `xpense_tracker` | hardcoded |

### `xpense-backend-secret` (namespace: `xpense`)

| Key | Value | Collected from |
|---|---|---|
| `TRACKER_DATASOURCE_USERNAME` | `xpense_admin` | hardcoded |
| `TRACKER_DATASOURCE_PASSWORD` | postgres password | installer prompt |
| `MF_DATASOURCE_USERNAME` | `xpense_admin` | hardcoded |
| `MF_DATASOURCE_PASSWORD` | postgres password | installer prompt |
| `INTERNAL_SERVICE_USERNAME` | user-supplied | installer prompt |
| `INTERNAL_SERVICE_PASSWORD` | user-supplied | installer prompt |
| `TOKEN_SIGNING_KEY` | base64 JWT key | installer prompt / auto-generated |

### `xpense-scheduler-secret` (namespace: `xpense`)

| Key | Value | Collected from |
|---|---|---|
| `TRACKER_DATASOURCE_USERNAME` | `xpense_admin` | hardcoded |
| `TRACKER_DATASOURCE_PASSWORD` | postgres password | installer prompt |
| `MF_DATASOURCE_USERNAME` | `xpense_admin` | hardcoded |
| `MF_DATASOURCE_PASSWORD` | postgres password | installer prompt |
| `TRACKER_SERVICE_USERNAME` | internal username | installer prompt |
| `TRACKER_SERVICE_PASSWORD` | internal password | installer prompt |

### `xpense-consumer-secret` (namespace: `xpense`)

| Key | Value | Collected from |
|---|---|---|
| `MF_DATASOURCE_USERNAME` | `xpense_admin` | hardcoded |
| `MF_DATASOURCE_PASSWORD` | postgres password | installer prompt |

### `instana-credentials` (namespace: `xpense`)

Used by the `instana-bluegreen-health` AnalysisTemplate to query the Instana
metrics API during blue-green promotion.

| Key | Value | Collected from |
|---|---|---|
| `host` | Instana tenant URL, e.g. `https://mytenant.instana.io` | installer prompt |
| `clusterName` | Kubernetes cluster name as registered in Instana | installer prompt |

### `instana-api-token` (namespace: `argo-rollouts`)

Injected as the `INSTANA_API_TOKEN` environment variable into the
`argo-rollouts` controller Deployment so the Instana metrics provider plugin
can authenticate to the Instana REST API.

| Key | Value | Collected from |
|---|---|---|
| `INSTANA_API_TOKEN` | Instana REST API token | installer prompt |

> **Note**: `install.sh` also patches the `argo-rollouts` Deployment to mount
> this secret as an env var. The patch is idempotent — re-running the installer
> is safe.

---

## ConfigMap values (non-secret, committed to Git)

### `xpense-backend-config`
| Key | Value |
|---|---|
| `TRACKER_DATASOURCE_URL` | `jdbc:postgresql://postgres:5432/xpense_tracker` |
| `MF_DATASOURCE_URL` | `jdbc:postgresql://postgres:5432/mf` |
| `FRONTEND_URL` | `http://xpense.local` |

### `xpense-scheduler-config`
| Key | Value |
|---|---|
| `TRACKER_DATASOURCE_URL` | `jdbc:postgresql://postgres:5432/xpense_tracker` |
| `MF_DATASOURCE_URL` | `jdbc:postgresql://postgres:5432/mf` |
| `KAFKA_BOOTSTRAP_SERVER` | `kafka:9092` |
| `TRACKER_SERVICE_URL` | `http://xpense-tracker-backend-active:8085` |

### `xpense-consumer-config`
| Key | Value |
|---|---|
| `MF_DATASOURCE_URL` | `jdbc:postgresql://postgres:5432/mf` |
| `KAFKA_BOOTSTRAP_SERVER` | `kafka:9092` |

---

## Instana blue-green analysis

The `instana-bluegreen-health` AnalysisTemplate (`k8s/backend/analysis-template.yaml`)
runs **after promotion** (post-promotion gate). It checks two metrics against
the new (green) ReplicaSet:

| Metric | Threshold | Source |
|---|---|---|
| Error rate | ≤ 5% | Instana `errors` (MEAN, 60s granularity, 5-min window) |
| Latency p90 | ≤ 1000 ms | Instana `latency` (P90, 60s granularity, 5-min window) |

The analysis is scoped to the green pod set by `rollouts-pod-template-hash`
label. If the analysis fails (2 failures in 3 measurements), Argo Rollouts
reverts the active service back to the blue ReplicaSet.

**Prerequisites for the analysis to run:**
1. `instana-credentials` secret in `xpense` namespace (host + clusterName)
2. `instana-api-token` secret in `argo-rollouts` namespace
3. `INSTANA_API_TOKEN` env var patched into the `argo-rollouts` controller Deployment
4. Instana `instana/metrics` plugin installed on the Argo Rollouts controller

---

## Known pitfalls

### PostgreSQL fails to start — `POSTGRES_PASSWORD` empty
ArgoCD must **not** overwrite the `postgres-secret`. All secret stubs in `k8s/`
carry `argocd.argoproj.io/sync-options: Skip` for this reason. If this
annotation is ever removed or changed to `Prune=false`, ArgoCD will reset
`data: {}` on every sync and Postgres will refuse to start.

### Kafka fails — `cluster.id mismatch`
Kafka stores cluster metadata on the PVC. If the pod restarts with a different
cluster ID than what is on disk it crashes. Mitigations in place:
1. `CLUSTER_ID` is pinned in `kafka-deployment.yaml` so the same ID is always
   used to format the volume.
2. `install.sh` deletes the `kafka-data` PVC before deploying so a fresh
   install always starts clean.

### Kafka fails — broker cannot register with controller
In KRaft combined mode the broker and controller run in the same process but
the controller listener resolves to the **pod hostname** (ephemeral), not the
Service DNS. `KAFKA_CONTROLLER_QUORUM_VOTERS` must use `1@localhost:9093` so
the in-process communication works regardless of the pod name.

### Instana AnalysisTemplate fails silently
If `instana-credentials` or `instana-api-token` do not exist, or `INSTANA_API_TOKEN`
is not injected into the `argo-rollouts` controller, the AnalysisTemplate will
error. `install.sh` creates all three as part of Step 4.

---

## install.sh checklist (what the script must collect)

Use this as a review checklist whenever `install.sh` is modified:

- [ ] PostgreSQL password (confirmed twice, not empty)
- [ ] JWT signing key (auto-generated if blank)
- [ ] Internal service username + password (defaulted to `service`/`service`)
- [ ] Instana API token
- [ ] Instana tenant host URL
- [ ] Instana cluster name
- [ ] Stale `kafka-data` PVC deleted before deploy
- [ ] `postgres-secret` verified non-empty before proceeding to ArgoCD sync
- [ ] `argo-rollouts` controller patched with `INSTANA_API_TOKEN`
