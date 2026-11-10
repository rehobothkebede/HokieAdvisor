const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "DELETE, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "DELETE") {
    return json({ detail: "Method not allowed" }, 405);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey;
  if (!supabaseURL || !serviceRoleKey || !anonKey) {
    return json({ detail: "Supabase account deletion is not configured." }, 500);
  }

  const authorization = req.headers.get("authorization") || "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return json({ detail: "Missing bearer token." }, 401);
  }

  const userResponse = await fetch(`${supabaseURL}/auth/v1/user`, {
    headers: {
      "apikey": anonKey,
      "Authorization": authorization,
    },
  });
  if (!userResponse.ok) {
    return json({ detail: "Invalid or expired session." }, 401);
  }

  const user = await userResponse.json();
  if (!user?.id) {
    return json({ detail: "Could not resolve authenticated user." }, 401);
  }

  // Uploaded syllabi live in Storage, which doesn't cascade from the database.
  // Remove them first; if that fails, keep the account so a retry can finish.
  const filesRemoved = await removeSyllabusFiles(supabaseURL, serviceRoleKey, user.id);
  if (!filesRemoved) {
    return json({
      detail: {
        code: "ACCOUNT_FILES_DELETE_FAILED",
        message: "Could not delete your uploaded files right now. Your account was not deleted. Please try again.",
      },
    }, 502);
  }

  const deleteResponse = await fetch(`${supabaseURL}/auth/v1/admin/users/${user.id}`, {
    method: "DELETE",
    headers: {
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
  });
  if (!deleteResponse.ok) {
    const detail = await safeErrorText(deleteResponse);
    console.warn(`Account deletion failed with status ${deleteResponse.status}: ${detail}`);
    return json({
      detail: {
        code: "ACCOUNT_DELETE_FAILED",
        message: "Could not delete the remote account right now. Please try again.",
      },
    }, 502);
  }

  return json({ deleted: true });
});

/**
 * Deletes every stored syllabus file of `userId` (bucket `syllabi`). Returns
 * true when nothing is left to delete. A project without the course companion
 * migrations (no syllabus_documents table) has nothing to remove.
 */
async function removeSyllabusFiles(supabaseURL: string, serviceRoleKey: string, userId: string): Promise<boolean> {
  const headers = { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` };
  const list = await fetch(
    `${supabaseURL}/rest/v1/syllabus_documents?select=storage_path&user_id=eq.${encodeURIComponent(userId)}`,
    { headers },
  );
  if (list.status === 404) return true; // table not deployed
  if (!list.ok) {
    console.warn(`Syllabus file listing failed with status ${list.status}`);
    return false;
  }
  const rows: { storage_path: string }[] = await list.json();
  const paths = rows.map((r) => r.storage_path).filter((p) => p.startsWith(`${userId}/`));
  for (let i = 0; i < paths.length; i += 100) {
    const response = await fetch(`${supabaseURL}/storage/v1/object/syllabi`, {
      method: "DELETE",
      headers: { ...headers, "Content-Type": "application/json" },
      body: JSON.stringify({ prefixes: paths.slice(i, i + 100) }),
    });
    if (!response.ok) {
      console.warn(`Syllabus file deletion failed with status ${response.status}`);
      return false;
    }
  }
  return true;
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
    return data?.msg || data?.message || data?.error_description || JSON.stringify(data);
  } catch {
    return await response.text();
  }
}
