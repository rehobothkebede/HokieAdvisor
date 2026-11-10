// Shapes shared by the courses handler and its stores.

export type Institution = { id: string; slug: string; name: string };

export type TermRow = {
  id: string;
  term_key: string;
  name: string;
  classes_begin: string; // yyyy-mm-dd
  classes_end: string;
  finals_end: string | null;
  timezone: string;
  source_id: string;
};

export type DeadlineRow = {
  id: string;
  term_id: string;
  kind: string;
  audience: string;
  label: string;
  starts_on: string;
  ends_on: string | null;
  time_note: string | null;
  detail: string | null;
  is_tentative: boolean;
  source_id: string;
};

export type GuideTopicRow = {
  topic: string;
  sort_order: number;
  title: string;
  points: { text: string; source_id: string }[];
  comparison: { aspect: string; drop: string; withdraw: string; source_id: string }[] | null;
  links: { title: string; url: string }[];
};

export type SourceRow = {
  id: string;
  kind: string;
  title: string;
  publisher: string;
  url: string;
  checked_on: string;
};

/**
 * Data access for one signed-in student. Every implementation must act with
 * that student's privileges (row-level security), never as the service role.
 */
export interface CoursesStore {
  institutionForUser(): Promise<Institution | null>;
  listTerms(institutionId: string): Promise<TermRow[]>;
  listDeadlines(termId: string): Promise<DeadlineRow[]>;
  listGuideTopics(institutionId: string): Promise<GuideTopicRow[]>;
  listSources(institutionId: string): Promise<SourceRow[]>;
}

export type HandlerResult = { status: number; body: unknown };

export class HandlerError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}
