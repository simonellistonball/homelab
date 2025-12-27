# Homelab Kubernetes Deployment

A complete infrastructure-as-code setup for a K3s single-node cluster with dual-stack IPv4/IPv6 networking, using Cilium CNI and a variety of self-hosted services.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        vm-111 (K3s Node)                        │
│  192.168.1.111 (main) │ 192.168.16.21 (storage) │ 192.168.100.11 (k8s)│
└─────────────────────────────────────────────────────────────────┘
         │                        │                        │
         │                        │                        │
         ▼                        ▼                        ▼
   ┌──────────┐            ┌──────────┐            ┌──────────────┐
   │ Internet │            │ TrueNAS  │            │ LoadBalancer │
   │  Access  │            │  NFS     │            │   Services   │
   └──────────┘            │192.168.16.11│         │ (Traefik)    │
                           └──────────┘            └──────────────┘
```

## Components

| Component | Description |
|-----------|-------------|
| **Cilium** | CNI with eBPF, dual-stack networking, L2 LoadBalancer |
| **Traefik** | Ingress controller with automatic TLS |
| **cert-manager** | Private CA for internal TLS certificates |
| **trust-manager** | Distributes CA trust bundle cluster-wide |
| **Redis** | In-memory cache/database |
| **Prometheus/Grafana/Loki** | Monitoring and logging stack |
| **Harbor** | Container registry |
| **Gitea** | Git server |
| **Dagster** | Data orchestration platform |
| **Redpanda** | Kafka-compatible streaming platform |
| **n8n** | Workflow automation |
| **LiteLLM** | LLM API proxy |
| **Whisper** | Speech-to-text service |
| **SeaweedFS** | S3-compatible object storage with tiered storage |
| **Immich** | Self-hosted photo and video management |

## Prerequisites

- Ubuntu/Debian VM with:
  - 8+ CPU cores
  - 32+ GB RAM
  - Network interfaces configured (main, storage, k8s vlan)
- TrueNAS server with NFS shares configured
- PostgreSQL server with databases created
- DNS configured for `*.apps.house.simonellistonball.com`

## Quick Start

### 1. Clone and Configure

```bash
git clone <repo-url> homelab
cd homelab

# Copy example config and customize
cp config.env.example config.env
vim config.env

# Generate secure passwords
./generate-passwords.sh
```

### 2. Prepare the VM

Ensure mount points exist on the K3s node:

```bash
sudo mkdir -p /mnt/scratch
sudo chmod 777 /mnt/scratch
```

### 3. Install K3s

```bash
sudo ./scripts/install-k3s.sh
```

This installs K3s with:
- Dual-stack IPv4/IPv6 networking
- Flannel disabled (Cilium will be used)
- Built-in Traefik and servicelb disabled

### 4. Deploy Everything

```bash
./deploy.sh
```

Or deploy individual components:

```bash
./deploy.sh 01-cilium
./deploy.sh 02-traefik
# etc.
```

## Directory Structure

```
homelab/
├── config.env.example     # Configuration template
├── config.env             # Your configuration (git-ignored)
├── deploy.sh              # Master deployment script
├── generate-passwords.sh  # Password generator
├── scripts/
│   ├── install-k3s.sh           # K3s installation
│   ├── generate-postgres-sql.sh # PostgreSQL setup
│   ├── generate-ca-secret.sh    # Generate CA secret from certs
│   └── update-postgres-passwords.sh
├── 00-namespaces/         # Kubernetes namespaces
├── 01-cilium/             # Cilium CNI + L2 LoadBalancer
├── 02-traefik/            # Ingress controller
├── 03-cert-manager/       # TLS certificate management
├── 04-storage/            # Storage classes and PVs
├── 05-redis/              # Redis deployment
├── 06-monitoring/         # Prometheus/Grafana/Loki
├── 07-harbor/             # Container registry
├── 08-gitea/              # Git server
├── 09-dagster/            # Data orchestration
├── 10-redpanda/           # Kafka-compatible streaming
├── 11-n8n/                # Workflow automation
├── 12-ai/                 # LiteLLM + Whisper
├── 13-seaweedfs/          # S3-compatible object storage
└── 14-immich/             # Photo and video management
```

## Network Configuration

### IP Ranges

| Network | Range | Purpose |
|---------|-------|---------|
| Main | 192.168.1.0/24 | Management, K8s API |
| Storage | 192.168.16.0/24 | NFS traffic to TrueNAS |
| K8s VLAN | 192.168.100.0/24 | LoadBalancer services |
| Pod CIDR | 10.42.0.0/16 + fd00:10:42::/56 | Pod networking |
| Service CIDR | 10.43.0.0/16 + fd00:10:43::/112 | ClusterIP services |

### Key Service IPs

| Service | IPv4 | IPv6 |
|---------|------|------|
| Traefik | 192.168.100.11 | 2a0e:cb01:f1:1001::b |
| Gitea SSH | 192.168.100.22 | - |

## Storage Classes

| Class | Type | Path | Use Case |
|-------|------|------|----------|
| `nfs-fast` | NFS | /mnt/fast/data | Databases, caches |
| `scratch` | local-path | /mnt/scratch | Temporary data |
| `nfs-data` | NFS | /mnt/data/data | General storage |
| `nfs-backups` | NFS | /mnt/data/backups | Backups |
| `nfs-archive` | NFS | /mnt/data/archive | Long-term storage |
| `nfs-models` | NFS | /mnt/fast/models | AI model cache |
| `nfs-surveillance` | NFS | /mnt/surveillance/frigate | Camera recordings |

## Service URLs

After deployment, services are available at:

| Service | URL |
|---------|-----|
| Traefik Dashboard | https://traefik.apps.house.simonellistonball.com |
| Grafana | https://grafana.apps.house.simonellistonball.com |
| Prometheus | https://prometheus.apps.house.simonellistonball.com |
| Harbor | https://harbor.apps.house.simonellistonball.com |
| Gitea | https://gitea.apps.house.simonellistonball.com |
| Dagster | https://dagster.apps.house.simonellistonball.com |
| Redpanda Console | https://redpanda.apps.house.simonellistonball.com |
| n8n | https://n8n.apps.house.simonellistonball.com |
| LiteLLM | https://llm.apps.house.simonellistonball.com |
| Whisper | https://whisper.apps.house.simonellistonball.com |
| SeaweedFS S3 | https://s3.apps.house.simonellistonball.com |
| SeaweedFS Filer | https://seaweedfs.apps.house.simonellistonball.com |
| Immich | https://immich.apps.house.simonellistonball.com |

## PostgreSQL Setup

The following databases should be created on your PostgreSQL server:

```bash
# Generate SQL script with passwords from config.env
./scripts/generate-postgres-sql.sh

# Apply to PostgreSQL server
psql -h 192.168.1.103 -U postgres < scripts/postgres-setup.sql
```

Required databases: `n8n`, `gitea`, `harbor`, `dagster`, `litellm`, `immich`, `frigate`

## SeaweedFS Object Storage

SeaweedFS provides S3-compatible object storage with tiered storage:

### Storage Tiers

| Tier | Storage Class | Use Case |
|------|--------------|----------|
| Hot | nfs-fast | Frequently accessed, performance-critical |
| Warm | nfs-data | Regular data |
| Cold | nfs-archive | Infrequently accessed, archival |

### Path-Based Tiering

Data is automatically placed on the appropriate tier based on bucket path:

```
/buckets/hot/*     → Hot tier (SSD)
/buckets/cache/*   → Hot tier (SSD)
/buckets/data/*    → Warm tier (HDD)
/buckets/archive/* → Cold tier (HDD)
/buckets/backup/*  → Cold tier (HDD)
```

### S3 API Usage

```bash
# Configure AWS CLI
export AWS_ACCESS_KEY_ID=<your-access-key>
export AWS_SECRET_ACCESS_KEY=<your-secret-key>

# Create bucket
aws --endpoint-url=https://s3.apps.house.simonellistonball.com s3 mb s3://mybucket

# Upload file
aws --endpoint-url=https://s3.apps.house.simonellistonball.com s3 cp file.txt s3://mybucket/

# List buckets
aws --endpoint-url=https://s3.apps.house.simonellistonball.com s3 ls
```

## Troubleshooting

### Check Cilium status
```bash
cilium status
cilium connectivity test
```

### Check pod networking
```bash
kubectl get pods -A -o wide
kubectl get svc -A
```

### Check LoadBalancer IPs
```bash
kubectl get ciliumloadbalancerippools
kubectl get ciliuml2announcementpolicies
```

### View logs
```bash
kubectl logs -n <namespace> <pod-name>
kubectl logs -n kube-system -l app.kubernetes.io/name=cilium
```

## Updating

To update a component:

```bash
# Update a single component
./deploy.sh 06-monitoring

# Or update everything
./deploy.sh
```

## Backup

Important data to backup:
- `config.env` (contains all passwords)
- PostgreSQL databases
- NFS shares on TrueNAS
- Gitea repositories
- Harbor container images
- SeaweedFS object storage data
