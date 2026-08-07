# Yggdrasil — Service Management

## Overview

Services are split into two categories:

| Category | Where | How managed | Rebuilt? |
|---|---|---|---|
| **Network** | Pi-hole LXC + Cloudflared LXC | Ansible | Never (stable) |
| **Kubernetes** | draupnir (k3s) | Flux GitOps | Frequently |

The key design principle: **network infrastructure survives draupnir rebuilds**.
Pi-hole (DNS), cloudflared (tunnel), and Homepage (dashboard) run on dedicated
stable LXCs. You can rebuild draupnir completely and still have remote access,
local DNS, and your dashboard.

---

## Infrastructure Map

```
192.168.69.2  pihole       LXC 102  — DNS, ad blocking
192.168.69.3  cloudflared  LXC 103  — Cloudflare tunnel + Homepage dashboard
192.168.69.5  alexandria   LXC 111  — NAS, file sharing (mimmisbrunnr 60TB)
192.168.69.69 asgard               — Proxmox hypervisor
192.168.69.77 draupnir     VM  777  — k3s Kubernetes cluster
```

---

## Adding a Non-Kubernetes Service

A "non-k8s service" is anything NOT running on draupnir — e.g. a web UI on
alexandria, Proxmox itself, or a future service on a new LXC.

**Step 1 — Add to the service registry:**

Edit `infrastructure/ansible/vars/services.yml` and add an entry:

```yaml
- name: My App
  description: What this app does
  hostname: myapp.yggdrasil.rip      # must be a real DNS name you control
  ip: 192.168.69.X                   # IP of the host running the service
  port: 8080                         # port the service listens on
  protocol: http                     # http or https
  tls_verify: true                   # false only for self-signed certs
  homepage_group: Storage            # group in Homepage: Network, Storage, Media, etc.
  homepage_icon: myapp.png           # icon from https://github.com/walkxcode/dashboard-icons
```

**Step 2 — Add a Cloudflare DNS record:**

In the Cloudflare dashboard → DNS:
- Type: `CNAME`
- Name: `myapp`
- Target: `<tunnel-id>.cfargotunnel.com`
- Proxy: Enabled (orange cloud)

**Step 3 — Apply:**

```bash
cd infrastructure/ansible
ansible-playbook site.yml --limit network
```

This updates:
- Pi-hole `custom.list` → `myapp.yggdrasil.rip` resolves locally to the service IP
- Cloudflared `config.yaml` → tunnel routes `myapp.yggdrasil.rip` to `ip:port`
- Homepage `services.yaml` → service card appears in the dashboard

**Step 4 — (Optional) Zero Trust policy:**

A wildcard Access Application already gates `*.yggdrasil.rip` (see
[Cloudflare Access — Google SSO](#cloudflare-access--google-sso) below), so
new services under `*.yggdrasil.rip` are covered automatically — no
per-service policy needed. Only add a dedicated Access Application in
Cloudflare Zero Trust → Access → Applications if this service needs to
*bypass* Access (e.g. it's an API/bearer-token endpoint, like the MCP
servers) or needs a different policy than "Google SSO, approved emails
only".

---

## Adding a Kubernetes Service

A "k8s service" runs on draupnir, deployed via Flux from this git repo.

**Step 1 — Create manifests:**

```
apps/k8s/<namespace>/<appname>/
  kustomization.yaml
  deployment.yaml   (or combined yaml)
  service.yaml
  ingress.yaml
```

**Step 2 — Add Homepage annotations to the Ingress:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: myns
  annotations:
    kubernetes.io/ingress.class: traefik
    # Homepage auto-discovery
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: "My App"
    gethomepage.dev/group: "Media"        # group in Homepage
    gethomepage.dev/icon: "myapp.png"     # from dashboard-icons
    gethomepage.dev/description: "My app description"
    # ExternalDNS — creates Cloudflare DNS record automatically
    external-dns.alpha.kubernetes.io/hostname: myapp.yggdrasil.rip
spec:
  rules:
  - host: myapp.yggdrasil.rip
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

**Step 3 — Add to the namespace kustomization:**

Edit `apps/k8s/<namespace>/kustomization.yaml` and add `- myapp/`.

**Step 4 — Push to git:**

```bash
git add .
git commit -m "add myapp"
git push
```

Flux picks it up automatically. Within ~1 minute:
- Deployment runs on draupnir
- ExternalDNS creates `myapp.yggdrasil.rip` DNS record in Cloudflare
- Cloudflared routes `myapp.yggdrasil.rip` to Traefik → pod (catch-all rule)
- Homepage discovers the service via the Ingress annotation

**No manual intervention required.**

---

## Secrets Reference

`vars/secrets.yml` (ansible-vault encrypted):

| Key | Used by | Description |
|---|---|---|
| `tailscale_auth_key` | tailscale role | Tailscale auth key for joining tailnet |
| `samba_user` | fileshare role | Samba share username |
| `samba_password` | fileshare role | Samba share password |
| `github_token` | flux_bootstrap role | GitHub PAT for Flux (repo scope) |
| `sops_age_key` | flux_bootstrap role | Age private key for SOPS decryption |
| `proxmox_password` | rclone_mount, fileshare | Used for rclone SFTP auth to njord |
| `ssh_public_key` | fileshare role | Public key added to david's authorized_keys |
| `pihole_password` | pihole role | Pi-hole web UI admin password |
| `cloudflare_tunnel_id` | cloudflared role | Tunnel ID from Cloudflare dashboard |
| `cloudflare_credentials_json` | cloudflared role | Tunnel credentials JSON file contents |

---

## Playbook Reference

```bash
# All hosts
ansible-playbook site.yml

# Network services only (Pi-hole + cloudflared + Homepage)
ansible-playbook site.yml --limit network

# Core only (alexandria + draupnir)
ansible-playbook site.yml --limit core

# Single host
ansible-playbook site.yml --limit pihole
ansible-playbook site.yml --limit cloudflared
ansible-playbook site.yml --limit alexandria
ansible-playbook site.yml --limit draupnir
```

---

## Cloudflare Access — Google SSO

`infrastructure/network/cloudflare_access.tf` puts every hostname under
`yggdrasil.rip` (apex + `*.yggdrasil.rip`, so the whole domain and every app
in it) behind a Cloudflare Access login using the Google identity provider
already configured in Zero Trust → Settings → Authentication. Only the
emails listed in `allowed_emails` (tfvars) can sign in.

Two hostnames are deliberately excluded — `budget-mcp.yggdrasil.rip` and
`sequence-mcp.yggdrasil.rip` (the Claude MCP connectors in
`infrastructure/ansible/vars/mcp_servers.yml`). They authenticate with their
own OAuth-shim bearer tokens rather than an interactive browser login, so a
second, more specific Access Application gives them a `bypass` policy
instead — Access always applies the most specific matching hostname, so this
wins over the domain-wide wildcard for just those two hosts. Add any future
bearer-token/API-only hostname to that bypass application's `destinations`
list rather than the main one, or its clients will start seeing a Google
login page instead of a 401.

**Apply:**

```bash
cd infrastructure/network
terraform init      # first run only, pulls the cloudflare provider
terraform apply
```

Requires `cloudflare_api_token` (account-level "Access: Apps and Policies"
Edit permission) and `cloudflare_account_id` in `terraform.tfvars` — see
`terraform.tfvars.example`.

---

## Terraform Reference

```bash
# Stable network LXCs (pihole, cloudflared) — rarely touch these
cd infrastructure/network
terraform init
terraform apply

# Core VMs/LXCs (draupnir, alexandria) — rebuilt frequently
cd infrastructure/core
terraform init
terraform apply
```
