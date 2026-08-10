# =============================================================================
# CLOUDFLARE ZERO TRUST ACCESS — Google SSO in front of yggdrasil.rip
# =============================================================================
#
# Gates the bare yggdrasil.rip homepage behind a Cloudflare Access login using
# the Google identity provider you already added in Zero Trust → Settings →
# Authentication. Only the email addresses in var.allowed_emails may sign in.
#
# NOT a wildcard: Cloudflare enforces destinations as unique across every
# self-hosted Access Application in the account — a *.yggdrasil.rip app
# cannot coexist with the narrower per-subdomain apps that already exist
# (DripProtect on drip.yggdrasil.rip, Odin on asguard.yggdrasil.rip, ssh on
# njord.yggdrasil.rip, plus the MCP-bypass app below), it 409s outright
# rather than yielding to them by precedence. Confirmed live 2026-08-07.
# So this app covers only the apex; any NEW subdomain you want Google-gated
# needs either its own destination added here or its own Access Application —
# it will not be picked up automatically.
#
# EXCLUDED on purpose: budget-mcp.yggdrasil.rip and sequence-mcp.yggdrasil.rip
# (infrastructure/ansible/vars/mcp_servers.yml). Those are Claude MCP
# connectors authenticated by their own OAuth-shim bearer tokens, not
# interactive browser logins — wrapping them in required Google SSO would
# break Claude's connection to them. They get their own bypass Access
# Application (below) instead, leaving their existing Caddy-level auth
# untouched.
#
# Requires a Cloudflare API token with the "Access: Apps and Policies" (Edit)
# and "Access: Organizations, Identity Providers, and Groups" (Read)
# account-level permissions — see terraform.tfvars.example.
# =============================================================================

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Find the Google IdP you already configured in Zero Trust, instead of
# re-declaring (and risking a duplicate of) it here.
data "cloudflare_zero_trust_access_identity_providers" "all" {
  account_id = var.cloudflare_account_id
}

locals {
  # "google" = consumer Google OAuth ("Sign in with Google"); "google-apps" =
  # Google Workspace restricted to a domain. Match whichever you configured.
  google_idp_ids = [
    for idp in data.cloudflare_zero_trust_access_identity_providers.all.result :
    idp.id if contains(["google", "google-apps"], idp.type)
  ]
  google_idp_id = one(local.google_idp_ids)
}

check "google_idp_present" {
  assert {
    condition     = local.google_idp_id != null
    error_message = "No Google identity provider found in this Cloudflare account (Zero Trust -> Settings -> Authentication). Add one before applying, or if you have more than one Google-type IdP, edit local.google_idp_id to pick explicitly."
  }
}

# --- yggdrasil.rip apex (homepage): Google-gated ---------------------------

resource "cloudflare_zero_trust_access_application" "yggdrasil" {
  account_id                = var.cloudflare_account_id
  name                      = "Yggdrasil"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
  app_launcher_visible      = false
  allowed_idps              = [local.google_idp_id]

  destinations = [
    { type = "public", uri = "yggdrasil.rip" },
  ]

  policies = [{
    name       = "Allow Google SSO — approved emails"
    decision   = "allow"
    precedence = 1
    include = [
      for email in var.allowed_emails : { email = { email = email } }
    ]
  }]
}

# --- MCP API endpoints: bypass Access, keep their own bearer-token auth ---

resource "cloudflare_zero_trust_access_application" "yggdrasil_mcp_bypass" {
  account_id           = var.cloudflare_account_id
  name                 = "Yggdrasil MCP (Access bypass)"
  type                 = "self_hosted"
  app_launcher_visible = false

  destinations = [
    { type = "public", uri = "budget-mcp.yggdrasil.rip" },
    { type = "public", uri = "sequence-mcp.yggdrasil.rip" },
  ]

  policies = [{
    name       = "Bypass Access — Caddy handles auth"
    decision   = "bypass"
    precedence = 1
    include    = [{ everyone = {} }]
  }]
}
