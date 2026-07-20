#!/usr/bin/env python3
"""OAuth 2.1 server with Dynamic Client Registration for Sequence MCP proxy.

Supports authorization code + PKCE (S256), DCR (RFC 7591), and refresh tokens.
Public clients (token_endpoint_auth_method: none) use PKCE only — no secret.
Confidential clients verify client_secret at the token endpoint.
"""
import base64
import os
import hashlib
import html as html_mod
import json
import secrets
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

BASE_URL = os.environ.get("BASE_URL", "https://sequence-mcp.yggdrasil.rip")
ACCESS_TOKEN = os.environ["ACCESS_TOKEN"]
ACCESS_TOKEN_TTL = 86400     # 24 h
REFRESH_TOKEN_TTL = 2592000  # 30 days

# Client registry — pre-registered + dynamically registered clients.
# redirect_uris: empty list means accept any (pre-registered client only).
CLIENTS = {}
if os.environ.get("CLIENT_SECRET"):
    CLIENTS["sequence-mcp"] = {
        "client_secret": os.environ["CLIENT_SECRET"],
        "redirect_uris": [],
        "token_endpoint_auth_method": "client_secret_post",
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "registered_at": 0,
    }

# In-memory state
PENDING_REQS = {}    # req_token  → authorize params (shown to user, pre-click)
PENDING_CODES = {}   # auth_code  → authorize params (post-approval, 60 s TTL)
REFRESH_TOKENS = {}  # token_str  → {client_id, expires_at}

DISCOVERY = {
    "issuer": BASE_URL,
    "authorization_endpoint": f"{BASE_URL}/oauth/authorize",
    "token_endpoint": f"{BASE_URL}/oauth/token",
    "registration_endpoint": f"{BASE_URL}/oauth/register",
    "response_types_supported": ["code"],
    "grant_types_supported": ["authorization_code", "refresh_token"],
    "code_challenge_methods_supported": ["S256"],
    "token_endpoint_auth_methods_supported": [
        "client_secret_post", "client_secret_basic", "none"
    ],
}

PRM = {
    "resource": BASE_URL,
    "authorization_servers": [BASE_URL],
}


def verify_pkce(verifier: str, challenge: str) -> bool:
    digest = hashlib.sha256(verifier.encode()).digest()
    expected = base64.urlsafe_b64encode(digest).rstrip(b"=").decode()
    return secrets.compare_digest(expected, challenge)


def _redirect_uri_ok(client: dict, redirect_uri: str) -> bool:
    allowed = client.get("redirect_uris", [])
    return not allowed or redirect_uri in allowed


class OAuthHandler(BaseHTTPRequestHandler):

    def send_json(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, status, body_html):
        body = body_html.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length).decode())

    def read_form(self):
        length = int(self.headers.get("Content-Length", 0))
        return parse_qs(self.rfile.read(length).decode())

    # ------------------------------------------------------------------
    # Routing
    # ------------------------------------------------------------------

    def do_GET(self):
        parsed = urlparse(self.path)
        path, qs = parsed.path, parse_qs(parsed.query)
        if path == "/.well-known/oauth-authorization-server":
            self.send_json(200, DISCOVERY)
        elif path == "/.well-known/oauth-protected-resource":
            self.send_json(200, PRM)
        elif path == "/oauth/authorize":
            self._authorize_get(qs)
        else:
            self.send_json(404, {"error": "not_found"})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/oauth/token":
            self._token()
        elif path == "/oauth/authorize":
            self._authorize_post()
        elif path == "/oauth/register":
            self._register()
        else:
            self.send_json(404, {"error": "not_found"})

    # ------------------------------------------------------------------
    # Dynamic Client Registration — RFC 7591
    # ------------------------------------------------------------------

    def _register(self):
        try:
            body = self.read_json()
        except (json.JSONDecodeError, ValueError):
            self.send_json(400, {"error": "invalid_request",
                                 "error_description": "Body must be JSON"})
            return

        redirect_uris = body.get("redirect_uris", [])
        grant_types = body.get("grant_types", ["authorization_code"])
        response_types = body.get("response_types", ["code"])
        auth_method = body.get("token_endpoint_auth_method", "client_secret_basic")
        client_name = body.get("client_name", "")

        if auth_method not in ("none", "client_secret_post", "client_secret_basic"):
            auth_method = "client_secret_basic"

        # Ensure refresh_token grant is included alongside authorization_code
        if "authorization_code" in grant_types and "refresh_token" not in grant_types:
            grant_types = list(grant_types) + ["refresh_token"]

        client_id = str(uuid.uuid4())
        # Public clients (auth_method "none") get no secret — PKCE only
        client_secret = None if auth_method == "none" else secrets.token_hex(32)
        now = int(time.time())

        CLIENTS[client_id] = {
            "client_secret": client_secret,
            "redirect_uris": redirect_uris,
            "token_endpoint_auth_method": auth_method,
            "grant_types": grant_types,
            "response_types": response_types,
            "client_name": client_name,
            "registered_at": now,
        }

        resp = {
            "client_id": client_id,
            "client_id_issued_at": now,
            "redirect_uris": redirect_uris,
            "grant_types": grant_types,
            "response_types": response_types,
            "token_endpoint_auth_method": auth_method,
        }
        if client_name:
            resp["client_name"] = client_name
        if client_secret:
            resp["client_secret"] = client_secret
            resp["client_secret_expires_at"] = 0  # never expires

        self.send_json(201, resp)

    # ------------------------------------------------------------------
    # Authorization endpoint
    # ------------------------------------------------------------------

    def _authorize_get(self, qs):
        client_id = qs.get("client_id", [""])[0]
        redirect_uri = qs.get("redirect_uri", [""])[0]
        state = qs.get("state", [""])[0]
        code_challenge = qs.get("code_challenge", [""])[0]
        method = qs.get("code_challenge_method", [""])[0]

        client = CLIENTS.get(client_id)
        if not client:
            self.send_html(400, "<h1>Unknown client</h1>")
            return
        if not _redirect_uri_ok(client, redirect_uri):
            self.send_html(400, "<h1>redirect_uri not registered</h1>")
            return
        if method != "S256":
            self.send_html(400, "<h1>Only S256 PKCE is supported</h1>")
            return
        if not code_challenge:
            self.send_html(400, "<h1>PKCE code_challenge required</h1>")
            return

        req_token = secrets.token_hex(16)
        PENDING_REQS[req_token] = {
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "state": html_mod.escape(state),
            "code_challenge": code_challenge,
            "expires_at": time.time() + 300,
        }

        self.send_html(200, f"""<!DOCTYPE html>
<html><head><title>Authorize Sequence MCP</title>
<style>
  body {{ font-family: sans-serif; max-width: 420px; margin: 80px auto; padding: 20px; }}
  h2 {{ margin-bottom: 8px; }}
  p {{ color: #555; }}
  .buttons {{ margin-top: 24px; display: flex; gap: 10px; }}
  button {{ padding: 10px 24px; border: none; border-radius: 6px; font-size: 15px; cursor: pointer; }}
  .approve {{ background: #22c55e; color: white; }}
  .deny   {{ background: #ef4444; color: white; }}
</style></head><body>
<h2>Authorize Sequence MCP</h2>
<p>claude.ai is requesting access to your Sequence finance account via this proxy.</p>
<form method="post" action="/oauth/authorize">
  <input type="hidden" name="req_token" value="{req_token}">
  <div class="buttons">
    <button type="submit" name="decision" value="approve" class="approve">Approve</button>
    <button type="submit" name="decision" value="deny"    class="deny">Deny</button>
  </div>
</form>
</body></html>""")

    def _authorize_post(self):
        params = self.read_form()
        req_token = params.get("req_token", [""])[0]
        decision = params.get("decision", ["deny"])[0]

        pending = PENDING_REQS.pop(req_token, None)
        if not pending or pending["expires_at"] < time.time():
            self.send_html(400, "<h1>Expired or invalid request</h1>")
            return

        redirect_uri = pending["redirect_uri"]
        state = pending["state"]
        sep = "&" if "?" in redirect_uri else "?"

        if decision != "approve":
            self.send_response(302)
            self.send_header("Location",
                             f"{redirect_uri}{sep}error=access_denied&state={state}")
            self.end_headers()
            return

        code = secrets.token_urlsafe(32)
        PENDING_CODES[code] = {**pending, "expires_at": time.time() + 60}

        self.send_response(302)
        self.send_header("Location", f"{redirect_uri}{sep}code={code}&state={state}")
        self.end_headers()

    # ------------------------------------------------------------------
    # Token endpoint
    # ------------------------------------------------------------------

    def _token(self):
        params = self.read_form()
        grant_type = params.get("grant_type", [""])[0]

        if grant_type == "refresh_token":
            self._token_refresh(params)
        elif grant_type == "authorization_code":
            self._token_authcode(params)
        else:
            self.send_json(400, {"error": "unsupported_grant_type"})

    def _resolve_client(self, params):
        """Return (client_id, client) or send an error and return (None, None)."""
        client_id = params.get("client_id", [""])[0]
        client_secret = params.get("client_secret", [""])[0]

        # client_secret_basic
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Basic "):
            try:
                decoded = base64.b64decode(auth[6:]).decode()
                client_id, _, client_secret = decoded.partition(":")
            except Exception:
                pass

        client = CLIENTS.get(client_id)
        if not client:
            self.send_json(401, {"error": "invalid_client"})
            return None, None

        auth_method = client.get("token_endpoint_auth_method", "client_secret_basic")
        if auth_method != "none":
            stored = client.get("client_secret") or ""
            if not stored or not secrets.compare_digest(client_secret, stored):
                self.send_json(401, {"error": "invalid_client"})
                return None, None

        return client_id, client

    def _token_authcode(self, params):
        client_id, client = self._resolve_client(params)
        if client is None:
            return

        code = params.get("code", [""])[0]
        verifier = params.get("code_verifier", [""])[0]
        redirect_uri = params.get("redirect_uri", [""])[0]

        pending = PENDING_CODES.pop(code, None)
        if not pending or pending["expires_at"] < time.time():
            self.send_json(400, {"error": "invalid_grant"})
            return
        if pending["client_id"] != client_id:
            self.send_json(400, {"error": "invalid_grant"})
            return
        if pending["redirect_uri"] != redirect_uri:
            self.send_json(400, {"error": "invalid_grant"})
            return
        if not verify_pkce(verifier, pending["code_challenge"]):
            self.send_json(400, {"error": "invalid_grant"})
            return

        refresh_token = self._issue_refresh_token(client_id)
        self.send_json(200, {
            "access_token": ACCESS_TOKEN,
            "token_type": "bearer",
            "expires_in": ACCESS_TOKEN_TTL,
            "refresh_token": refresh_token,
        })

    def _token_refresh(self, params):
        client_id, client = self._resolve_client(params)
        if client is None:
            return

        token_str = params.get("refresh_token", [""])[0]
        entry = REFRESH_TOKENS.get(token_str)

        if not entry or entry["expires_at"] < time.time() \
                or entry["client_id"] != client_id:
            self.send_json(400, {"error": "invalid_grant"})
            return

        # Rotate: delete old token, issue new one
        del REFRESH_TOKENS[token_str]
        new_refresh = self._issue_refresh_token(client_id)
        self.send_json(200, {
            "access_token": ACCESS_TOKEN,
            "token_type": "bearer",
            "expires_in": ACCESS_TOKEN_TTL,
            "refresh_token": new_refresh,
        })

    def _issue_refresh_token(self, client_id: str) -> str:
        token_str = secrets.token_urlsafe(48)
        REFRESH_TOKENS[token_str] = {
            "client_id": client_id,
            "expires_at": time.time() + REFRESH_TOKEN_TTL,
        }
        return token_str

    def log_message(self, fmt, *args):
        pass  # silence access log; systemd journal captures stderr


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "3000"))
    server = HTTPServer(("127.0.0.1", port), OAuthHandler)
    print(f"OAuth server listening on 127.0.0.1:{port}", flush=True)
    server.serve_forever()
