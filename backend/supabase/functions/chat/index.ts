import { requireUser } from "../_shared/auth.ts";
import { buildAcademicContext, type TranscriptEntry } from "./context.ts";
import { type ChatMessage, chooseModel, trimHistory } from "./conversation.ts";
import { hasAttachments, isAttachmentError, parseAttachments, userContent } from "./attachments.ts";
import { extractMemories } from "./memory.ts";

type ChatRequest = {
  messages?: unknown[];
  major?: string;
  transcript?: TranscriptEntry[];
  in_progress_courses?: string[];
  transcript_notes?: string[];
  chat_memories?: string[];
  attachments?: unknown;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_MESSAGES = 40;
const MAX_MESSAGE_CHARS = 8000;
const DEFAULT_DAILY_LIMIT = 60;
const MAX_COMPLETION_TOKENS = 4000;

// Institution-specific rules. When migration 005 is live this comes from
// institutions.prompt_context for the student's institution.
const VT_PROMPT_CONTEXT = `Institution: Virginia Tech.
- C or better means C, C+, B-, B, B+, A-, A, or A+. C- does not satisfy C-or-better requirements.
- Treat transfer/awarded credit grades such as T, TR, TRANSFER, P, CR, or CREDIT as satisfying exact mapped VT course codes.
- The official DARS audit is the source of truth when it disagrees with the Hokie Advisor audit.`;

const systemPrompt = `You are Hokie Advisor, a personalized academic advisor and CS/math tutor for Virginia Tech students.

Operating rules:
- If the student asks about degree planning, scheduling, prerequisites, grades, transcripts, or audits, answer as an academic advisor.
- If the student asks about course material, programming, math, proofs, algorithms, or debugging, answer as a tutor.
- Use the student's transcript, audit, and requirement context when provided. Do not ask them to check their transcript or audit if the answer is available in context.
- For "what do I still need to graduate?", combine the program requirements, the latest audits, and the transcript; list what remains and note anything that needs an advisor's confirmation.
- For course recommendations, only suggest courses whose prerequisites the student has met (or is completing this term), and say which requirement each one fills.
- For transcript rulings, answer yes/no first, then explain the specific courses and grades.
- Never fabricate requirements. If a requirement is not in context, say what is known and what still needs confirmation.
- When the student attaches a photo or document, work from what it actually shows. If part of it is unreadable, say which part instead of guessing.
- Be concise, warm, and concrete. Prefer short paragraphs and bullets.
- For math, algorithms, proofs, matrices, and recurrence relations, use LaTeX where helpful.
- For graph theory, trees, paths, circuits, BFS/DFS, shortest paths, state machines, or prerequisite chains, include a fenced graph block the app renders as a diagram, then explain it in 2-4 short bullets.

Graph block format (one item per line; operators need a space on each side):
- \`A - B\` undirected edge; \`A -> B\` directed edge (drawn with an arrow)
- \`A - B : 4\` weighted edge (weights show on the edge)
- Node names may contain hyphens or spaces (\`CS-2114 -> CS-3114\`); quote names that contain " - " or ":" (\`"Intro: Part 1" -> B\`)
- A line with just a name adds an isolated node
- \`directed: true\` makes every edge directed
- \`highlight: A -> B -> D\` highlights a path (nodes and edges); \`highlight: A, C\` highlights nodes only
- \`step: <path or nodes> | <caption>\` adds a frame the student steps through with Next/Prev; use one step per algorithm iteration
- Keep it under 40 nodes. Do not put other text inside the block.

Example (BFS from A):
\`\`\`graph
A - B
A - C
B - D
C - D
D - E
step: A | Start at A; queue = [A]
step: A, B, C | Visit A's neighbors B and C; queue = [B, C]
step: A, B, C, D | From B, discover D; queue = [C, D]
step: A, B, C, D, E | From D, discover E; every node reached
highlight: A -> B -> D -> E
\`\`\``;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return errorJSON("METHOD_NOT_ALLOWED", "Method not allowed.", 405);
  }

  const auth = await requireUser(req);
  if (auth.response) return auth.response;

  let body: ChatRequest;
  try {
    body = await req.json();
  } catch {
    return errorJSON("CHAT_INVALID_JSON", "Invalid JSON body.", 400);
  }

  const conversation = sanitizeMessages(body.messages);
  if (!conversation.length || conversation[conversation.length - 1].role !== "user") {
    return errorJSON("CHAT_MESSAGES_REQUIRED", "Send a message to start the conversation.", 400);
  }
  if (conversation[conversation.length - 1].content.length > MAX_MESSAGE_CHARS) {
    return errorJSON(
      "CHAT_MESSAGE_TOO_LONG",
      `That message is too long. Keep it under ${MAX_MESSAGE_CHARS.toLocaleString("en-US")} characters.`,
      400,
    );
  }

  const attachments = parseAttachments(body.attachments);
  if (isAttachmentError(attachments)) {
    return errorJSON(attachments.code, attachments.message, attachments.status);
  }

  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) {
    console.warn("Chat: OPENAI_API_KEY is not configured.");
    return errorJSON("CHAT_AI_REQUEST_FAILED", "The advisor is not configured right now. Try again later.", 500);
  }

  const quota = await consumeChatQuota(auth.user.id);
  if (!quota.allowed) {
    return errorJSON(
      "CHAT_RATE_LIMITED",
      `You've reached today's ${quota.limit} advisor messages. Your limit resets at midnight Eastern.`,
      429,
    );
  }

  const latestMessage = conversation[conversation.length - 1].content;
  const { model: openAIModel } = chooseModel(latestMessage, hasAttachments(attachments));
  const prompt = await buildPrompt(body, auth.user.id, latestMessage);
  const { recent, earlierDigest } = trimHistory(conversation);
  const messages = [
    { role: "system", content: prompt },
    ...(earlierDigest ? [{ role: "system", content: earlierDigest }] : []),
    ...recent.slice(0, -1),
    { role: "user", content: userContent(latestMessage, attachments) },
  ];

  const shouldStream = new URL(req.url).pathname.endsWith("/stream");
  const memories = extractMemories(
    latestMessage,
    Array.isArray(body.chat_memories) ? body.chat_memories.map(String) : [],
    openAIKey,
    openAIBaseURL(),
  );

  try {
    const openAIResponse = await fetch(`${openAIBaseURL()}/chat/completions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: openAIModel,
        messages,
        max_completion_tokens: MAX_COMPLETION_TOKENS,
        stream: shouldStream,
      }),
    });

    if (!openAIResponse.ok) {
      const detail = await safeErrorText(openAIResponse);
      console.warn(`Chat OpenAI request failed with status ${openAIResponse.status}: ${detail}`);
      return json({
        detail: {
          code: "CHAT_AI_REQUEST_FAILED",
          message: "We could not reach the advisor right now. Check your connection and try again.",
        },
      }, 502);
    }

    if (shouldStream) {
      return streamOpenAIResponse(openAIResponse, async () => {
        const items = await memories;
        return items.length ? [{ type: "memories", items }] : [];
      });
    }

    const data = await openAIResponse.json();
    const choice = data.choices?.[0];
    return json({
      reply: choice?.message?.content ?? "",
      truncated: choice?.finish_reason === "length",
      memories: await memories,
    });
  } catch (error) {
    console.warn(`Chat AI service error: ${errorMessage(error)}`);
    return json({
      detail: {
        code: "CHAT_AI_REQUEST_FAILED",
        message: "We could not reach the advisor right now. Check your connection and try again.",
      },
    }, 502);
  }
});

async function buildPrompt(body: ChatRequest, userId: string, latestMessage: string): Promise<string> {
  const academic = await buildAcademicContext({
    userId,
    clientMajor: body.major || "Computer Science",
    transcript: Array.isArray(body.transcript) ? body.transcript : [],
    inProgressCourses: Array.isArray(body.in_progress_courses) ? body.in_progress_courses.map(String) : [],
    latestMessage,
  });

  const parts = [systemPrompt, VT_PROMPT_CONTEXT, ...academic.sections];
  const studentContext = buildStudentContext(body);
  if (studentContext) {
    parts.push(studentContext);
  }
  return parts.join("\n\n");
}

function buildStudentContext(body: ChatRequest): string {
  const lines: string[] = [];

  if (body.transcript?.length) {
    lines.push("Transcript courses:");
    for (const course of body.transcript.slice(0, 160)) {
      const details = [
        course.name,
        course.grade ? `grade: ${course.grade}` : undefined,
        course.semester,
        typeof course.credits === "number" ? `${course.credits} credits` : undefined,
      ].filter(Boolean).join(", ");
      lines.push(`- ${course.code}${details ? ` (${details})` : ""}`);
    }
  }

  if (body.in_progress_courses?.length) {
    lines.push("Current/upcoming course context:");
    for (const course of body.in_progress_courses.slice(0, 80)) {
      lines.push(`- ${course}`);
    }
  }

  if (body.transcript_notes?.length) {
    lines.push("Private transcript parser notes:");
    for (const note of body.transcript_notes.slice(0, 20)) {
      lines.push(`- ${note}`);
    }
  }

  if (body.chat_memories?.length) {
    lines.push("Student preferences and recurring context:");
    for (const memory of body.chat_memories.slice(0, 20)) {
      lines.push(`- ${memory}`);
    }
  }

  return lines.join("\n");
}

// Only user/assistant turns are accepted from the client; system and tool roles
// would let a caller override the advisor's instructions. The newest message is
// length-checked by the caller; older turns are truncated rather than rejected
// because long assistant answers routinely exceed the per-message cap.
function sanitizeMessages(raw: unknown): ChatMessage[] {
  if (!Array.isArray(raw)) return [];
  const messages: ChatMessage[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const { role, content } = item as Record<string, unknown>;
    if (role !== "user" && role !== "assistant") continue;
    const text = typeof content === "string" ? content : "";
    if (!text.trim()) continue;
    messages.push({ role, content: text });
  }
  const recent = messages.slice(-MAX_MESSAGES);
  return recent.map((message, index) =>
    index === recent.length - 1 || message.content.length <= MAX_MESSAGE_CHARS
      ? message
      : { ...message, content: `${message.content.slice(0, MAX_MESSAGE_CHARS)}…` }
  );
}

// Atomically counts this request against the user's daily allowance
// (consume_chat_quota in migration 006). If the quota RPC is unavailable, for
// example before 006 is applied, the request is allowed and the failure logged
// so chat keeps working; authentication is still enforced.
async function consumeChatQuota(userId: string): Promise<{ allowed: boolean; limit: number }> {
  const limit = Number(Deno.env.get("CHAT_DAILY_LIMIT")) || DEFAULT_DAILY_LIMIT;
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    console.warn("Chat quota skipped: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not configured.");
    return { allowed: true, limit };
  }

  try {
    const response = await fetch(`${supabaseURL}/rest/v1/rpc/consume_chat_quota`, {
      method: "POST",
      headers: {
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_user_id: userId, p_limit: limit }),
    });
    if (!response.ok) {
      console.warn(`Chat quota check failed with status ${response.status}: ${await safeErrorText(response)}`);
      return { allowed: true, limit };
    }
    const rows = await response.json();
    const row = Array.isArray(rows) ? rows[0] : rows;
    return { allowed: row?.allowed !== false, limit };
  } catch (error) {
    console.warn(`Chat quota check error: ${errorMessage(error)}`);
    return { allowed: true, limit };
  }
}

// Relays OpenAI's stream as SSE. Token payloads are JSON strings (what shipped
// iOS builds decode); control events are JSON objects with a "type", which
// older clients ignore. After the last token: {"type":"finish","reason":...},
// any trailing events (e.g. extracted memories), then [DONE].
function streamOpenAIResponse(
  openAIResponse: Response,
  trailingEvents: () => Promise<Record<string, unknown>[]> = () => Promise.resolve([]),
): Response {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  let finishReason: string | null = null;

  const stream = new ReadableStream({
    async start(controller) {
      const send = (payload: unknown) => controller.enqueue(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`));
      const finish = async () => {
        send({ type: "finish", reason: finishReason ?? "stop" });
        try {
          for (const event of await trailingEvents()) send(event);
        } catch (error) {
          console.warn(`Chat trailing events failed: ${errorMessage(error)}`);
        }
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();
      };

      const reader = openAIResponse.body?.getReader();
      if (!reader) {
        await finish();
        return;
      }

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() ?? "";

          for (const line of lines) {
            if (!line.startsWith("data: ")) continue;
            const payload = line.slice(6).trim();
            if (payload === "[DONE]") {
              await finish();
              return;
            }
            try {
              const data = JSON.parse(payload);
              const choice = data.choices?.[0];
              const token = choice?.delta?.content;
              if (token) send(token);
              if (choice?.finish_reason) finishReason = choice.finish_reason;
            } catch {
              // Ignore malformed provider chunks and keep streaming.
            }
          }
        }
        await finish();
      } catch (error) {
        controller.error(error);
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
    },
  });
}

// Overridable for local testing against a mock; production uses OpenAI.
function openAIBaseURL(): string {
  return (Deno.env.get("OPENAI_BASE_URL") || "https://api.openai.com/v1").replace(/\/$/, "");
}

function errorJSON(code: string, message: string, status: number): Response {
  return json({ detail: { code, message } }, status);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

async function safeErrorText(response: Response): Promise<string> {
  try {
    const data = await response.json();
    return data.error?.message || data.message || JSON.stringify(data).slice(0, 800);
  } catch {
    return (await response.text()).slice(0, 800);
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
