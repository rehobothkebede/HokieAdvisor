import {
  corsHeaders,
  errorResponse,
  json,
  methodNotAllowed,
  stringArray,
} from "../_shared/academic.ts";
import { requireUser } from "../_shared/auth.ts";

type TutoringRequest = {
  struggling_courses?: string[];
  completed_courses?: string[];
  major?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return methodNotAllowed();
  }

  const auth = await requireUser(req);
  if (auth.response) return auth.response;

  let body: TutoringRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse("TUTORING_INVALID_JSON", "Invalid JSON body.", 400);
  }

  const strugglingCourses = stringArray(body.struggling_courses);
  if (!strugglingCourses.length) {
    return errorResponse("TUTORING_COURSES_REQUIRED", "struggling_courses cannot be empty", 400);
  }

  return json({
    resources: [
      {
        name: "Virginia Tech Student Success Center",
        type: "Tutoring",
        description: `Start with tutoring or academic coaching for ${strugglingCourses.slice(0, 3).join(", ")}.`,
        link: "https://studentsuccess.vt.edu/",
      },
      {
        name: "CS Office Hours and Course Staff",
        type: "Course support",
        description: "Use the current course Canvas page, TA office hours, and instructor office hours for assignment-specific help.",
        link: null,
      },
      {
        name: "MyAdvisor",
        type: "Planning",
        description: "Ask MyAdvisor to plan study time around your deadlines or find a course's office hours. For help with the material itself, use office hours or tutoring.",
        link: null,
      },
    ],
    tips: [
      "Bring one concrete problem or confusing lecture topic to each help session.",
      "Ask for feedback on your approach before asking for the final answer.",
      "Schedule support early in the week so you have time to apply it before deadlines.",
    ],
    encouragement: `You are not behind because you need help with ${strugglingCourses[0]}. Treat this like debugging: isolate the smallest confusing step, get feedback, and iterate.`,
  });
});
