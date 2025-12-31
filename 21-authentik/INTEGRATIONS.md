# Authentik Service Integrations

After deploying Authentik, configure your services to use it for authentication.

## Initial Setup

1. Navigate to `https://auth.apps.house.simonellistonball.com/if/flow/initial-setup/`
2. Create your admin account (akadmin)
3. Log in and configure applications below

## Service Integrations

### Grafana (Native OIDC)

1. In Authentik: Create OAuth2/OIDC Provider + Application
   - Provider: `grafana`
   - Redirect URI: `https://grafana.apps.house.simonellistonball.com/login/generic_oauth`
   - Scopes: `openid email profile`

2. Add to Grafana Helm values:
```yaml
grafana:
  grafana.ini:
    server:
      root_url: https://grafana.apps.house.simonellistonball.com
    auth.generic_oauth:
      enabled: true
      name: Authentik
      client_id: <from authentik>
      client_secret: <from authentik>
      scopes: openid email profile
      auth_url: https://auth.apps.house.simonellistonball.com/application/o/authorize/
      token_url: https://auth.apps.house.simonellistonball.com/application/o/token/
      api_url: https://auth.apps.house.simonellistonball.com/application/o/userinfo/
      role_attribute_path: contains(groups[*], 'grafana-admin') && 'Admin' || 'Viewer'
```

### Gitea (Native OIDC)

1. In Authentik: Create OAuth2/OIDC Provider + Application
   - Provider: `gitea`
   - Redirect URI: `https://gitea.apps.house.simonellistonball.com/user/oauth2/authentik/callback`

2. In Gitea Admin: Site Administration > Authentication Sources > Add
   - Type: OAuth2
   - Provider: OpenID Connect
   - Client ID/Secret: from Authentik
   - OpenID Connect Auto Discovery URL: `https://auth.apps.house.simonellistonball.com/application/o/gitea/.well-known/openid-configuration`

### Harbor (Native OIDC)

1. In Authentik: Create OAuth2/OIDC Provider + Application
   - Provider: `harbor`
   - Redirect URI: `https://harbor.apps.house.simonellistonball.com/c/oidc/callback`

2. In Harbor: Configuration > Authentication
   - Auth Mode: OIDC
   - OIDC Provider: `https://auth.apps.house.simonellistonball.com/application/o/harbor/`
   - Client ID/Secret: from Authentik
   - OIDC Scope: `openid,email,profile`
   - Username Claim: `preferred_username`
   - Group Claim: `groups`

### Immich (Native OIDC)

1. In Authentik: Create OAuth2/OIDC Provider + Application
   - Provider: `immich`
   - Redirect URI: `https://photos.apps.house.simonellistonball.com/auth/login`
   - `app://` for mobile

2. In Immich: Administration > Settings > OAuth
   - Enable OAuth Login
   - Issuer URL: `https://auth.apps.house.simonellistonball.com/application/o/immich/`
   - Client ID/Secret: from Authentik
   - Scope: `openid email profile`

### Traefik Dashboard (Forward Auth)

Update `02-traefik/dashboard-ingressroute.yaml`:
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`traefik.apps.house.simonellistonball.com`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))
      middlewares:
        - name: authentik
          namespace: auth
      services:
        - kind: TraefikService
          name: api@internal
  tls:
    secretName: apps-house-tls
```

Before this works, create in Authentik:
1. Application: `traefik`
2. Provider: Proxy Provider (Forward Auth mode)
3. External Host: `https://traefik.apps.house.simonellistonball.com`
4. Add to embedded outpost

### n8n (Forward Auth)

Update `11-n8n/ingressroute.yaml`:
```yaml
routes:
  - kind: Rule
    match: Host(`n8n.apps.house.simonellistonball.com`)
    middlewares:
      - name: authentik
        namespace: auth
    services:
      - name: n8n
        port: 5678
```

### Dagster (Forward Auth)

Update `09-dagster/ingressroute.yaml`:
```yaml
routes:
  - kind: Rule
    match: Host(`dagster.apps.house.simonellistonball.com`)
    middlewares:
      - name: authentik
        namespace: auth
    services:
      - name: dagster-webserver
        port: 80
```

## LLDAP Integration (LDAPS/TLS)

The LLDAP source is **automatically configured** via blueprint during deployment.

**Auto-configured settings:**
- Name: `LLDAP`
- Server URI: `ldaps://lldap.auth.svc.cluster.local:636`
- Bind CN: `uid=admin,ou=people,dc=house,dc=simonellistonball,dc=com`
- Base DN: `dc=house,dc=simonellistonball,dc=com`
- User sync: enabled
- Group sync: enabled

**After deployment:**
1. Go to Directory > Federation & Social Logins
2. Click on the "LLDAP" source
3. Click "Sync" to import users from LLDAP

The CA trust bundle (`simonellistonball-ca-bundle`) is automatically distributed to the `auth` namespace for LDAPS verification.

See `22-lldap/INTEGRATIONS.md` for full details.

## Creating Users and Groups

1. Directory > Users - Create users
2. Directory > Groups - Create groups like:
   - `grafana-admin` - Full Grafana admin access
   - `harbor-admin` - Harbor admin access
   - `developers` - General dev access

## Outpost Configuration

For forward auth to work:

1. Applications > Outposts > Edit `authentik Embedded Outpost`
2. Add all applications that use forward auth (traefik, n8n, dagster, etc.)
3. Save

Or create a dedicated proxy outpost for better isolation.
