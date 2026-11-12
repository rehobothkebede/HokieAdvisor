export type ChatMessage = {
  role: "user" | "assistant";
  content: string;
};

// Only the newest turns are sent to the model; older ones are dropped, not
// summarized, so prompt size can't grow with the conversation. Saved
// conversations on the device are untouched; this only limits what is sent.
export const RECENT_WINDOW_MESSAGES = 6;
/** Older turns in the window are shortened to this many characters. */
export const PRIOR_TURN_CHARS = 1500;

export function recentWindow(messages: ChatMessage[]): ChatMessage[] {
  const recent = messages.slice(-RECENT_WINDOW_MESSAGES);
  // The model must see a conversation that starts with the student.
  while (recent.length > 1 && recent[0].role !== "user") recent.shift();
  return recent.map((message, index) =>
    index === recent.length - 1 || message.content.length <= PRIOR_TURN_CHARS
      ? message
      : { ...message, content: `${message.content.slice(0, PRIOR_TURN_CHARS)}…` }
  );
}

type Env = (name: string) => string | undefined;
const denoEnv: Env = (name) => Deno.env.get(name);

/** The one advisor model. Clients can't choose it; older tutor settings are ignored. */
export function advisorModel(env: Env = denoEnv): string {
  return env("OPENAI_MODEL_ADVISOR") || env("OPENAI_MODEL_CHAT") || env("OPENAI_MODEL") || "gpt-5.4-nano";
}

// Reasoning models spend part of max_completion_tokens on hidden reasoning
// before any visible text. 1,200 leaves room for low-effort reasoning plus a
// concise ~250-400 word answer. Bounded so a setting can't raise it far.
export const DEFAULT_MAX_COMPLETION_TOKENS = 1200;
const MIN_COMPLETION_TOKENS = 400;
const MAX_COMPLETION_TOKENS_CAP = 2000;

export function maxCompletionTokens(env: Env = denoEnv): number | null {
  const raw = env("CHAT_MAX_COMPLETION_TOKENS")?.trim();
  if (!raw) return DEFAULT_MAX_COMPLETION_TOKENS;
  if (!/^\d+$/.test(raw)) return null;
  const value = Number(raw);
  return value >= MIN_COMPLETION_TOKENS && value <= MAX_COMPLETION_TOKENS_CAP ? value : null;
}

const EFFORTS = new Set(["none", "minimal", "low", "medium"]);

/**
 * reasoning_effort sent to the provider. Defaults to "low" so most of the
 * budget goes to the answer. CHAT_REASONING_EFFORT=off omits the parameter
 * for a model that doesn't accept it. Invalid values are a config error.
 */
export function reasoningEffort(env: Env = denoEnv): string | undefined | null {
  const raw = env("CHAT_REASONING_EFFORT")?.trim().toLowerCase();
  if (!raw) return "low";
  if (raw === "off") return undefined;
  return EFFORTS.has(raw) ? raw : null;
}
