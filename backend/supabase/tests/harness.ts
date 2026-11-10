// Test harness: an in-memory Postgres (PGlite) with the Supabase shim and the
// project's real migrations applied in order. Used by the database tests and
// by the local QA server. Never connects to a hosted project.

import { PGlite } from "npm:@electric-sql/pglite@0.2.17";

const here = new URL(".", import.meta.url);
const migrationsDir = new URL("../migrations/", here);

// Order matters: 005 (institutions) is untracked in git but required by 007+.
export const MIGRATIONS = [
  "001_initial_schema.sql",
  "002_auth_storage_bootstrap.sql",
  "003_api_role_grants.sql",
  "004_user_owned_child_integrity.sql",
  "005_multi_institution.sql",
  "006_chat_usage.sql",
  "007_course_companion_registration.sql",
  "008_course_companion_syllabi.sql",
  "009_course_companion_review.sql",
];

export async function createTestDatabase(upTo?: string): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(await Deno.readTextFile(new URL("supabase_shim.sql", here)));
  for (const file of MIGRATIONS) {
    const url = new URL(file, migrationsDir);
    let sql: string;
    try {
      sql = await Deno.readTextFile(url);
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) break; // later stages not written yet
      throw error;
    }
    // PGlite ships without pgcrypto; gen_random_uuid() is built into Postgres 13+.
    sql = sql.replace(/create extension if not exists pgcrypto;/gi, "");
    try {
      await db.exec(sql);
    } catch (error) {
      throw new Error(`Migration ${file} failed: ${(error as Error).message}`);
    }
    if (file === upTo) break;
  }
  return db;
}

export async function createUser(db: PGlite, email: string): Promise<string> {
  const result = await db.query<{ id: string }>(
    "insert into auth.users (email) values ($1) returning id",
    [email],
  );
  return result.rows[0].id;
}

/** Runs `fn` as a signed-in student: role `authenticated`, RLS enforced. */
export async function asUser<T>(db: PGlite, userId: string, fn: (tx: Tx) => Promise<T>): Promise<T> {
  return await db.transaction(async (tx) => {
    await tx.query("select set_config('request.jwt.claims', $1, true)", [
      JSON.stringify({ sub: userId, role: "authenticated" }),
    ]);
    await tx.exec("set local role authenticated");
    return await fn(tx);
  });
}

/** Runs `fn` with no session: role `anon`. */
export async function asAnon<T>(db: PGlite, fn: (tx: Tx) => Promise<T>): Promise<T> {
  return await db.transaction(async (tx) => {
    await tx.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({ role: "anon" })]);
    await tx.exec("set local role anon");
    return await fn(tx);
  });
}

export type Tx = Parameters<Parameters<PGlite["transaction"]>[0]>[0];
