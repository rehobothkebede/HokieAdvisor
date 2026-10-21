// Service-role reads for Edge Functions. Callers must already have verified the
// user (requireUser) and must scope user-owned tables by user_id themselves,
// because the service role bypasses row-level security.

export type Row = Record<string, unknown>;

export async function restSelect(table: string, params: Record<string, string>): Promise<Row[]> {
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return [];

  const url = new URL(`${supabaseURL}/rest/v1/${table}`);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }

  try {
    const response = await fetch(url, {
      headers: {
        "apikey": serviceRoleKey,
        "Authorization": `Bearer ${serviceRoleKey}`,
      },
    });
    if (!response.ok) {
      console.warn(`restSelect ${table} failed with status ${response.status}`);
      return [];
    }
    const rows = await response.json();
    return Array.isArray(rows) ? rows : [];
  } catch (error) {
    console.warn(`restSelect ${table} error: ${error instanceof Error ? error.message : String(error)}`);
    return [];
  }
}

// Every read of a catalog table (catalog_*, coe_courses, pathways_courses) goes
// through here so institution scoping can be added in one place.
// TODO(005): accept an institutionId and add `institution_id=eq.<id>` once
// migration 005 is applied; today every catalog row belongs to Virginia Tech.
export function catalogQuery(table: string, params: Record<string, string>): Promise<Row[]> {
  return restSelect(table, params);
}

// Quotes values for a PostgREST in.(...) filter.
export function inList(values: string[]): string {
  return `in.(${values.map((value) => `"${value.replaceAll('"', '""')}"`).join(",")})`;
}

// Strips characters that carry meaning inside PostgREST filter syntax.
export function filterSafe(value: string): string {
  return value.replace(/[^A-Za-z0-9 .&'-]/g, " ").replace(/\s+/g, " ").trim();
}
