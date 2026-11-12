"""Legacy FastAPI routes can't bypass MyAdvisor's auth and allowances.

Supabase Auth, the reserve_ai_quota RPC, and OpenAI are all faked; the SQL
semantics of reserve_ai_quota are covered by the Deno PGlite tests.
"""
from __future__ import annotations

import io
from types import SimpleNamespace

import httpx
import pytest
from fastapi.testclient import TestClient
from openai import APITimeoutError

from app.main import app
from app.services import ai_guard, ai_service, dars_audit_service, transcript_service

VALID = "valid-session-token"
USER_ID = "11111111-1111-1111-1111-111111111111"


class FakeSupabase:
    def __init__(self):
        self.mode = "db"  # db | error | malformed | unreachable
        self.limit_override = None
        self.used: dict[tuple[str, str], int] = {}
        self.rpc_calls: list[dict] = []
        self.auth_up = True

    def get(self, url, headers=None, timeout=None):
        assert url == "http://supabase.test/auth/v1/user"
        if not self.auth_up:
            raise httpx.ConnectError("down")
        token = headers["Authorization"].removeprefix("Bearer ")
        if token == VALID:
            return httpx.Response(200, json={"id": USER_ID, "role": "authenticated"})
        return httpx.Response(401, json={"msg": "invalid JWT"})

    def post(self, url, headers=None, json=None, timeout=None):
        assert url == "http://supabase.test/rest/v1/rpc/reserve_ai_quota"
        assert headers["Authorization"] == "Bearer dummy-service-role-key"
        self.rpc_calls.append(json)
        if self.mode == "unreachable":
            raise httpx.ReadTimeout("slow")
        if self.mode == "error":
            return httpx.Response(500, text="boom")
        if self.mode == "malformed":
            return httpx.Response(200, json={"allowed": True})
        key = (json["p_user_id"], json["p_kind"])
        used = self.used.get(key, 0)
        if used >= json["p_user_daily_limit"]:
            row = {"allowed": False, "reason": "user_daily", "user_used": used, "retry_after_seconds": 3600}
        else:
            self.used[key] = used + 1
            row = {"allowed": True, "reason": "ok", "user_used": used + 1, "retry_after_seconds": 0}
        return httpx.Response(200, json=[{**row, "user_limit": json["p_user_daily_limit"], "global_used": 0, "global_limit": 250}])


class FakeOpenAI:
    def __init__(self):
        self.calls = 0
        self.fail_with = None
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self.create))

    def create(self, **kwargs):
        self.calls += 1
        if self.fail_with:
            raise self.fail_with
        if kwargs.get("stream"):
            chunk = SimpleNamespace(choices=[SimpleNamespace(delta=SimpleNamespace(content="Plan"), finish_reason="stop")])
            return iter([chunk])
        content = '{"recommended_courses": [], "reasoning": "", "warnings": [], "resources": [], "tips": [], "encouragement": "", "courses": [], "in_progress_courses": []}'
        if "response_format" not in kwargs:
            content = "Take CS 3114 next."
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=content), finish_reason="stop")])


@pytest.fixture
def env(monkeypatch):
    supabase = FakeSupabase()
    openai = FakeOpenAI()
    monkeypatch.setattr(ai_guard, "http_get", supabase.get)
    monkeypatch.setattr(ai_guard, "http_post", supabase.post)
    for module in (ai_service, transcript_service, dars_audit_service):
        monkeypatch.setattr(module, "client", openai)
    # The plan route scrapes the public VT catalog; tests stay offline.
    from app.routes import advisor
    monkeypatch.setattr(advisor, "scrape_vt_major_catalog", lambda major: {"required_courses": []})
    monkeypatch.setattr(advisor, "load_courses", lambda subject: [])
    monkeypatch.setenv("LEGACY_AI_ROUTES_ENABLED", "true")
    return SimpleNamespace(supabase=supabase, openai=openai, client=TestClient(app), monkeypatch=monkeypatch)


CHAT = {"messages": [{"role": "user", "content": "What should I take after CS 2114?"}]}
PLAN = {"json": {"completed_courses": [], "major": "Computer Science"}}


def paid_requests():
    """Legacy routes that can still make a paid call (behind the flag)."""
    return [
        ("post", "/advisor/plan", PLAN),
        ("post", "/transcript/upload", {"files": {"file": ("t.png", io.BytesIO(b"\x89PNG fake"), "image/png")}}),
        ("post", "/advisor/dars/upload", {"files": {"file": ("d.png", io.BytesIO(b"\x89PNG fake"), "image/png")}}),
    ]


def test_legacy_chat_and_tutoring_are_retired_for_the_pilot(env):
    for path, body in [("/chat", CHAT), ("/chat/stream", CHAT), ("/tutoring/recommend", {"struggling_courses": ["CS 2114"]})]:
        response = call(env.client, "post", path, {"json": body})
        assert response.status_code == 503, path
        assert response.json()["detail"]["code"] == "LEGACY_CHAT_RETIRED"
    assert env.openai.calls == 0 and env.supabase.rpc_calls == []


def call(client, method, path, kwargs, token=VALID):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return getattr(client, method)(path, headers=headers, **kwargs)


def test_paid_routes_are_off_unless_explicitly_enabled(env):
    env.monkeypatch.delenv("LEGACY_AI_ROUTES_ENABLED")
    for method, path, kwargs in paid_requests():
        response = call(env.client, method, path, kwargs)
        assert response.status_code == 503, path
        assert response.json()["detail"]["code"] == "LEGACY_AI_DISABLED"
    assert env.openai.calls == 0 and env.supabase.rpc_calls == []


@pytest.mark.parametrize("token", [None, "dummy-anon-key", "forged-token"])
def test_paid_routes_need_a_verified_user(env, token):
    for method, path, kwargs in paid_requests():
        response = call(env.client, method, path, kwargs, token=token)
        assert response.status_code == 401, (path, token)
    assert env.openai.calls == 0 and env.supabase.rpc_calls == []


def test_auth_outage_fails_closed(env):
    env.supabase.auth_up = False
    response = call(env.client, "post", "/advisor/plan", PLAN)
    assert response.status_code == 503
    assert env.openai.calls == 0


def test_each_paid_route_reserves_once_for_the_verified_user(env):
    for method, path, kwargs in paid_requests():
        before = (env.openai.calls, len(env.supabase.rpc_calls))
        response = call(env.client, method, path, {**kwargs, **({"json": {**kwargs["json"], "user_id": "someone-else"}} if "json" in kwargs else {})})
        assert response.status_code == 200, (path, response.text)
        assert (env.openai.calls - before[0], len(env.supabase.rpc_calls) - before[1]) == (1, 1), path
    kinds = [c["p_kind"] for c in env.supabase.rpc_calls]
    assert kinds == ["chat", "document", "document"]
    assert {c["p_user_id"] for c in env.supabase.rpc_calls} == {USER_ID}
    assert {c["p_user_daily_limit"] for c in env.supabase.rpc_calls} == {10}


def test_daily_limit_blocks_the_eleventh_request_without_a_paid_call(env):
    for _ in range(10):
        assert call(env.client, "post", "/advisor/plan", PLAN).status_code == 200
    denied = call(env.client, "post", "/advisor/plan", PLAN)
    assert denied.status_code == 429
    assert denied.headers["retry-after"] == "3600"
    assert "10 MyAdvisor replies" in denied.json()["detail"]["message"]
    assert env.openai.calls == 10


def test_document_allowance_is_separate_from_chat(env):
    env.monkeypatch.setenv("MYADVISOR_CHAT_USER_DAILY_LIMIT", "1")
    assert call(env.client, "post", "/advisor/plan", PLAN).status_code == 200
    assert call(env.client, "post", "/advisor/plan", PLAN).status_code == 429
    method, path, kwargs = paid_requests()[1]
    assert call(env.client, method, path, kwargs).status_code == 200


@pytest.mark.parametrize("mode", ["error", "malformed", "unreachable"])
def test_quota_outage_or_bad_reply_fails_closed(env, mode):
    env.supabase.mode = mode
    response = call(env.client, "post", "/advisor/plan", PLAN)
    assert response.status_code == 503
    assert "temporarily unavailable" in response.json()["detail"]["message"]
    assert env.openai.calls == 0


@pytest.mark.parametrize("name,value", [
    ("MYADVISOR_CHAT_USER_DAILY_LIMIT", "lots"),
    ("MYADVISOR_CHAT_GLOBAL_DAILY_LIMIT", "0"),
    ("MYADVISOR_CHAT_BURST_LIMIT", "1.5"),
    ("SUPABASE_SERVICE_ROLE_KEY", ""),
    ("OPENAI_API_KEY", ""),
])
def test_missing_or_invalid_configuration_fails_closed(env, name, value):
    env.monkeypatch.setenv(name, value)
    response = call(env.client, "post", "/advisor/plan", PLAN)
    assert response.status_code == 503
    assert env.openai.calls == 0 and env.supabase.rpc_calls == []


def test_invalid_requests_cost_nothing(env):
    assert call(env.client, "post", "/advisor/plan", {"json": {"completed_courses": [], "major": ""}}).status_code == 400
    empty_pdf = {"files": {"file": ("t.pdf", io.BytesIO(b"%PDF-1.4\n%%EOF"), "application/pdf")}}
    assert call(env.client, "post", "/transcript/upload", empty_pdf).status_code >= 400
    assert env.supabase.rpc_calls == [] and env.openai.calls == 0


def test_provider_failure_counts_once_is_not_retried_and_hides_details(env):
    env.openai.fail_with = APITimeoutError(request=httpx.Request("POST", "http://provider.test"))
    response = call(env.client, "post", "/advisor/plan", PLAN)
    assert response.status_code == 502
    assert "Timeout" not in response.text and "provider.test" not in response.text
    assert env.openai.calls == 1
    assert len(env.supabase.rpc_calls) == 1


def test_sdk_clients_never_retry_on_their_own():
    for module in (ai_service, transcript_service, dars_audit_service):
        assert module.client.max_retries == 0


def test_admin_routes_need_a_server_side_admin_token(env, monkeypatch):
    assert env.client.get("/admin/seed-coe/status").status_code == 503
    monkeypatch.setenv("ADMIN_API_TOKEN", "dummy-admin-token")
    assert env.client.get("/admin/seed-coe/status").status_code == 401
    assert env.client.get("/admin/seed-coe/status", headers={"X-Admin-Token": "wrong"}).status_code == 401
    assert env.client.get("/admin/seed-coe/status", headers={"Authorization": f"Bearer {VALID}"}).status_code == 401
    assert env.client.get("/admin/seed-coe/status", headers={"X-Admin-Token": "dummy-admin-token"}).status_code == 200
