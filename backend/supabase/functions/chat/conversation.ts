export type ChatMessage = {
  role: "user" | "assistant";
  content: string;
};

export const FULL_HISTORY_MESSAGES = 12;
const EARLIER_TURN_CHARS = 200;
const EARLIER_DIGEST_CHARS = 2000;

// Keeps the last FULL_HISTORY_MESSAGES turns verbatim and folds the student's
// earlier questions into a short digest, so prompt size stops growing with the
// conversation. Earlier assistant answers are dropped; the digest is enough to
// keep the thread's topic without paying for old long answers again.
export function trimHistory(messages: ChatMessage[]): { recent: ChatMessage[]; earlierDigest: string } {
  if (messages.length <= FULL_HISTORY_MESSAGES) {
    return { recent: messages, earlierDigest: "" };
  }

  const earlier = messages.slice(0, -FULL_HISTORY_MESSAGES);
  const recent = messages.slice(-FULL_HISTORY_MESSAGES);
  const lines: string[] = [];
  let used = 0;
  for (const message of earlier) {
    if (message.role !== "user") continue;
    const text = message.content.replace(/\s+/g, " ").trim();
    const line = `- ${text.length > EARLIER_TURN_CHARS ? `${text.slice(0, EARLIER_TURN_CHARS)}…` : text}`;
    if (used + line.length > EARLIER_DIGEST_CHARS) break;
    lines.push(line);
    used += line.length;
  }

  return {
    recent,
    earlierDigest: lines.length
      ? `Earlier in this conversation (older turns summarized), the student asked:\n${lines.join("\n")}`
      : "",
  };
}

const TUTOR_KEYWORDS = new RegExp(
  "\\b(" + [
    "proofs?",
    "prove",
    "induction",
    "lemma",
    "theorem",
    "matri(x|ces)",
    "eigen\\w*",
    "determinant",
    "vector",
    "integral",
    "derivative",
    "recurrence",
    "big[- ]?o",
    "complexity",
    "algorithms?",
    "bfs",
    "dfs",
    "dijkstra",
    "graph",
    "tree",
    "heap",
    "hash",
    "recursion",
    "pointer",
    "debug\\w*",
    "compile\\w*",
    "segfault",
    "equation",
    "homework",
    "problem set",
  ].join("|") + ")\\b",
  "i",
);

// Coursework help (math, proofs, algorithms, code, or anything with an
// attachment) goes to the tutor model; planning and advising stay on the chat
// model. Both fall back to OPENAI_MODEL, then the default.
export function isTutorRequest(latestMessage: string, hasAttachment = false): boolean {
  if (hasAttachment) return true;
  if (/\$[^$\s][^$]*\$|\\\(|\\\[|\\begin\{|```/.test(latestMessage)) return true;
  return TUTOR_KEYWORDS.test(latestMessage);
}

export function chooseModel(latestMessage: string, hasAttachment = false): { model: string; kind: "chat" | "tutor" } {
  const base = Deno.env.get("OPENAI_MODEL") || "gpt-5.4-nano";
  const chatModel = Deno.env.get("OPENAI_MODEL_CHAT") || base;
  if (isTutorRequest(latestMessage, hasAttachment)) {
    return { model: Deno.env.get("OPENAI_MODEL_TUTOR") || chatModel, kind: "tutor" };
  }
  return { model: chatModel, kind: "chat" };
}
