# LLDAP Integration Guide

LLDAP is the authoritative source for Unix users and groups. It syncs to Authentik for web SSO and to TrueNAS for NFS permissions.

**All LDAP connections use TLS (LDAPS on port 636)** for security.

## Architecture

```
                    ┌─────────────┐
                    │   LLDAP     │
                    │ (Users/Groups)
                    └──────┬──────┘
                           │ LDAPS (TLS)
            ┌──────────────┼──────────────┐
            │              │              │
            ▼              ▼              ▼
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │ Authentik│   │ TrueNAS  │   │ K8s Nodes│
      │ (Web SSO)│   │  (NFS)   │   │ (optional)
      └──────────┘   └──────────┘   └──────────┘
```

## TLS Certificate

LLDAP uses a certificate signed by the **Simon Elliston Ball Root CA** for LDAPS.

The certificate is automatically issued by cert-manager using the `ca-issuer` ClusterIssuer with these SANs:
- `lldap.auth.svc.cluster.local`
- `lldap.auth.svc`
- `lldap`
- `ldap.apps.house.simonellistonball.com`

## LLDAP Configuration

### Base DN Structure
```
dc=house,dc=simonellistonball,dc=com
├── ou=people          # Users
│   ├── uid=admin
│   ├── uid=simon
│   └── uid=family1
└── ou=groups          # Groups
    ├── cn=admins
    ├── cn=family
    ├── cn=media       # For media file access (Immich, Plex, etc.)
    └── cn=backup      # For backup access
```

### Recommended Groups and GIDs

Create these groups in LLDAP with consistent GIDs:

| Group   | GID  | Purpose                          |
|---------|------|----------------------------------|
| admins  | 1000 | Full admin access                |
| family  | 1001 | Family members                   |
| media   | 1002 | Media file access (photos, etc.) |
| backup  | 1003 | Backup access                    |
| apps    | 1004 | Application service accounts     |

### Recommended Users

| User    | UID  | Groups              | Purpose           |
|---------|------|---------------------|-------------------|
| admin   | 1000 | admins              | LLDAP admin       |
| simon   | 1001 | admins, family, media | Primary user   |
| immich  | 1100 | media, apps         | Immich service    |

## TrueNAS Integration

### Export Root CA Certificate

First, export the Root CA for TrueNAS to trust:

```bash
# Extract from the cluster
kubectl get configmap root-ca-configmap -n cert-manager -o jsonpath='{.data.root-ca\.crt}' > simon-elliston-ball-root-ca.crt
```

Or copy from `03-cert-manager/root-ca-configmap.yaml`.

### Configure LDAP Directory Service

1. **TrueNAS Web UI** → Directory Services → LDAP

2. **Connection Settings:**
   - Hostname: `ldap.apps.house.simonellistonball.com` (or LoadBalancer IP)
   - Port: `636`
   - Encryption: `SSL` (LDAPS)
   - Base DN: `dc=house,dc=simonellistonball,dc=com`
   - Bind DN: `uid=admin,ou=people,dc=house,dc=simonellistonball,dc=com`
   - Bind Password: (from LLDAP_ADMIN_PASSWORD)

3. **Certificate:**
   - Upload the Root CA certificate (`simon-elliston-ball-root-ca.crt`)
   - Or add to TrueNAS trusted CAs

4. **Advanced Options:**
   - User Suffix: `ou=people`
   - Group Suffix: `ou=groups`
   - Allow Anonymous Binding: No

5. **Test and Enable**

### NFS Share Permissions

After LDAP is configured, set dataset permissions using LDAP users/groups:

```bash
# Example: Photos dataset for Immich
# Owner: immich (UID 1100)
# Group: media (GID 1002)
# Mode: 770
```

## Authentik Integration

### Configure LDAP Source (Manual via UI)

1. **Authentik Admin** → Directory → Federation & Social Logins → Create → LDAP Source

2. **Connection Settings:**
   - Name: `LLDAP`
   - Server URI: `ldaps://lldap.auth.svc.cluster.local:636`
   - Enable StartTLS: No (already using LDAPS)
   - TLS Verification Certificate: Select the CA bundle or skip verification for internal
   - Bind CN: `uid=admin,ou=people,dc=house,dc=simonellistonball,dc=com`
   - Bind Password: (from LLDAP_ADMIN_PASSWORD)
   - Base DN: `dc=house,dc=simonellistonball,dc=com`

3. **LDAP Attribute Mapping:**
   - User object filter: `(objectClass=person)`
   - Group object filter: `(objectClass=groupOfUniqueNames)`
   - User path template: `ou=people`
   - Group path template: `ou=groups`

4. **Sync Settings:**
   - Sync users: Yes
   - Sync groups: Yes
   - Sync parent group: (optional)
   - Property mappings: Use defaults or customize

5. **Save and Sync**

### CA Certificate for Authentik

The trust bundle (`simonellistonball-ca-bundle`) is automatically distributed to all namespaces by trust-manager. Authentik pods can mount this for LDAPS verification:

```yaml
# Already available as ConfigMap in auth namespace
kubectl get configmap simonellistonball-ca-bundle -n auth
```

### Sync Schedule

Authentik will sync users on a schedule. You can also trigger manual sync:
- Go to Directory → Federation & Social Logins
- Click on LLDAP source
- Click "Sync" button

## Kubernetes Node Integration (Optional)

If you want K8s nodes to recognize LDAP users (for pod securityContext):

### Install SSSD on Nodes

```bash
# On each K8s node
apt install sssd sssd-ldap ca-certificates

# Copy the Root CA
cp simon-elliston-ball-root-ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

# /etc/sssd/sssd.conf
[sssd]
services = nss, pam
config_file_version = 2
domains = LDAP

[domain/LDAP]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldaps://lldap.auth.svc.cluster.local:636
ldap_search_base = dc=house,dc=simonellistonball,dc=com
ldap_default_bind_dn = uid=admin,ou=people,dc=house,dc=simonellistonball,dc=com
ldap_default_authtok = <LLDAP_ADMIN_PASSWORD>
ldap_user_search_base = ou=people,dc=house,dc=simonellistonball,dc=com
ldap_group_search_base = ou=groups,dc=house,dc=simonellistonball,dc=com
ldap_tls_cacert = /etc/ssl/certs/ca-certificates.crt
ldap_id_use_start_tls = false
```

## Deployment Order

1. Deploy LLDAP first:
   ```bash
   rsync -avz ~/homelab/22-lldap/ k8s:~/homelab/22-lldap/
   ssh k8s 'cd ~/homelab && ./deploy.sh 22-lldap'
   ```

2. Create users/groups in LLDAP web UI

3. Deploy Authentik:
   ```bash
   rsync -avz ~/homelab/21-authentik/ k8s:~/homelab/21-authentik/
   ssh k8s 'cd ~/homelab && ./deploy.sh 21-authentik'
   ```

4. Configure Authentik LDAP source (via web UI)

5. Configure TrueNAS LDAP (via web UI)

## Troubleshooting

### Test LDAPS Connection
```bash
# From a pod in the cluster (with openssl)
openssl s_client -connect lldap.auth.svc.cluster.local:636 -showcerts

# Test LDAP query with TLS
ldapsearch -x -H ldaps://lldap.auth.svc.cluster.local:636 \
  -D "uid=admin,ou=people,dc=house,dc=simonellistonball,dc=com" \
  -w "<password>" \
  -b "dc=house,dc=simonellistonball,dc=com" \
  "(objectClass=person)"
```

### Check Certificate
```bash
# Verify the LDAPS certificate
kubectl get secret lldap-ldaps-tls -n auth -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

### Check User/Group Sync in Authentik
- Directory → Users - should show LDAP users
- Directory → Groups - should show LDAP groups

### Verify TrueNAS LDAP
- Directory Services → LDAP → Rebuild Directory Service Cache
- Shell: `getent passwd` should show LDAP users
- Shell: `getent group` should show LDAP groups

### Certificate Trust Issues
If you get certificate verification errors:
1. Ensure the Root CA is installed on the client
2. Check the certificate chain: `openssl verify -CAfile root-ca.crt server-cert.crt`
3. Verify the hostname matches the certificate SANs
