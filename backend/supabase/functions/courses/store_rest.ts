// Production store: Supabase REST (PostgREST) called with the student's own
// access token, so row-level security decides what each request can see or
// change. The service-role key is never used here.

import type {
  CoursesStore,
  DeadlineRow,
  GuideTopicRow,
  Institution,
  SourceRow,
  TermRow,
} from "./types.ts";

export class RestStore implements CoursesStore {
  constructor(
    private supabaseURL: string,
    private anonKey: string,
    private accessToken: string,
    private userId: string,
  ) {}

  protected async rest<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await fetch(`${this.supabaseURL}/rest/v1/${path}`, {
      ...init,
      headers: {
        apikey: this.anonKey,
        Authorization: `Bearer ${this.accessToken}`,
        "Content-Type": "application/json",
        ...(init.headers ?? {}),
      },
    });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      throw new Error(`REST ${init.method ?? "GET"} ${path.split("?")[0]} failed: ${response.status} ${text.slice(0, 200)}`);
    }
    if (response.status === 204) return undefined as T;
    const text = await response.text();
    return (text ? JSON.parse(text) : undefined) as T;
  }

  async institutionForUser(): Promise<Institution | null> {
    const rows = await this.rest<{ institutions: Institution & { is_active: boolean } | null }[]>(
      `profiles?select=institutions(id,slug,name,is_active)&id=eq.${this.userId}`,
    );
    const inst = rows[0]?.institutions;
    if (!inst || !inst.is_active) return null;
    return { id: inst.id, slug: inst.slug, name: inst.name };
  }

  listTerms(institutionId: string): Promise<TermRow[]> {
    return this.rest(
      `academic_terms?select=id,term_key,name,classes_begin,classes_end,finals_end,timezone,source_id` +
        `&institution_id=eq.${institutionId}&order=classes_begin`,
    );
  }

  listDeadlines(termId: string): Promise<DeadlineRow[]> {
    return this.rest(
      `term_deadlines?select=id,term_id,kind,audience,label,starts_on,ends_on,time_note,detail,is_tentative,source_id` +
        `&term_id=eq.${termId}&order=starts_on`,
    );
  }

  listGuideTopics(institutionId: string): Promise<GuideTopicRow[]> {
    return this.rest(
      `registration_guide_topics?select=topic,sort_order,title,points,comparison,links` +
        `&institution_id=eq.${institutionId}&order=sort_order`,
    );
  }

  listSources(institutionId: string): Promise<SourceRow[]> {
    return this.rest(
      `official_sources?select=id,kind,title,publisher,url,checked_on&institution_id=eq.${institutionId}`,
    );
  }
}
