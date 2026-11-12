"""Protection for the legacy FastAPI routes that can spend OpenAI money.

The iOS app uses the Supabase Edge Functions; this API is legacy. Its paid
routes are OFF unless LEGACY_AI_ROUTES_ENABLED=true. When enabled they get
the same protections as the Edge Functions:

* the caller must present a Supabase user session that Supabase Auth
  verifies (the public anon key alone is rejected), and
* every paid call first reserves one unit through the same database function
  (reserve_ai_quota, migration 010) with the same MYADVISOR_* limits, so both
  backends share one set of counters.

Anything uncertain fails closed with a friendly 503. Nothing here logs tokens,
keys, or request bodies.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Callable, Literal, Optional

import httpx
from fastapi import Header, HTTPException

from app.routes.errors import error_detail

logger = logging.getLogger(__name__)

Kind = Literal["chat", "document"]

# (env var, pilot default, max): mirrors _shared/quota.ts and the SQL bounds.
_LIMITS: dict[str, dict[str, tuple[str, int, int]]] = {
    "chat": {
        "user_daily": ("MYADVISOR_CHAT_USER_DAILY_LIMIT", 10, 1000),
        "global_daily": ("MYADVISOR_CHAT_GLOBAL_DAILY_LIMIT", 250, 100000),
        "burst": ("MYADVISOR_CHAT_BURST_LIMIT", 5, 100),
        "burst_window_seconds": ("MYADVISOR_CHAT_BURST_WINDOW_SECONDS", 60, 86400),
    },
    "document": {
        "user_daily": ("MYADVISOR_DOCUMENT_USER_DAILY_LIMIT", 10, 1000),
        "global_daily": ("MYADVISOR_DOCUMENT_GLOBAL_DAILY_LIMIT", 50, 100000),
        "burst": ("MYADVISOR_DOCUMENT_BURST_LIMIT", 3, 100),
        "burst_window_seconds": ("MYADVISOR_DOCUMENT_BURST_WINDOW_SECONDS", 300, 86400),
    },
}

_TIMEOUT_SECONDS = 5.0
_REASONS = {"ok", "user_daily", "global_daily", "burst"}

Env = Callable[[str], Optional[str]]
# Injectable for tests; production uses a real HTTP client.
http_post: Callable[..., httpx.Response] = httpx.post
http_get: Callable[..., httpx.Response] = httpx.get


def _env(name: str) -> Optional[str]:
    return os.getenv(name)


def _unavailable(cause: str, kind: Kind = "chat") -> HTTPException:
    logger.warning("Legacy AI guard unavailable: %s", cause)
    message = (
        "MyAdvisor is temporarily unavailable. Please try again a little later."
        if kind == "chat"
        else "Document reading is temporarily unavailable. Please try again a little later."
    )
    return HTTPException(status_code=503, detail=error_detail("AI_TEMPORARILY_UNAVAILABLE", message))


def routes_enabled(env: Env = _env) -> bool:
    return (env("LEGACY_AI_ROUTES_ENABLED") or "").strip().lower() == "true"


def quota_limits(kind: Kind, env: Env = _env) -> Optional[dict[str, int]]:
    """Unset uses the pilot default; set-but-invalid returns None (fail closed)."""
    limits: dict[str, int] = {}
    for key, (name, default, maximum) in _LIMITS[kind].items():
        raw = (env(name) or "").strip()
        if not raw:
            limits[key] = default
            continue
        if not raw.isdigit() or not raw.isascii():
            return None
        value = int(raw)
        if value < 1 or value > maximum:
            return None
        limits[key] = value
    return limits


@dataclass(frozen=True)
class VerifiedUser:
    id: str


def verify_user(authorization: Optional[str], env: Env = _env) -> VerifiedUser:
    """Returns the Supabase user for this bearer token, or raises 401/503."""
    if not routes_enabled(env):
        raise HTTPException(
            status_code=503,
            detail=error_detail(
                "LEGACY_AI_DISABLED",
                "This endpoint is turned off for the MyAdvisor pilot. Use the Agora app.",
            ),
        )
    token = ""
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization[len("bearer "):].strip()
    url = (env("SUPABASE_URL") or "").rstrip("/")
    anon_key = env("SUPABASE_ANON_KEY") or ""
    if not token or token == anon_key:
        raise HTTPException(status_code=401, detail=error_detail("AUTH_REQUIRED", "Please sign in to use MyAdvisor."))
    if not url or not anon_key:
        raise _unavailable("auth_not_configured")
    try:
        response = http_get(
            f"{url}/auth/v1/user",
            headers={"apikey": anon_key, "Authorization": f"Bearer {token}"},
            timeout=_TIMEOUT_SECONDS,
        )
    except httpx.HTTPError:
        raise _unavailable("auth_unreachable") from None
    if response.status_code != 200:
        raise HTTPException(
            status_code=401,
            detail=error_detail("AUTH_INVALID_SESSION", "Invalid or expired session. Please sign in again."),
        )
    try:
        user_id = response.json().get("id")
    except ValueError:
        user_id = None
    if not isinstance(user_id, str) or not user_id:
        raise HTTPException(
            status_code=401,
            detail=error_detail("AUTH_INVALID_SESSION", "Invalid or expired session. Please sign in again."),
        )
    return VerifiedUser(id=user_id)


def retired_for_pilot() -> None:
    """Router dependency for legacy AI routes with no pilot scope controls.

    MyAdvisor's scope checks, input bounds, and single advisor model live in
    the chat Edge Function; these routes would bypass them, so they stay off
    for the pilot whatever LEGACY_AI_ROUTES_ENABLED says."""
    raise HTTPException(
        status_code=503,
        detail=error_detail(
            "LEGACY_CHAT_RETIRED",
            "MyAdvisor chat is available only in the Agora app during the pilot.",
        ),
    )


def require_user(authorization: Optional[str] = Header(default=None)) -> VerifiedUser:
    """FastAPI dependency: authentication only (free). Reserve separately."""
    return verify_user(authorization)


def reserve(user: VerifiedUser, kind: Kind, env: Env = _env) -> None:
    """Reserves one paid call immediately before making it, or raises 429/503."""
    if not (env("OPENAI_API_KEY") or ""):
        raise _unavailable("no_provider_key", kind)
    limits = quota_limits(kind, env)
    if limits is None:
        raise _unavailable("invalid_limits", kind)
    url = (env("SUPABASE_URL") or "").rstrip("/")
    service_key = env("SUPABASE_SERVICE_ROLE_KEY") or ""
    if not url or not service_key:
        raise _unavailable("missing_credentials", kind)
    try:
        response = http_post(
            f"{url}/rest/v1/rpc/reserve_ai_quota",
            headers={"apikey": service_key, "Authorization": f"Bearer {service_key}", "Content-Type": "application/json"},
            json={
                "p_user_id": user.id,
                "p_kind": kind,
                "p_user_daily_limit": limits["user_daily"],
                "p_global_daily_limit": limits["global_daily"],
                "p_burst_limit": limits["burst"],
                "p_burst_window_seconds": limits["burst_window_seconds"],
            },
            timeout=_TIMEOUT_SECONDS,
        )
    except httpx.HTTPError:
        raise _unavailable("rpc_unreachable", kind) from None
    if response.status_code != 200:
        raise _unavailable(f"rpc_status_{response.status_code}", kind)
    try:
        rows = response.json()
    except ValueError:
        raise _unavailable("rpc_malformed", kind) from None
    row = rows[0] if isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], dict) else None
    if (
        row is None
        or not isinstance(row.get("allowed"), bool)
        or row.get("reason") not in _REASONS
        or not _is_count(row.get("user_used"))
        or not _is_count(row.get("retry_after_seconds"))
        or row["allowed"] != (row["reason"] == "ok")
    ):
        raise _unavailable("rpc_malformed", kind)
    if row["allowed"]:
        return

    reason = row["reason"]
    retry_after = max(1, row["retry_after_seconds"])
    noun = "MyAdvisor replies" if kind == "chat" else "document imports"
    if reason == "user_daily":
        code, message = "AI_RATE_LIMITED", f"You've used today's {limits['user_daily']} {noun}. They reset at midnight Eastern."
    elif reason == "burst":
        code, message = "AI_BURST_LIMITED", "That's a lot of requests in a short time. Try again shortly."
    else:
        code, message = "AI_PILOT_CAPACITY_REACHED", "Today's pilot capacity has been reached. Please try again after midnight Eastern."
    raise HTTPException(status_code=429, detail=error_detail(code, message), headers={"Retry-After": str(retry_after)})


def _is_count(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0
