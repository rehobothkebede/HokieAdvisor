import { normalizeGrade } from "./academic.ts";

// Virginia Tech grading rules and the Computer Science B.S. (2025-2026)
// requirements, shared by the audit and chat functions. These mirror
// backend/data/catalog/computer_science.json. When migration 005's
// institutions / degree_audit_specs tables are populated, this module becomes
// the VT fallback rather than the source of truth.

export type CourseRequirement = {
  code: string;
  name: string;
  credits: number;
  gradeRequired?: "C";
};

export const TOTAL_REQUIRED_CREDITS = 123;
export const FREE_ELECTIVE_CREDITS = 10;

export const GRADE_POINTS: Record<string, number> = {
  "A": 4.0,
  "A-": 3.7,
  "B+": 3.3,
  "B": 3.0,
  "B-": 2.7,
  "C+": 2.3,
  "C": 2.0,
  "C-": 1.7,
  "D+": 1.3,
  "D": 1.0,
  "D-": 0.7,
  "F": 0.0,
  "W": 0.0,
  "WF": 0.0,
};

export const NON_CREDIT_GRADES = new Set(["F", "W", "WF", "I", "NG"]);
export const AWARDED_CREDIT_GRADES = new Set(["P", "PASS", "CR", "CREDIT", "T", "TR", "TRANSFER"]);

export const REQUIRED_COURSES: CourseRequirement[] = [
  { code: "CS 1114", name: "Intro to Software Design", credits: 3, gradeRequired: "C" },
  { code: "ENGE 1215", name: "Foundations of Engineering", credits: 2 },
  { code: "ENGL 1105", name: "First-Year Writing", credits: 3 },
  { code: "MATH 1225", name: "Calculus of a Single Variable I", credits: 4 },
  { code: "CS 2114", name: "Software Design & Data Structures", credits: 3, gradeRequired: "C" },
  { code: "ENGE 1216", name: "Foundations of Engineering", credits: 2 },
  { code: "ENGL 1106", name: "First-Year Writing", credits: 3 },
  { code: "MATH 1226", name: "Calculus of a Single Variable II", credits: 4 },
  { code: "CS 1944", name: "CS First Year Seminar", credits: 1 },
  { code: "CS 2104", name: "Intro to Problem Solving in CS", credits: 3, gradeRequired: "C" },
  { code: "CS 2505", name: "Intro to Computer Organization I", credits: 3, gradeRequired: "C" },
  { code: "MATH 2534", name: "Intro to Discrete Mathematics", credits: 3 },
  { code: "CS 2506", name: "Intro to Computer Organization II", credits: 3, gradeRequired: "C" },
  { code: "MATH 2114", name: "Intro to Linear Algebra", credits: 3 },
  { code: "MATH 2204", name: "Intro to Multivariable Calculus", credits: 3 },
  { code: "CS 3114", name: "Data Structures & Algorithms", credits: 3, gradeRequired: "C" },
  { code: "MATH 3134", name: "Applied Combinatorics", credits: 3 },
  { code: "ENGE 3900", name: "Bridge Experience", credits: 0 },
  { code: "CS 3214", name: "Computer Systems", credits: 3 },
  { code: "CS 3604", name: "Professionalism in Computing", credits: 3 },
  { code: "CS 3304", name: "Comparative Languages", credits: 3 },
  { code: "CS 4944", name: "CS Seminar", credits: 1 },
  { code: "CS 4094", name: "Computer Science Capstone", credits: 3 },
];

export const SUBSTITUTIONS: Record<string, string[]> = {
  "ENGE 1215": ["ENGE 1414"],
  "ENGE 1216": ["ENGE 1414"],
  "MATH 2114": ["MATH 2405H", "MATH 2406H"],
  "MATH 2204": ["MATH 2405H", "MATH 2406H"],
  "CS 1114": ["CS 2064", "ECE 2514"],
  "CS 2114": ["ECE 3514"],
  "CS 2505": ["ECE 2564"],
};

export const NATURAL_SCIENCE = new Set(["BIOL 1105", "BIOL 1115", "CHEM 1035", "CHEM 1045", "PHYS 2305"]);
export const ADVANCED_SCIENCE = new Set(["BIOL 1106", "BIOL 1116", "CHEM 1036", "CHEM 1046", "PHYS 2306"]);
export const COMMUNICATIONS = new Set(["COMM 2004", "COMM 2014"]);
export const WRITING = new Set(["ENGL 3764", "ENGL 3804", "ENGL 3814", "ENGL 3824", "ENGL 3834", "ENGL 3844", "ENGL 4824"]);

export function isPassing(grade: string | null): boolean {
  const normalized = normalizeGrade(grade);
  if (!normalized || NON_CREDIT_GRADES.has(normalized)) return false;
  if (isAwardedCreditGrade(normalized)) return true;
  return (GRADE_POINTS[normalized] ?? 0) > 0;
}

export function isAwardedCreditGrade(grade: string | null): boolean {
  const normalized = normalizeGrade(grade);
  return normalized ? AWARDED_CREDIT_GRADES.has(normalized) : false;
}

// ---------------------------------------------------------------------------
// Program specs used for advisor chat context
// ---------------------------------------------------------------------------

export type ProgramSpec = {
  subject: string;
  name: string;
  degree: string;
  catalogYear: string;
  totalCredits: number;
  requiredCourses: CourseRequirement[];
  substitutions: Record<string, string[]>;
  notes: string[];
};

export const VT_PROGRAMS: Record<string, ProgramSpec> = {
  CS: {
    subject: "CS",
    name: "Computer Science",
    degree: "B.S.",
    catalogYear: "2025-2026",
    totalCredits: TOTAL_REQUIRED_CREDITS,
    requiredCourses: REQUIRED_COURSES,
    substitutions: SUBSTITUTIONS,
    notes: [
      "C or better required in core CS courses marked (C).",
      "Natural science: two lecture+lab sequences, 8 credits (BIOL 1105/1115 + 1106/1116, CHEM 1035/1045 + 1036/1046, or PHYS 2305 + 2306).",
      "Communications: COMM 2004 or COMM 2014. Technical writing: one of ENGL 3764, 3804, 3814, 3824, 3834, 3844, 4824.",
      "CS technical electives: 3000/4000-level CS courses beyond the required core, per the CS checksheet.",
      "30 credits of non-technical courses (outside science, math, statistics, and College of Engineering departments).",
      "CS 4094 Capstone requires CS 2505 and CS 3114.",
      "Pathways 7 is suspended as of Oct. 1, 2025; its 3 credits count as a free elective.",
    ],
  },
};

// Major names and abbreviations a profile may hold, mapped to a subject code.
// Mirrors MAJOR_TO_COE in backend/app/services/coe_service.py.
const MAJOR_ALIASES: Record<string, string> = {
  "computer science": "CS",
  "computer science bs": "CS",
  "computer science b.s.": "CS",
  "cs": "CS",
};

export function resolveMajorSubject(major: string): string | null {
  const key = major.trim().toLowerCase().replace(/\s+/g, " ");
  if (!key) return null;
  if (MAJOR_ALIASES[key]) return MAJOR_ALIASES[key];
  const withoutDegree = key.replace(/\s*\(?(b\.?s\.?|b\.?a\.?)\)?$/, "").trim();
  return MAJOR_ALIASES[withoutDegree] || null;
}
