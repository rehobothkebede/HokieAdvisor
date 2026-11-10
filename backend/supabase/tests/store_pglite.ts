// TEST/QA-ONLY store: runs the courses handler's queries against the local
// PGlite database *as the signed-in student* (role `authenticated`, RLS on),
// so tests and the local QA server exercise the real migration policies.

import type { PGlite } from "npm:@electric-sql/pglite@0.2.17";
import type {
  CoursesStore,
  DeadlineRow,
  GuideTopicRow,
  Institution,
  SourceRow,
  TermRow,
} from "../functions/courses/types.ts";
import { asUser, type Tx } from "./harness.ts";

export class PgliteStore implements CoursesStore {
  constructor(protected db: PGlite, protected userId: string) {}

  protected run<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    return asUser(this.db, this.userId, fn);
  }

  protected async rows<T>(sql: string, params: unknown[] = []): Promise<T[]> {
    return await this.run(async (tx) => (await tx.query<T>(sql, params)).rows);
  }

  async institutionForUser(): Promise<Institution | null> {
    const rows = await this.rows<Institution>(
      `select i.id, i.slug, i.name from public.profiles p
         join public.institutions i on i.id = p.institution_id
        where p.id = auth.uid() and i.is_active`,
    );
    return rows[0] ?? null;
  }

  listTerms(institutionId: string): Promise<TermRow[]> {
    return this.rows(
      `select id, term_key, name, classes_begin::text, classes_end::text, finals_end::text, timezone, source_id
         from public.academic_terms where institution_id = $1 order by classes_begin`,
      [institutionId],
    );
  }

  listDeadlines(termId: string): Promise<DeadlineRow[]> {
    return this.rows(
      `select id, term_id, kind, audience, label, starts_on::text, ends_on::text, time_note, detail, is_tentative, source_id
         from public.term_deadlines where term_id = $1 order by starts_on`,
      [termId],
    );
  }

  listGuideTopics(institutionId: string): Promise<GuideTopicRow[]> {
    return this.rows(
      `select topic, sort_order, title, points, comparison, links
         from public.registration_guide_topics where institution_id = $1 order by sort_order`,
      [institutionId],
    );
  }

  listSources(institutionId: string): Promise<SourceRow[]> {
    return this.rows(
      `select id, kind, title, publisher, url, checked_on::text
         from public.official_sources where institution_id = $1`,
      [institutionId],
    );
  }
}
