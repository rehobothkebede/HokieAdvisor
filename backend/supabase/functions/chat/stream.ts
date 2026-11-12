import { corsHeaders } from "../_shared/academic.ts";

// Relays OpenAI's stream as SSE. Token payloads are JSON strings (what shipped
// iOS builds decode); control events are JSON objects with a "type", which
// older clients ignore. After the last token: {"type":"finish","reason":...},
// any trailing events (e.g. extracted memories), then [DONE].
export function streamOpenAIResponse(
  openAIResponse: Response,
  trailingEvents: () => Promise<Record<string, unknown>[]> = () => Promise.resolve([]),
  options: {
    /** Sent as a token when the reply hit its token limit before any text (reasoning models). */
    emptyLengthText?: string;
  } = {},
): Response {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  let finishReason: string | null = null;
  let sentText = false;

  const stream = new ReadableStream({
    async start(controller) {
      const send = (payload: unknown) => controller.enqueue(encoder.encode(`data: ${JSON.stringify(payload)}\n\n`));
      const finish = async () => {
        if (!sentText && finishReason === "length" && options.emptyLengthText) send(options.emptyLengthText);
        send({ type: "finish", reason: finishReason ?? "interrupted" });
        try {
          for (const event of await trailingEvents()) send(event);
        } catch (error) {
          console.warn(`Chat trailing events failed: ${error instanceof Error ? error.message : String(error)}`);
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
              if (token) {
                send(token);
                sentText = true;
              }
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

