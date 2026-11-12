// Synthetic streaming responses only. No external requests or model calls.
Deno.serve({ hostname: "127.0.0.1", port: 8792 }, async (req) => {
  if (req.method === "GET") return new Response("Local QA fixture server");
  const body = await req.json();
  const input = body.messages.at(-1).content;
  if (input === "empty") return new Response("", { headers: { "content-type": "text/event-stream" } });
  if (input === "rate-limit") return Response.json({ detail: { code: "CHAT_RATE_LIMITED", message: "Daily test limit reached." } }, { status: 429 });
  let data = 'data: "A partial answer"\n\n';
  if (input !== "abrupt") {
    data += `data: ${JSON.stringify({ type: "finish", reason: input === "length" ? "length" : input === "server-interrupted" ? "interrupted" : "stop" })}\n\n`;
    data += 'data: {"type":"memories","items":["Prefers short examples."]}\n\n';
    data += 'data: [DONE]\n\n';
  }
  return new Response(data, { headers: { "content-type": "text/event-stream" } });
});
