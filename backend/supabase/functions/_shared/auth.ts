import { createClient, type User } from "npm:@supabase/supabase-js@2";
import { errorResponse } from "./academic.ts";

export type AuthResult =
  | { user: User; response?: undefined }
  | { user?: undefined; response: Response };

// Verifies the caller's Supabase session. The bare anon key is a valid JWT for
// the gateway, so it is rejected here explicitly: only signed-in users pass.
export async function requireUser(req: Request): Promise<AuthResult> {
  const authorization = req.headers.get("authorization") || "";
  const token = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice("bearer ".length).trim()
    : "";
  const supabaseURL = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";

  if (!token || token === anonKey) {
    return { response: errorResponse("AUTH_REQUIRED", "Please sign in to use Hokie Advisor.", 401) };
  }
  if (!supabaseURL || !anonKey) {
    console.warn("requireUser: SUPABASE_URL or SUPABASE_ANON_KEY is not configured.");
    return { response: errorResponse("AUTH_UNAVAILABLE", "Sign-in is temporarily unavailable. Try again shortly.", 503) };
  }

  const client = createClient(supabaseURL, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data?.user) {
    return {
      response: errorResponse("AUTH_INVALID_SESSION", "Invalid or expired session. Please sign in again.", 401),
    };
  }
  return { user: data.user };
}
