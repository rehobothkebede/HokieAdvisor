import { requireUser } from "../_shared/auth.ts";

type ChatMessage = {
  role: "user" | "assistant";
  content: string;
};

type TranscriptEntry = {
  code: string;
  name?: string;
  grade?: string | null;
  semester?: string | null;
  credits?: number | null;
};

type ChatRequest = {
  messages?: unknown[];
  major?: string;
  transcript?: TranscriptEntry[];
  in_progress_courses?: string[];
  transcript_notes?: string[];
  chat_memories?: string[];
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_MESSAGES = 40;
const MAX_MESSAGE_CHARS = 8000;
const DEFAULT_DAILY_LIMIT = 60;

const systemPrompt = `You are Hokie Advisor, a personalized academic advisor and CS/math tutor for Virginia Tech students.

Operating rules:
- If the student asks about degree planning, scheduling, prerequisites, grades, transcripts, or audits, answer as an academic advisor.
- If the student asks about course material, programming, math, proofs, algorithms, or debugging, answer as a tutor.
- Use the student's transcript context when provided. Do not ask them to check their transcript if the answer is available in context.
- For transcript rulings, answer yes/no first, then explain the specific courses and grades.
- C or better means C, C+, B-, B, B+, A-, A, or A+. C- does not satisfy C-or-better requirements.
- Treat transfer/awarded credit grades such as T, TR, TRANSFER, P, CR, or CREDIT as satisfying exact mapped VT course codes.
- Never fabricate requirements. If a requirement is not in context, say what is known and what still needs confirmation.
- Be concise, warm, and concrete. Prefer short paragraphs and bullets.
- For math, algorithms, proofs, matrices, and recurrence relations, use LaTeX where helpful.
- For visual graph/tree/path topics, include a fenced graph block when useful.`;

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

  const openAIModel = Deno.env.get("OPENAI_MODEL") || "gpt-5.4-nano";
  const prompt = await buildPrompt(body);
  const messages = [
    { role: "system", content: prompt },
    ...conversation,
  ];

  const shouldStream = new URL(req.url).pathname.endsWith("/stream");

  try {
    const openAIResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAIKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: openAIModel,
        messages,
        max_completion_tokens: 1500,
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
      return streamOpenAIResponse(openAIResponse);
    }

    const data = await openAIResponse.json();
    return json({ reply: data.choices?.[0]?.message?.content ?? "" });
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

async function buildPrompt(body: ChatRequest): Promise<string> {
  const parts = [systemPrompt];
  const studentContext = buildStudentContext(body);
  if (studentContext) {
    parts.push(studentContext);
  }

  const courseContext = await buildCourseContext(body.major || "Computer Science");
  if (courseContext) {
    parts.push(`Department course catalog context:\n${courseContext}`);
  }

  return parts.join("\n\n");
}

function buildStudentContext(body: ChatRequest): string {
  const lines: string[] = [];

  if (body.major) {
    lines.push(`Student major: ${body.major}`);
  }

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

async function buildCourseContext(major: string): Promise<string> {
  const subject = subjectForMajor(major);
  if (!subject) {
    return "";
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseURL || !supabaseKey) {
    return "";
  }

  const url = new URL(`${supabaseURL}/rest/v1/coe_courses`);
  url.searchParams.set("select", "code,name,credits,prerequisites,description");
  url.searchParams.set("subject", `eq.${subject}`);
  url.searchParams.set("order", "code.asc");
  url.searchParams.set("limit", "80");

  const response = await fetch(url, {
    headers: {
      "apikey": supabaseKey,
      "Authorization": `Bearer ${supabaseKey}`,
    },
  });
  if (!response.ok) {
    return "";
  }

  const courses = await response.json();
  return courses.map((course: Record<string, unknown>) => {
    const prereqs = course.prerequisites ? `; prereqs: ${course.prerequisites}` : "";
    const description = course.description ? `; ${String(course.description).slice(0, 220)}` : "";
    return `- ${course.code}: ${course.name} (${course.credits ?? "?"} credits${prereqs})${description}`;
  }).join("\n");
}

function subjectForMajor(major: string): string {
  const normalized = major.trim().toLowerCase();
  if (["computer science", "cs"].includes(normalized)) {
    return "CS";
  }
  return "";
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

function streamOpenAIResponse(openAIResponse: Response): Response {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";

  const stream = new ReadableStream({
    async start(controller) {
      const reader = openAIResponse.body?.getReader();
      if (!reader) {
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();
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
              controller.enqueue(encoder.encode("data: [DONE]\n\n"));
              controller.close();
              return;
            }
            try {
              const data = JSON.parse(payload);
              const token = data.choices?.[0]?.delta?.content;
              if (token) {
                controller.enqueue(encoder.encode(`data: ${JSON.stringify(token)}\n\n`));
              }
            } catch {
              // Ignore malformed provider chunks and keep streaming.
            }
          }
        }
        controller.enqueue(encoder.encode("data: [DONE]\n\n"));
        controller.close();
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
