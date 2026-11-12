// Shared fakes for chat handler tests: Supabase Auth and REST, the real
// reserve_ai_quota in PGlite, and a counting provider. Dummy credentials only.
import { createTestDatabase, createUser, reserveAsServiceRole } from "./harness.ts";

export const db = await createTestDatabase();
export const ANON = "dummy-anon-key";
export const SERVICE = "dummy-service-role-key";
export const BASE_ENV: Record<string, string> = {
  SUPABASE_URL: "http://supabase.test",
  SUPABASE_ANON_KEY: ANON,
  SUPABASE_SERVICE_ROLE_KEY: SERVICE,
  OPENAI_API_KEY: "sk-dummy-not-a-real-key",
  OPENAI_BASE_URL: "http://provider.test/v1",
  MYADVISOR_CHAT_BURST_LIMIT: "100",
};

export type Mode = { quota: "db" | "error" | "malformed" | "hang"; provider: "ok" | "error" | "empty_length" };
export const state = {
  tokens: new Map<string, string>(),
  providerCalls: [] as Record<string, unknown>[],
  quotaCalls: 0,
  mode: { quota: "db", provider: "ok" } as Mode,
};

export async function router(input: string | URL | Request, init?: RequestInit): Promise<Response> {
  const request = new Request(input, init);
  const url = new URL(request.url);
  if (url.host === "supabase.test" && url.pathname === "/auth/v1/user") {
    const token = (request.headers.get("authorization") ?? "").replace(/^bearer\s+/i, "");
    const id = state.tokens.get(token);
    return id
      ? Response.json({ id, aud: "authenticated", role: "authenticated", email: "student@vt.edu" })
      : Response.json({ msg: "invalid JWT" }, { status: 401 });
  }
  if (url.host === "supabase.test" && url.pathname === "/rest/v1/rpc/reserve_ai_quota") {
    state.quotaCalls++;
    if (request.headers.get("authorization") !== `Bearer ${SERVICE}`) return new Response("forbidden", { status: 401 });
    if (state.mode.quota === "error") return new Response("upstream", { status: 500 });
    if (state.mode.quota === "malformed") return Response.json({ allowed: true });
    if (state.mode.quota === "hang") {
      // Like a real fetch, an unanswered request rejects when its signal aborts.
      return await new Promise((_resolve, reject) =>
        request.signal.addEventListener("abort", () => reject(request.signal.reason))
      );
    }
    return Response.json(await reserveAsServiceRole(db, await request.json()));
  }
  if (url.host === "supabase.test") return Response.json([]); // academic context lookups
  if (url.host === "provider.test" || url.host === "api.openai.com") {
    const body = await request.json();
    state.providerCalls.push(body);
    if (state.mode.provider === "error") return Response.json({ error: { message: "boom" } }, { status: 500 });
    if (url.pathname.endsWith("/responses")) return Response.json({ output_text: JSON.stringify({ courses: [] }) });
    if (state.mode.provider === "empty_length") {
      // A reasoning model that spent its whole budget before writing anything.
      return body.stream
        ? new Response(`data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: "length" }] })}\n\ndata: [DONE]\n\n`)
        : Response.json({ choices: [{ message: { content: "" }, finish_reason: "length" }] });
    }
    if (body.stream) {
      const chunk = (content: string | null, reason: string | null) =>
        `data: ${JSON.stringify({ choices: [{ delta: { content }, finish_reason: reason }] })}\n\n`;
      return new Response(chunk("Take CS 3114 next.", null) + chunk(null, "stop") + "data: [DONE]\n\n", {
        headers: { "Content-Type": "text/event-stream" },
      });
    }
    return Response.json({ choices: [{ message: { content: "Take CS 3114 next." }, finish_reason: "stop" }] });
  }
  return new Response("unexpected host", { status: 599 });
}

export async function withEnv<T>(overrides: Record<string, string | null>, fn: () => Promise<T>): Promise<T> {
  const env = { ...BASE_ENV, ...overrides };
  const saved = new Map<string, string | undefined>();
  for (const [k, v] of Object.entries(env)) {
    saved.set(k, Deno.env.get(k));
    if (v === null) Deno.env.delete(k);
    else Deno.env.set(k, v);
  }
  const realFetch = globalThis.fetch;
  globalThis.fetch = router as typeof fetch;
  try {
    return await fn();
  } finally {
    globalThis.fetch = realFetch;
    for (const [k, v] of saved) v === undefined ? Deno.env.delete(k) : Deno.env.set(k, v);
  }
}

export function reset(mode: Partial<Mode> = {}) {
  state.providerCalls = [];
  state.quotaCalls = 0;
  state.mode = { quota: "db", provider: "ok", ...mode };
}

export async function student(): Promise<{ id: string; token: string }> {
  const id = await createUser(db, `chat-${crypto.randomUUID()}@vt.edu`);
  const token = `session-${crypto.randomUUID()}`;
  state.tokens.set(token, id);
  return { id, token };
}

export function chat(token: string | null, body: unknown, path = "/chat"): Request {
  return new Request(`http://edge.test/functions/v1${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

export const ask = (text = "What should I take after CS 2114?") => ({ messages: [{ role: "user", content: text }] });

export async function used(userId: string, kind = "chat"): Promise<number> {
  const r = await db.query<{ n: number }>(
    "select coalesce(sum(request_count), 0)::int as n from public.ai_usage_daily where user_id = $1 and kind = $2", [userId, kind],
  );
  return r.rows[0].n;
}

export async function resetGlobal() {
  await db.query("delete from public.ai_usage_global_daily");
}

