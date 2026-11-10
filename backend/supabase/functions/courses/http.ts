// HTTP layer shared by the deployed edge function and the local QA server:
// CORS, method checks, authentication hook, body parsing, and dispatch.

import { corsHeaders, errorResponse, json, methodNotAllowed } from "../_shared/academic.ts";
import { type Deps, handleAction } from "./handler.ts";

export type Authenticated = { userId: string; token: string };

export type HTTPConfig = {
  authenticate: (req: Request) => Promise<Authenticated | Response>;
  deps: (auth: Authenticated) => Deps;
};

export async function handleHTTP(req: Request, config: HTTPConfig): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return methodNotAllowed();

  const auth = await config.authenticate(req);
  if (auth instanceof Response) return auth;

  let body: Record<string, unknown>;
  const contentType = req.headers.get("content-type") ?? "";
  if (contentType.startsWith("multipart/form-data")) {
    // Uploads: fields become the body; the file is passed through untouched.
    let form: FormData;
    try {
      form = await req.formData();
    } catch {
      return errorResponse("COURSES_INVALID_FORM", "Upload the file using multipart/form-data.", 400);
    }
    body = {};
    for (const [key, value] of form.entries()) body[key] = value;
  } else {
    try {
      body = await req.json();
    } catch {
      return errorResponse("COURSES_INVALID_JSON", "Send a JSON body.", 400);
    }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return errorResponse("COURSES_INVALID_JSON", "Send a JSON object.", 400);
    }
  }

  const action = typeof body.action === "string" ? body.action : "";
  const result = await handleAction(action, body, config.deps(auth));
  return json(result.body, result.status);
}
