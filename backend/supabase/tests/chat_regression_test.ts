// Local-only advisor regressions. No OpenAI or hosted Supabase calls.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { requireUser } from "../functions/_shared/auth.ts";
import { parseAttachments, isAttachmentError, MAX_DOCUMENT_CHARS } from "../functions/chat/attachments.ts";
import { advisorModel, type ChatMessage, PRIOR_TURN_CHARS, RECENT_WINDOW_MESSAGES, recentWindow } from "../functions/chat/conversation.ts";
import { classifyScope } from "../functions/chat/scope.ts";
import { streamOpenAIResponse } from "../functions/chat/stream.ts";
import { asUser, createTestDatabase, createUser } from "./harness.ts";

function chunk(content: string | null, reason: string | null = null): string {
  return `data: ${JSON.stringify({ choices: [{ delta: { content }, finish_reason: reason }] })}\n\n`;
}

Deno.test("chat stream: preserves completion reason and trailing memories", async () => {
  const upstream = new Response(chunk("Hello") + chunk(null, "stop") + "data: [DONE]\n\n");
  const text = await streamOpenAIResponse(upstream, () => Promise.resolve([{ type: "memories", items: ["Likes examples."] }])).text();
  assert(text.includes('data: "Hello"'));
  assert(text.includes('"reason":"stop"'));
  assert(text.indexOf('"type":"memories"') > text.indexOf('"type":"finish"'));
  assert(text.endsWith("data: [DONE]\n\n"));
});

Deno.test("chat stream: token limit stays distinguishable from interruption", async () => {
  const text = await streamOpenAIResponse(new Response(chunk("Answer") + chunk(null, "length"))).text();
  assert(text.includes('"reason":"length"'));
});

Deno.test("chat stream: silent upstream disconnect is never labeled successful", async () => {
  const text = await streamOpenAIResponse(new Response(chunk("Half an answer"))).text();
  assert(text.includes('data: "Half an answer"'));
  assert(text.includes('"reason":"interrupted"'));
  assert(!text.includes('"reason":"stop"'));
});

Deno.test("chat stream: empty provider body is an interruption", async () => {
  const text = await streamOpenAIResponse(new Response(null)).text();
  assert(text.includes('"reason":"interrupted"'));
});

Deno.test("chat stream: DONE without a provider completion reason is interrupted", async () => {
  const text = await streamOpenAIResponse(new Response(chunk("Partial") + "data: [DONE]\n\n")).text();
  assert(text.includes('"reason":"interrupted"'));
});

Deno.test("chat history: keeps only a small recent window with bounded older turns", () => {
  const messages: ChatMessage[] = Array.from({ length: 41 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", content: `${i}: ${"a".repeat(8000)}` }));
  const window = recentWindow(messages);
  assertEquals(window.length, RECENT_WINDOW_MESSAGES - 1); // starts with the student's turn
  assertEquals(window[0].role, "user");
  assertEquals(window.at(-1), messages.at(-1));
  assert(window.slice(0, -1).every((m) => m.content.length <= PRIOR_TURN_CHARS + 1));
});

Deno.test("chat attachments: rejects unreadable, oversized, and duplicate files", () => {
  for (const input of [
    [{ type: "document", text: " " }],
    [{ type: "document", text: "a".repeat(MAX_DOCUMENT_CHARS + 1) }],
    [{ type: "document", text: "one" }, { type: "document", text: "two" }],
    [{ type: "image", mime_type: "image/jpeg", data_base64: "invalid!" }],
  ]) assert(isAttachmentError(parseAttachments(input)));
  assert(!isAttachmentError(parseAttachments([{ type: "document", text: "Readable course notes." }])));
});

Deno.test("chat routing: one advisor model; subject-tutoring prompts are redirected for the pilot", () => {
  const env = (vars: Record<string, string>) => (name: string) => vars[name];
  assertEquals(advisorModel(env({ OPENAI_MODEL_CHAT: "advisor", OPENAI_MODEL_TUTOR: "tutor" })), "advisor");
  for (const prompt of ["Walk me through an eigenvalue example", "Help me prove a recurrence by induction", "Explain how BFS works"]) {
    assertEquals(classifyScope(prompt).kind, "redirect", prompt);
  }
  assertEquals(classifyScope("What Computer Science courses should I take next semester?").kind, "advising");
});

Deno.test("chat auth: missing credentials rejected before any external call", async () => {
  const result = await requireUser(new Request("http://localhost/chat"));
  assertEquals(result.response?.status, 401);
});

Deno.test("chat quota: enforces limit, isolates owners, and forbids client writes", async () => {
  const db = await createTestDatabase("006_chat_usage.sql");
  try {
    const alice = await createUser(db, "quota-alice@vt.edu");
    const bob = await createUser(db, "quota-bob@vt.edu");
    for (let i = 1; i <= 3; i++) {
      const result = await db.query("select * from public.consume_chat_quota($1, 3)", [alice]);
      assertEquals(result.rows[0], { allowed: true, used: i });
    }
    const blocked = await db.query("select * from public.consume_chat_quota($1, 3)", [alice]);
    assertEquals(blocked.rows[0], { allowed: false, used: 3 });
    const other = await asUser(db, bob, (tx) => tx.query("select * from public.chat_usage"));
    assertEquals(other.rows.length, 0);
    const own = await asUser(db, alice, (tx) => tx.query("select * from public.chat_usage"));
    assertEquals(own.rows.length, 1);
    await assertRejects(() => asUser(db, alice, (tx) => tx.query("select * from public.consume_chat_quota($1, 3)", [alice])));
    await assertRejects(() => asUser(db, alice, (tx) => tx.query("update public.chat_usage set request_count = 0")));
  } finally { await db.close(); }
});
