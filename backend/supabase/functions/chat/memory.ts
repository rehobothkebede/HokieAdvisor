import { chatModel } from "./conversation.ts";

const MAX_FACTS = 3;
const MAX_FACT_CHARS = 140;
const EXTRACTION_TIMEOUT_MS = 10_000;

const extractionPrompt = `You maintain a short memory of durable facts about a Virginia Tech student so a future advising conversation can be personalized.

From the student's latest message, extract at most ${MAX_FACTS} facts worth remembering long-term:
- how they like explanations (visual, step-by-step, brief, analogies)
- goals and plans (career, minor, graduation timing, grad school)
- what they struggle with or are strong in (courses, topics)
- the name they want to be called, and constraints (works part-time, transfer student)

Rules:
- One sentence each, ${MAX_FACT_CHARS} characters or fewer, written as "Student ..." or "Prefers ...".
- Skip one-off questions, course material, and anything already covered by the existing memories.
- Never record health, finances, ID numbers, passwords, contact details, or facts about other people.
- Most messages contain nothing worth remembering: return an empty list then.`;

// Asks the chat model for memorable facts in the student's newest message.
// Runs alongside the main answer; any failure or timeout yields [] so chat is
// never affected.
export async function extractMemories(
  latestMessage: string,
  existingMemories: string[],
  apiKey: string,
  baseURL: string,
): Promise<string[]> {
  if (latestMessage.trim().length < 12) return [];

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), EXTRACTION_TIMEOUT_MS);
  try {
    const existing = existingMemories.slice(0, 30).map((memory) => `- ${memory}`).join("\n") || "(none)";
    const response = await fetch(`${baseURL}/chat/completions`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: chatModel(),
        messages: [
          { role: "system", content: extractionPrompt },
          {
            role: "user",
            content: `Existing memories:\n${existing}\n\nStudent's latest message:\n"""\n${latestMessage.slice(0, 4000)}\n"""`,
          },
        ],
        max_completion_tokens: 800,
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "student_memories",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              required: ["memories"],
              properties: {
                memories: { type: "array", maxItems: MAX_FACTS, items: { type: "string" } },
              },
            },
          },
        },
      }),
    });
    if (!response.ok) {
      console.warn(`Memory extraction failed with status ${response.status}`);
      return [];
    }
    const data = await response.json();
    const parsed = JSON.parse(data.choices?.[0]?.message?.content ?? "{}");
    return cleanFacts(parsed?.memories, existingMemories);
  } catch (error) {
    console.warn(`Memory extraction error: ${error instanceof Error ? error.message : String(error)}`);
    return [];
  } finally {
    clearTimeout(timeout);
  }
}

export function cleanFacts(raw: unknown, existingMemories: string[]): string[] {
  if (!Array.isArray(raw)) return [];
  const existing = new Set(existingMemories.map((memory) => memory.trim().toLowerCase()));
  const facts: string[] = [];
  for (const item of raw) {
    if (typeof item !== "string") continue;
    const fact = item.replace(/\s+/g, " ").trim();
    if (!fact || fact.length > MAX_FACT_CHARS || existing.has(fact.toLowerCase())) continue;
    facts.push(fact);
    if (facts.length === MAX_FACTS) break;
  }
  return facts;
}
