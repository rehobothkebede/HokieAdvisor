import { normalizeCode, objectArray, stringArray } from "../_shared/academic.ts";
import { catalogQuery, filterSafe, inList, restSelect, type Row } from "../_shared/catalog.ts";
import {
  GRADE_POINTS,
  isAwardedCreditGrade,
  isPassing,
  type ProgramSpec,
  resolveMajorSubject,
  VT_PROGRAMS,
} from "../_shared/vt_programs.ts";

export type TranscriptEntry = {
  code: string;
  name?: string;
  grade?: string | null;
  semester?: string | null;
  credits?: number | null;
};

export type AcademicContextInput = {
  userId: string;
  clientMajor: string;
  transcript: TranscriptEntry[];
  inProgressCourses: string[];
  latestMessage: string;
  now?: Date;
};

export type AcademicContext = {
  major: string;
  sections: string[];
};

type CourseRow = {
  code: string;
  name: string;
  credits: unknown;
  prerequisites: string;
  description: string;
};

const COURSE_CODE_PATTERN = /\b([A-Z]{2,4})[\s-]?(\d{4}[A-Z]?)\b/g;
const MAX_CONTEXT_COURSES = 60;
const MAX_MENTIONED_CODES = 12;
const DIGEST_LIMIT = 2500;

// Builds the server-side academic context for the advisor prompt: the
// student's profile, program requirements, latest audits, Pathways status, a
// relevant slice of the catalog, and today's date and term. Every lookup is
// best-effort; a missing table or row just drops that section.
export async function buildAcademicContext(input: AcademicContextInput): Promise<AcademicContext> {
  const [profile, degreeAudit, darsAudit] = await Promise.all([
    firstRow("profiles", { id: `eq.${input.userId}`, select: "major,graduation_year,full_name" }),
    firstRow("degree_audits", {
      user_id: `eq.${input.userId}`,
      select: "response,created_at",
      order: "created_at.desc",
      limit: "1",
    }),
    firstRow("dars_audits", {
      user_id: `eq.${input.userId}`,
      select: "response,created_at",
      order: "created_at.desc",
      limit: "1",
    }),
  ]);

  const major = stringValue(profile?.major) || input.clientMajor.trim();
  const graduationYear = stringValue(profile?.graduation_year);
  const sections: string[] = [];

  sections.push(termContext(input.now ?? new Date()));

  const studentLines = [
    major ? `Major: ${major}` : "Major: not set in profile",
    graduationYear ? `Expected graduation: ${graduationYear}` : "",
  ].filter(Boolean);
  sections.push(`Student profile:\n${studentLines.map((line) => `- ${line}`).join("\n")}`);

  const program = major ? await resolveProgram(major) : null;
  const grades = gradeSets(input.transcript);
  const inProgress = new Set(input.inProgressCourses.map(normalizeCode));
  const taken = new Set([...input.transcript.map((entry) => normalizeCode(entry.code)), ...inProgress]);

  const requirementText = await requirementContext(program, grades, inProgress);
  if (requirementText) sections.push(requirementText);

  const degreeDigest = degreeAuditDigest(degreeAudit);
  if (degreeDigest) sections.push(degreeDigest);

  const darsDigest = darsAuditDigest(darsAudit);
  if (darsDigest) sections.push(darsDigest);

  const mentioned = mentionedCodes(input.latestMessage);
  const pathwaysText = await pathwaysContext(degreeAudit, mentioned);
  if (pathwaysText) sections.push(pathwaysText);

  const courseText = await courseContext(program, grades, taken, inProgress, mentioned);
  if (courseText) sections.push(courseText);

  return { major, sections };
}

// ---------------------------------------------------------------------------
// Date and term
// ---------------------------------------------------------------------------

export function termContext(now: Date): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      year: "numeric",
      month: "numeric",
      day: "numeric",
    }).formatToParts(now).map((part) => [part.type, part.value]),
  );
  const year = Number(parts.year);
  const month = Number(parts.month);
  const day = Number(parts.day);
  const today = new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(now);

  const { current, next } = vtTerms(year, month, day);
  return `Today is ${today} (Eastern). Current Virginia Tech term: ${current}. Next regular semester: ${next}. ` +
    `"Next semester" means ${next} unless the student says otherwise.`;
}

// Approximate VT calendar boundaries; exact dates vary by a few days each year.
export function vtTerms(year: number, month: number, day: number): { current: string; next: string } {
  const md = month * 100 + day;
  if (md < 115) return { current: `Winter ${year - 1}-${year} session`, next: `Spring ${year}` };
  if (md <= 515) return { current: `Spring ${year}`, next: `Fall ${year}` };
  if (md <= 815) return { current: `Summer ${year}`, next: `Fall ${year}` };
  if (md <= 1220) return { current: `Fall ${year}`, next: `Spring ${year + 1}` };
  return { current: `Winter ${year}-${year + 1} session`, next: `Spring ${year + 1}` };
}

// ---------------------------------------------------------------------------
// Program and requirements
// ---------------------------------------------------------------------------

type ResolvedProgram = {
  subject: string | null;
  programKey: string | null;
  programName: string;
  spec: ProgramSpec | null;
};

// Maps a profile major to a catalog program and subject: the alias table
// first, then catalog_programs, then catalog_subjects by name.
async function resolveProgram(major: string): Promise<ResolvedProgram> {
  const safe = filterSafe(major);
  let subject = resolveMajorSubject(major);
  let programKey: string | null = null;
  let programName = major;

  if (safe) {
    const programs = await catalogQuery("catalog_programs", {
      select: "key,name,code,degree",
      or: `(name.ilike.*${safe}*,code.ilike.${safe})`,
      limit: "5",
    });
    const program = programs.find((row) => stringValue(row.name).toLowerCase() === major.toLowerCase()) ?? programs[0];
    if (program) {
      programKey = stringValue(program.key) || null;
      programName = [stringValue(program.name), stringValue(program.degree)].filter(Boolean).join(" ") || major;
      subject ??= subjectFromCode(stringValue(program.code));
    }
  }

  if (!subject && safe) {
    const subjects = await catalogQuery("catalog_subjects", {
      select: "code,name",
      name: `ilike.${safe}`,
      limit: "1",
    });
    subject = stringValue(subjects[0]?.code).toUpperCase() || null;
  }

  return { subject, programKey, programName, spec: subject ? VT_PROGRAMS[subject] ?? null : null };
}

function subjectFromCode(code: string): string | null {
  const match = code.toUpperCase().match(/^([A-Z]{2,4})\b/);
  return match ? match[1] : null;
}

async function requirementContext(
  program: ResolvedProgram | null,
  grades: GradeSets,
  inProgress: Set<string>,
): Promise<string> {
  if (!program) return "";

  if (program.programKey) {
    const row = await firstCatalogRow("catalog_requirements", {
      program_key: `eq.${program.programKey}`,
      select: "name,requirements",
    });
    if (row?.requirements && Object.keys(row.requirements as object).length) {
      return `Program requirements for ${stringValue(row.name) || program.programName} (catalog data):\n` +
        clip(JSON.stringify(row.requirements), DIGEST_LIMIT);
    }
  }

  const spec = program.spec;
  if (!spec) {
    return `No requirement checksheet is loaded for ${program.programName}. Say so instead of guessing requirements.`;
  }

  const unmet = unmetRequirements(spec, grades);
  const required = spec.requiredCourses
    .map((course) => `${course.code}${course.gradeRequired ? " (C)" : ""}`)
    .join(", ");
  const lines = [
    `Program requirements: ${spec.name} ${spec.degree}, ${spec.catalogYear} catalog, ${spec.totalCredits} total credits.`,
    `Required courses: ${required}.`,
    ...spec.notes.map((note) => `- ${note}`),
    unmet.length
      ? `Required courses not yet satisfied (per transcript): ${
        unmet.map((course) => `${course.code}${inProgress.has(course.code) ? " (in progress)" : ""}`).join(", ")
      }.`
      : grades.passing.size
      ? "All required courses are passed per the transcript."
      : "No transcript on file, so requirement progress is unknown.",
  ];
  return lines.join("\n");
}

// A requirement is met by the course or a listed substitute, at C or better
// when the requirement says so (matching the audit function's rule).
function unmetRequirements(spec: ProgramSpec, grades: GradeSets) {
  return spec.requiredCourses.filter((course) => {
    const satisfied = course.gradeRequired === "C" ? grades.cOrBetter : grades.passing;
    return !satisfied.has(course.code) && !(spec.substitutions[course.code] || []).some((code) => satisfied.has(code));
  });
}

// ---------------------------------------------------------------------------
// Audits and Pathways
// ---------------------------------------------------------------------------

function degreeAuditDigest(row: Row | null): string {
  const response = row?.response as Row | undefined;
  if (!response) return "";

  const buckets = objectArray(response.buckets);
  const incomplete = buckets
    .filter((bucket) => bucket.status !== "complete")
    .slice(0, 15)
    .map((bucket) => {
      const missing = stringArray(bucket.missing_items).slice(0, 6).join(", ");
      return `- ${stringValue(bucket.title)} (${stringValue(bucket.status)})${missing ? `: missing ${missing}` : ""}`;
    });
  const warnings = stringArray(response.warnings).slice(0, 5).map((warning) => `- Warning: ${warning}`);

  return clip(
    [
      `Latest Hokie Advisor degree audit (${stringValue(response.major)} ${stringValue(response.degree)}, ` +
      `${stringValue(response.catalog_year)} catalog, run ${dateOnly(row?.created_at)}): ` +
      `${response.percent_complete ?? "?"}% complete, ${response.completed_credits ?? "?"} of ` +
      `${response.total_required_credits ?? "?"} credits.`,
      incomplete.length ? "Incomplete requirements:" : "All audit requirements are complete.",
      ...incomplete,
      ...warnings,
    ].join("\n"),
    DIGEST_LIMIT,
  );
}

function darsAuditDigest(row: Row | null): string {
  const response = row?.response as Row | undefined;
  if (!response) return "";

  const header = [
    stringValue(response.program),
    response.catalog_year ? `${stringValue(response.catalog_year)} catalog` : "",
    response.prepared_on ? `prepared ${stringValue(response.prepared_on)}` : `uploaded ${dateOnly(row?.created_at)}`,
    response.university_gpa != null ? `university GPA ${response.university_gpa}` : "",
    response.in_major_gpa != null ? `in-major GPA ${response.in_major_gpa}` : "",
  ].filter(Boolean).join(", ");

  const categories = objectArray(response.categories)
    .filter((category) => category.status !== "complete")
    .slice(0, 8)
    .map((category) => {
      const hours = category.unfulfilled_hours != null ? `, ${category.unfulfilled_hours} hours unfulfilled` : "";
      return `- ${stringValue(category.title)} (${stringValue(category.status)}${hours})`;
    });
  const sections = objectArray(response.sections)
    .filter((section) => section.status !== "complete")
    .slice(0, 15)
    .map((section) => {
      const missing = stringArray(section.missing_items).slice(0, 6).join("; ");
      return `- ${stringValue(section.title)} (${stringValue(section.status)})${missing ? `: ${missing}` : ""}`;
    });

  return clip(
    [
      `Latest official DARS audit (source of truth over the Hokie Advisor audit): ${header}.`,
      ...(categories.length ? ["Unfinished categories:", ...categories] : []),
      ...(sections.length ? ["Unfinished sections:", ...sections] : ["All DARS sections are complete."]),
    ].join("\n"),
    DIGEST_LIMIT,
  );
}

async function pathwaysContext(degreeAudit: Row | null, mentioned: string[]): Promise<string> {
  const lines: string[] = [];

  const buckets = objectArray((degreeAudit?.response as Row | undefined)?.buckets)
    .filter((bucket) => stringValue(bucket.id).startsWith("pathways"));
  for (const bucket of buckets) {
    const matched = stringArray(bucket.matched_courses).slice(0, 4).join(", ");
    lines.push(`- ${stringValue(bucket.title)}: ${stringValue(bucket.status)}${matched ? ` (${matched})` : ""}`);
  }

  if (mentioned.length) {
    const rows = await catalogQuery("pathways_courses", {
      select: "code,concept,raw",
      code: inList(mentioned),
    });
    const concepts = new Map<string, Set<string>>();
    for (const row of rows) {
      const raw = (row.raw ?? {}) as Row;
      const area = stringValue(raw.section_id) || stringValue(row.concept);
      const code = normalizeCode(row.code);
      if (!concepts.has(code)) concepts.set(code, new Set());
      concepts.get(code)?.add(area);
    }
    for (const code of mentioned) {
      const areas = concepts.get(code);
      lines.push(areas?.size
        ? `- ${code} counts toward Pathways ${[...areas].join(", ")}`
        : `- ${code} is not in the Pathways course list`);
    }
  }

  return lines.length ? `Pathways general education:\n${lines.join("\n")}` : "";
}

// ---------------------------------------------------------------------------
// Course selection
// ---------------------------------------------------------------------------

// Picks catalog courses relevant to this student instead of the first N by
// code: unmet required courses, courses whose prerequisites are met, and any
// course the student just mentioned.
async function courseContext(
  program: ResolvedProgram | null,
  grades: GradeSets,
  taken: Set<string>,
  inProgress: Set<string>,
  mentioned: string[],
): Promise<string> {
  const passing = grades.passing;
  const unmetCodes = program?.spec ? unmetRequirements(program.spec, grades).map((course) => course.code) : [];
  const lookupCodes = [...new Set([...mentioned, ...unmetCodes])];

  const [subjectCourses, lookedUp] = await Promise.all([
    program?.subject ? coursesForSubject(program.subject) : Promise.resolve([] as CourseRow[]),
    lookupCodes.length ? coursesByCode(lookupCodes) : Promise.resolve([] as CourseRow[]),
  ]);
  const byCode = new Map<string, CourseRow>();
  for (const course of [...subjectCourses, ...lookedUp]) {
    if (!byCode.has(course.code)) byCode.set(course.code, course);
  }

  const selected: { course: CourseRow; reason: string }[] = [];
  const seen = new Set<string>();
  const add = (code: string, reason: string) => {
    const course = byCode.get(code);
    if (!course || seen.has(code) || selected.length >= MAX_CONTEXT_COURSES) return;
    seen.add(code);
    selected.push({ course, reason });
  };

  const status = (code: string) => {
    if (passing.has(code)) return "already passed";
    if (inProgress.has(code)) return "in progress";
    const course = byCode.get(code);
    return course && prerequisitesMet(course.prerequisites, passing) ? "prerequisites met" : "prerequisites not yet met";
  };
  for (const code of mentioned) add(code, `mentioned; ${status(code)}`);
  for (const code of unmetCodes) {
    const belowC = passing.has(code) && !grades.cOrBetter.has(code);
    add(code, `required; ${belowC ? "passed below the required C; retake needed" : status(code)}`);
  }

  // Courses the student could take next. Courses without prerequisites only
  // qualify at the 3000+ level, and variable-credit listings (independent
  // study, field study, study abroad) are skipped as noise.
  const eligible = subjectCourses
    .filter((course) =>
      !taken.has(course.code) &&
      !/\d\s*-\s*\d/.test(String(course.credits ?? "")) &&
      (course.prerequisites ? prerequisitesMet(course.prerequisites, passing) : courseLevel(course.code) >= 3000)
    )
    .sort((a, b) => Number(Boolean(b.prerequisites)) - Number(Boolean(a.prerequisites)) || a.code.localeCompare(b.code));
  for (const course of eligible) add(course.code, "prerequisites met");

  if (!selected.length) return "";
  const lines = selected.map(({ course, reason }) => {
    const prereqs = course.prerequisites ? `; prereqs: ${course.prerequisites}` : "";
    const description = course.description ? `; ${course.description.slice(0, 160)}` : "";
    return `- ${course.code}: ${course.name} (${course.credits ?? "?"} credits; ${reason}${prereqs})${description}`;
  });
  return `Relevant catalog courses:\n${lines.join("\n")}`;
}

async function coursesForSubject(subject: string): Promise<CourseRow[]> {
  const params = {
    select: "code,name,credits,prerequisites,description",
    subject: `eq.${subject}`,
    order: "code.asc",
    limit: "400",
  };
  const [coe, catalog] = await Promise.all([
    catalogQuery("coe_courses", params),
    catalogQuery("catalog_courses", params),
  ]);
  return [...coe, ...catalog].map(toCourseRow);
}

async function coursesByCode(codes: string[]): Promise<CourseRow[]> {
  const params = {
    select: "code,name,credits,prerequisites,description",
    code: inList(codes),
    limit: "100",
  };
  const [coe, catalog] = await Promise.all([
    catalogQuery("coe_courses", params),
    catalogQuery("catalog_courses", params),
  ]);
  return [...coe, ...catalog].map(toCourseRow);
}

function toCourseRow(row: Row): CourseRow {
  return {
    code: normalizeCode(row.code),
    name: stringValue(row.name),
    credits: row.credits,
    prerequisites: stringValue(row.prerequisites),
    description: stringValue(row.description),
  };
}

// Treats "and", ";" and "," as clause separators and each clause as satisfied
// when any course code in it has been passed ("(CS 2505 or ECE 2564) and
// MATH 2534"). Clauses without course codes (e.g. "junior standing") are
// ignored. Courses without prerequisites always qualify.
export function prerequisitesMet(text: string, passing: Set<string>): boolean {
  if (!text.trim()) return true;
  const clauses = text.split(/\band\b|;|,/i);
  return clauses.every((clause) => {
    const codes = codesIn(clause);
    return !codes.length || codes.some((code) => passing.has(code));
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

type GradeSets = { passing: Set<string>; cOrBetter: Set<string> };

function gradeSets(transcript: TranscriptEntry[]): GradeSets {
  const passing = new Set<string>();
  const cOrBetter = new Set<string>();
  for (const entry of transcript) {
    const grade = entry.grade ?? null;
    if (!isPassing(grade)) continue;
    const code = normalizeCode(entry.code);
    passing.add(code);
    if (isAwardedCreditGrade(grade) || (GRADE_POINTS[normalizeGradeKey(grade)] ?? -1) >= 2.0) cOrBetter.add(code);
  }
  return { passing, cOrBetter };
}

function normalizeGradeKey(grade: string | null): string {
  return (grade || "").trim().toUpperCase();
}

function courseLevel(code: string): number {
  const match = code.match(/(\d{4})/);
  return match ? Number(match[1]) : 0;
}

// Course codes the student typed. "CS 3114" is taken as written; lowercase
// "cs 3114" is accepted too, unless it reads like ordinary words or a year
// ("fall 2026", "in 2024").
export function mentionedCodes(text: string): string[] {
  const codes: string[] = [];
  for (const match of text.matchAll(/\b([A-Za-z]{2,4})[\s-]?(\d{4}[A-Za-z]?)\b/g)) {
    const [, subject, number] = match;
    const typedUppercase = subject === subject.toUpperCase();
    const looksLikeYear = /^(19|20)\d\d$/.test(number);
    if (!typedUppercase && (looksLikeYear || NON_SUBJECT_WORDS.has(subject.toLowerCase()))) continue;
    if (typedUppercase && looksLikeYear && NON_SUBJECT_WORDS.has(subject.toLowerCase())) continue;
    codes.push(`${subject.toUpperCase()} ${number.toUpperCase()}`);
  }
  return [...new Set(codes)].slice(0, MAX_MENTIONED_CODES);
}

const NON_SUBJECT_WORDS = new Set([
  "a", "an", "and", "as", "at", "by", "fall", "for", "from", "in", "into", "is", "it", "of", "on", "or",
  "over", "past", "than", "the", "to", "till", "up", "year", "fy", "ay", "with", "was", "this", "that",
]);

function codesIn(text: string): string[] {
  return [...text.matchAll(COURSE_CODE_PATTERN)].map((match) => `${match[1]} ${match[2]}`);
}

async function firstRow(table: string, params: Record<string, string>): Promise<Row | null> {
  return (await restSelect(table, { ...params, limit: params.limit ?? "1" }))[0] ?? null;
}

async function firstCatalogRow(table: string, params: Record<string, string>): Promise<Row | null> {
  return (await catalogQuery(table, { ...params, limit: "1" }))[0] ?? null;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value.trim() : value == null ? "" : String(value);
}

function dateOnly(value: unknown): string {
  return stringValue(value).slice(0, 10) || "unknown date";
}

function clip(text: string, limit: number): string {
  return text.length <= limit ? text : `${text.slice(0, limit)}…`;
}
