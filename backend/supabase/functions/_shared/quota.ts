// Server-side allowances for paid AI calls (migration 010, reserve_ai_quota).
//
// Every paid call reserves one unit BEFORE contacting the provider. The
// reservation is atomic in Postgres, so concurrent requests can't exceed a
// limit. Anything uncertain fails closed: missing server credentials,
// invalid limit settings, an unreachable or slow database, or a reply that
// isn't exactly the expected shape all deny the paid call.
//
// Units are requests, not tokens or dollars. A reserved unit is never
// refunded, so a provider failure after reservation still counts.

import { errorResponse } from "./academic.ts";

export type QuotaKind = "chat" | "document";

export type QuotaLimits = {
  userDaily: number;
  globalDaily: number;
  burst: number;
  burstWindowSeconds: number;
};

type LimitSpec = { env: string; fallback: number; max: number };

// Pilot defaults: configurable per environment, documented in
// docs/MYADVISOR_BACKEND_IMPLEMENTATION.md. Bounds match the SQL checks.
const LIMIT_SPECS: Record<QuotaKind, Record<keyof QuotaLimits, LimitSpec>> = {
  chat: {
    userDaily: { env: "MYADVISOR_CHAT_USER_DAILY_LIMIT", fallback: 10, max: 1000 },
    globalDaily: { env: "MYADVISOR_CHAT_GLOBAL_DAILY_LIMIT", fallback: 250, max: 100000 },
    burst: { env: "MYADVISOR_CHAT_BURST_LIMIT", fallback: 5, max: 100 },
    burstWindowSeconds: { env: "MYADVISOR_CHAT_BURST_WINDOW_SECONDS", fallback: 60, max: 86400 },
  },
  document: {
    userDaily: { env: "MYADVISOR_DOCUMENT_USER_DAILY_LIMIT", fallback: 10, max: 1000 },
    globalDaily: { env: "MYADVISOR_DOCUMENT_GLOBAL_DAILY_LIMIT", fallback: 50, max: 100000 },
    burst: { env: "MYADVISOR_DOCUMENT_BURST_LIMIT", fallback: 3, max: 100 },
    burstWindowSeconds: { env: "MYADVISOR_DOCUMENT_BURST_WINDOW_SECONDS", fallback: 300, max: 86400 },
  },
};

const RPC_TIMEOUT_MS = 5_000;
const REASONS = new Set(["ok", "user_daily", "global_daily", "burst"]);

export type QuotaEnv = (name: string) => string | undefined;

export type QuotaOptions = {
  env?: QuotaEnv;
  fetch?: typeof fetch;
  /** Database round-trip budget; past it the paid call is denied. */
  timeoutMs?: number;
};

/** Reads limits from env. Unset uses the pilot default; set-but-invalid is an error. */
export function quotaLimits(kind: QuotaKind, env: QuotaEnv = (n) => Deno.env.get(n)): QuotaLimits | null {
  const specs = LIMIT_SPECS[kind];
  const limits = {} as QuotaLimits;
  for (const key of Object.keys(specs) as (keyof QuotaLimits)[]) {
    const spec = specs[key];
    const raw = env(spec.env)?.trim();
    if (raw === undefined || raw === "") {
      limits[key] = spec.fallback;
      continue;
    }
    if (!/^\d+$/.test(raw)) return null;
    const value = Number(raw);
    if (!Number.isSafeInteger(value) || value < 1 || value > spec.max) return null;
    limits[key] = value;
  }
  return limits;
}

export type QuotaDecision =
  | { status: "allowed"; userUsed: number; userLimit: number }
  | { status: "denied"; reason: "user_daily" | "global_daily" | "burst"; retryAfterSeconds: number; userLimit: number }
  | { status: "unavailable"; cause: string };

/** Atomically reserves one paid call for this user. Never throws. */
export async function reserveQuota(userId: string, kind: QuotaKind, options: QuotaOptions = {}): Promise<QuotaDecision> {
  const env = options.env ?? ((n: string) => Deno.env.get(n));
  const doFetch = options.fetch ?? fetch;

  const limits = quotaLimits(kind, env);
  if (!limits) return { status: "unavailable", cause: "invalid_limits" };
  const supabaseURL = (env("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseURL || !serviceRoleKey) return { status: "unavailable", cause: "missing_credentials" };
  if (!userId) return { status: "unavailable", cause: "missing_user" };

  let response: Response;
  try {
    response = await doFetch(`${supabaseURL}/rest/v1/rpc/reserve_ai_quota`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_user_id: userId,
        p_kind: kind,
        p_user_daily_limit: limits.userDaily,
        p_global_daily_limit: limits.globalDaily,
        p_burst_limit: limits.burst,
        p_burst_window_seconds: limits.burstWindowSeconds,
      }),
      signal: AbortSignal.timeout(options.timeoutMs ?? RPC_TIMEOUT_MS),
    });
  } catch {
    return { status: "unavailable", cause: "rpc_unreachable" };
  }
  if (!response.ok) {
    await response.body?.cancel().catch(() => {});
    return { status: "unavailable", cause: `rpc_status_${response.status}` };
  }

  let rows: unknown;
  try {
    rows = await response.json();
  } catch {
    return { status: "unavailable", cause: "rpc_malformed" };
  }
  const row = Array.isArray(rows) && rows.length === 1 ? rows[0] as Record<string, unknown> : null;
  if (
    !row || typeof row.allowed !== "boolean" || typeof row.reason !== "string" || !REASONS.has(row.reason) ||
    !isCount(row.user_used) || !isCount(row.retry_after_seconds) ||
    (row.allowed !== (row.reason === "ok"))
  ) {
    return { status: "unavailable", cause: "rpc_malformed" };
  }
  if (row.allowed) return { status: "allowed", userUsed: row.user_used as number, userLimit: limits.userDaily };
  return {
    status: "denied",
    reason: row.reason as "user_daily" | "global_daily" | "burst",
    retryAfterSeconds: Math.max(1, row.retry_after_seconds as number),
    userLimit: limits.userDaily,
  };
}

function isCount(value: unknown): boolean {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

export type QuotaDenial = { status: 429 | 503; code: string; message: string; retryAfterSeconds?: number };

/**
 * What to tell the student instead of making a paid call, or null when the
 * call may proceed. Logs only the cause code, never user data.
 */
export function quotaDenial(decision: QuotaDecision, kind: QuotaKind, codePrefix: string): QuotaDenial | null {
  if (decision.status === "allowed") return null;
  if (decision.status === "unavailable") {
    console.warn(`${codePrefix} quota unavailable: ${decision.cause}`);
    return {
      status: 503,
      code: `${codePrefix}_TEMPORARILY_UNAVAILABLE`,
      message: kind === "chat"
        ? "MyAdvisor is temporarily unavailable. Please try again a little later."
        : "Document reading is temporarily unavailable. Please try again a little later.",
    };
  }
  const noun = kind === "chat" ? "MyAdvisor replies" : "document imports";
  const message = decision.reason === "user_daily"
    ? `You've used today's ${decision.userLimit} ${noun}. They reset at midnight Eastern.`
    : decision.reason === "burst"
    ? `That's a lot of requests in a short time. Try again in ${waitText(decision.retryAfterSeconds)}.`
    : kind === "chat"
    ? "MyAdvisor has reached today's pilot capacity. Please try again after midnight Eastern."
    : "Document reading has reached today's pilot capacity. Please try again after midnight Eastern.";
  const code = decision.reason === "user_daily"
    ? `${codePrefix}_RATE_LIMITED`
    : decision.reason === "burst"
    ? `${codePrefix}_BURST_LIMITED`
    : `${codePrefix}_PILOT_CAPACITY_REACHED`;
  return { status: 429, code, message, retryAfterSeconds: decision.retryAfterSeconds };
}

/** quotaDenial as an HTTP response (with Retry-After), or null to proceed. */
export function quotaRejection(decision: QuotaDecision, kind: QuotaKind, codePrefix: string): Response | null {
  const denial = quotaDenial(decision, kind, codePrefix);
  if (!denial) return null;
  const response = errorResponse(denial.code, denial.message, denial.status);
  if (denial.retryAfterSeconds) response.headers.set("Retry-After", String(denial.retryAfterSeconds));
  return response;
}

function waitText(seconds: number): string {
  if (seconds < 90) return `${seconds} second${seconds === 1 ? "" : "s"}`;
  const minutes = Math.ceil(seconds / 60);
  return `${minutes} minute${minutes === 1 ? "" : "s"}`;
}
