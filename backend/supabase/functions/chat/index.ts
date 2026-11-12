// Edge function: MyAdvisor chat. POST /chat (JSON) or /chat/stream (SSE).
import { handleChat } from "./handler.ts";

Deno.serve(handleChat);
