# =============================================================================
# CLOUDFLARE ZERO TRUST ACCESS — Google SSO in front of yggdrasil.rip
# =============================================================================
#
# Gates the bare yggdrasil.rip homepage behind a Cloudflare Access login using
# the Google identity provider you already added in Zero Trust → Settings →
# Authentication. Only the email addresses in var.allowed_emails may sign in.
#
# NOTE ON *.yggdrasil.rip: the actual wildcard covering every subdomain is
# the pre-existing, dashboard-managed "Odin" Access Application — NOT
# anything in this file. Terraform doesn't own it; don't recreate it here
# (a second app on the same destination 409s — Cloudflare enforces
# destinations as unique across every self-hosted app in the account). This
# file only adds the apex on top of Odin's wildcard, plus narrower
# bypass apps below for hosts that must NOT require interactive login.
# Cloudflare does allow a more-specific destination (e.g. one exact
# hostname) to be created after a wildcard app already exists — confirmed
# live 2026-08-08 via the Jellyfin bypass below — it's only "new wildcard
# on top of existing specifics" that gets rejected.
#
# EXCLUDED on purpose:
#   - budget-mcp.yggdrasil.rip / sequence-mcp.yggdrasil.rip
#     (infrastructure/ansible/vars/mcp_servers.yml) — Claude MCP connectors
#     authenticated by their own OAuth-shim bearer tokens, not interactive
#     browser logins. Required Google SSO would break Claude's connection.
#   - ab.yggdrasil.rip — the actual Actual Budget server itself. The
#     mcp-budget service on hermod calls this as a JSON API backend; when
#     Odin's wildcard gated it, Access returned its HTML login redirect
#     instead of JSON and the MCP connector died with a parse error
#     (confirmed live 2026-08-14). Has its own password auth already.
#   - jellyfin.yggdrasil.rip (apps/k8s/knarr/jellyfin) — TVs/set-top boxes
#     can't complete an interactive SSO redirect, so Jellyfin needs to stay
#     reachable without the Access gate. Relies on Jellyfin's own login.
#   - audiobookshelf.yggdrasil.rip (apps/k8s/knarr/audiobookshelf) — same
#     problem as Jellyfin: the Audiobookshelf mobile app can't complete an
#     interactive SSO redirect, so login from the app broke once Odin's
#     wildcard started gating it (confirmed live 2026-09-15). Relies on
#     Audiobookshelf's own login.
#   - the *arr stack (Sonarr, Sonarr-anime, Radarr, Prowlarr, Lidarr,
#     Chaptarr), qBittorrent, SABnzbd and Seer — subdomains and their
#     yggdrasil.rip/<path> routes. Double SSO was a hassle; each app's own
#     login (set to Required) stands.
#   - tunarr.yggdrasil.rip — ONLY its M3U/XMLTV/stream/HDHomeRun paths, so
#     IPTV clients and Jellyfin Live TV can fetch them. Tunarr has no login,
#     so its web UI stays behind Odin's Google SSO.
# Each group gets its own bypass Access Application below, leaving their
# existing auth (Caddy / Actual's password / each app's own login)
# untouched. Add any future no-interactive-login hostname the
# same way.
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

# --- MCP API endpoints + their backends: bypass Access, own auth stands ---

resource "cloudflare_zero_trust_access_application" "yggdrasil_mcp_bypass" {
  account_id           = var.cloudflare_account_id
  name                 = "Yggdrasil MCP (Access bypass)"
  type                 = "self_hosted"
  app_launcher_visible = false

  destinations = [
    { type = "public", uri = "budget-mcp.yggdrasil.rip" },
    { type = "public", uri = "sequence-mcp.yggdrasil.rip" },
    { type = "public", uri = "ab.yggdrasil.rip" },
  ]

  policies = [{
    name       = "Bypass Access — Caddy handles auth"
    decision   = "bypass"
    precedence = 1
    include    = [{ everyone = {} }]
  }]
}

# --- Jellyfin: bypass Access, TVs/set-top boxes can't do interactive SSO ---

resource "cloudflare_zero_trust_access_application" "jellyfin_bypass" {
  account_id           = var.cloudflare_account_id
  name                 = "Jellyfin (Access bypass)"
  type                 = "self_hosted"
  app_launcher_visible = false

  destinations = [
    { type = "public", uri = "jellyfin.yggdrasil.rip" },
    # Path-based route (apps/k8s/knarr/paths-ingress.yaml) added manually in
    # the dashboard after this app was first created — folded in here so
    # Terraform doesn't revert it on the next apply.
    { type = "public", uri = "yggdrasil.rip/jelly" },
  ]

  policies = [{
    name       = "Bypass Access — Jellyfin handles its own login"
    decision   = "bypass"
    precedence = 1
    include    = [{ everyone = {} }]
  }]
}

# --- Audiobookshelf: bypass Access, mobile app can't do interactive SSO ---

resource "cloudflare_zero_trust_access_application" "audiobookshelf_bypass" {
  account_id           = var.cloudflare_account_id
  name                 = "Audiobookshelf (Access bypass)"
  type                 = "self_hosted"
  app_launcher_visible = false

  destinations = [
    { type = "public", uri = "audiobookshelf.yggdrasil.rip" },
  ]

  policies = [{
    name       = "Bypass Access — Audiobookshelf handles its own login"
    decision   = "bypass"
    precedence = 1
    include    = [{ everyone = {} }]
  }]
}

# --- *arr stack, downloaders, Seer: bypass Access, each app's own login ----
# Every app below has its own auth set to "Required" (not "Disabled for
# Local Addresses" — tunnel traffic arrives from inside the cluster, so that
# setting would leave them open to the internet). Re-check that before
# adding anything here.

resource "cloudflare_zero_trust_access_application" "arr_stack_bypass" {
  account_id           = var.cloudflare_account_id
  name                 = "*arr stack (Access bypass)"
  type                 = "self_hosted"
  app_launcher_visible = false

  destinations = [
    { type = "public", uri = "sonarr.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/sonarr" },
    { type = "public", uri = "anime.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/crunchy" },
    { type = "public", uri = "radarr.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/radarr" },
    { type = "public", uri = "prowlarr.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/prowlarr" },
    { type = "public", uri = "lidarr.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/lidarr" },
    { type = "public", uri = "chaptarr.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/chaptarr" },
    { type = "public", uri = "qbit.yggdrasil.rip" },
    { type = "public", uri = "sabnzbd.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/sab" },
    { type = "public", uri = "seer.yggdrasil.rip" },
    { type = "public", uri = "yggdrasil.rip/seer" },
  ]

  policies = [{
    name       = "Bypass Access — each app handles its own login"
    decision   = "bypass"
    precedence = 1
    include    = [{ everyone = {} }]
  }]
}

# --- Tunarr: bypass Access for the stream/guide endpoints only ------------
# Tunarr has no login of its own, so the web UI stays behind Odin's Google
# SSO. Only the paths IPTV clients and Jellyfin's Live TV fetch
# non-interactively are opened: M3U playlist, XMLTV guide, the streams, and
# the HDHomeRun emulation endpoints.

resource "cloudflare_zero_trust_access_application" "tunarr_streams_bypass" {
  account_id           = var.cloudflare_account_id
  name                 = "Tunarr streams (Access bypass)"
  type                 = "self_hosted"
  app_launcher_visible = false

  destinations = [
    { type = "public", uri = "tunarr.yggdrasil.rip/api/channels.m3u" },
    { type = "public", uri = "tunarr.yggdrasil.rip/api/xmltv.xml" },
    { type = "public", uri = "tunarr.yggdrasil.rip/stream" },
    { type = "public", uri = "tunarr.yggdrasil.rip/media-player" },
    { type = "public", uri = "tunarr.yggdrasil.rip/discover.json" },
    { type = "public", uri = "tunarr.yggdrasil.rip/lineup.json" },
    { type = "public", uri = "tunarr.yggdrasil.rip/lineup_status.json" },
    { type = "public", uri = "tunarr.yggdrasil.rip/device.xml" },
  ]

  policies = [{
    name       = "Bypass Access — stream/guide endpoints, UI stays gated"
    decision   = "bypass"
    precedence = 1
    include    = [{ everyone = {} }]
  }]
}
