# Agora — Partner Product Overview

**Your next chapter**  
*Understand your degree. Plan what’s next.*

Prepared November 10, 2026.

## What Agora is

Agora is an iPhone app that helps students understand their academic records, track degree progress, ask personalized academic questions, and organize the details of their current classes.

It brings together information that students normally search for across transcripts, degree audits, syllabi, registration pages, and past advising conversations.

The initial audience is Virginia Tech students. The broader vision is one academic platform that can adapt to different universities, with each school’s identity, academic requirements, and course information.

**Status note:** This overview reflects the current app code. “Built” means implemented in the project; features that use online services still depend on the corresponding services and database changes being configured and deployed. The November 10 QA review confirmed that the live courses service is missing and the live chat service needs its authentication fix deployed. See the [QA report](/Users/mula/HokieAdvisor/docs/AGORA_QA_REPORT_2026-11-10.md) before describing the app as launch-ready.

## 1. Accounts, onboarding, and school identity

Students can create an account, sign in, and return to their saved academic information. The app maintains their session and provides sign-out and account-management controls.

Agora has its own brand, while the school supplies the accent colors, school name, and campus-specific wording. After sign-in, a school welcome screen leads into the app. Virginia Tech’s welcome says “Let’s go, Hokies.” Its presentation supports school artwork with a gradient fallback.

**Current scope:** Virginia Tech is the only enabled school. The theme structure supports expansion, but adding another university also requires its academic data and advising support.

## 2. Personalized Home dashboard

Home brings the student’s academic information and next actions into one screen:

- Personalized greeting, school, program, and graduation year when available.
- A transcript-import starting point for new users.
- Academic statistics and degree progress when sufficient records are available.
- A suggested next action based on the student’s current state.
- Direct access to the AI advisor.
- A “This term” area for current courses and registration information.
- Study and planning tips, plus support prompts for courses the student reports struggling with.

The dashboard changes as the student adds information, rather than displaying invented academic results before an import.

## 3. Transcript import and academic record

Students can upload a transcript as a PDF, PNG, or JPEG. Automated reading extracts course names and codes, grades, credits, and semesters. That information supports the academic summary, degree estimate, and advisor context.

Students can review the imported course list and re-upload a clearer or updated transcript. A replacement import replaces the previous record. They can also mark whether current classes are going well or identify courses where they need support.

**Current limitation:** Individual imported transcript courses cannot be edited in the app. Automated extraction can make mistakes, so reviewing the result is part of the workflow.

## 4. Degree progress and official audit import

Agora provides two related views of academic progress:

**Transcript-based estimate:** For the supported Virginia Tech Computer Science B.S., the app uses programmed academic rules to organize completed credits and requirement groups, identify outstanding requirements, and flag issues such as minimum grades or retakes. It includes relevant electives and Pathways requirements.

**Imported official audit:** Students can upload a DARS/uAchieve audit as a PDF or image. The official audit appears first and takes priority over Agora’s transcript estimate. It can be replaced or removed.

This helps students answer questions such as “What have I completed?” and “Which requirements still need attention?”

**Current scope:** Students in other programs can import an official audit and use the advisor, but the app does not calculate a transcript-based degree estimate for every major. Agora does not log into DARS automatically or issue an official graduation determination.

## 5. Personalized AI academic advisor

The advisor supports questions about requirements, course choices, academic progress, and planning. Its context includes available profile information, imported coursework, in-progress courses, saved memories, recent audit results, and relevant catalog information.

Course context prioritizes courses mentioned in the conversation, unmet requirements, and courses for which the available record suggests prerequisites have been satisfied. The advisor also receives date and semester context.

Example questions include:

- “What do I still need to graduate?”
- “Which requirements should I prioritize next semester?”
- “What prerequisite is blocking me from taking this course?”
- “Explain what this section of my degree audit means.”

Responses appear progressively as they are generated. Long answers can be continued, and interrupted responses retain the text already received.

**Boundary:** This is personalized guidance, not a guarantee of course availability, registration eligibility, admission, or graduation. Full editable semester-by-semester roadmaps are not yet implemented. The current advisor context does not automatically include the new syllabus dashboard’s confirmed facts.

## 6. Tutoring, attachments, and learning visuals

The same Advisor screen supports learning questions, particularly math and computer science:

- Step-by-step explanations and worked examples.
- Properly rendered mathematical notation.
- Formatted code examples.
- Graph diagrams with directed arrows, edge weights, and traversal steps when provided in the response.
- Next/Previous controls for supported graph walkthroughs.

Students can attach a photo, a text-based PDF, or a text file to a question. Photos are resized and compressed; PDF text is extracted on the device. Size and document limits produce clear errors.

**Current limits:** Chat PDFs need selectable text; scanned pages can be submitted as photos instead. Chat attachments are sent with the relevant question, while saved history retains their names rather than the original files. Voice input is not implemented.

## 7. Saved conversations and personal memory

Conversations save automatically and can be reopened or deleted. Students do not have to start from scratch each time they return.

Agora also maintains short memory notes, such as study preferences or academic goals. Students can add, edit, and delete memories in Profile, including deleting all of them. The advisor can extract concise facts from messages, and recurring study topics can be remembered.

Memories are separate from the official academic record; a remembered preference does not change degree requirements.

## 8. Current courses and private syllabus uploads

The “This term” feature lets students add courses with their course code, term, section identifier/CRN, and instructor. Suggestions can use existing in-progress coursework.

Each course has its own dashboard and syllabus status. Students can upload a PDF, PNG, or JPEG syllabus, add a later version, or remove a version or course.

The syllabus workflow reads text on the device and sends that text to the AI service for structured extraction. Uploaded syllabi and extracted details are scoped to the student’s account.

**Current behavior:** Syllabi are private, not shared with future students. Students are encouraged to add them, but uploading a syllabus is not required to use the rest of Agora. If one is unavailable, they can set a reminder to add it later.

## 9. Syllabus review and course dashboard

The app organizes information found in a syllabus into:

- Exams and assignment deadlines.
- Exam format, such as online, in-person, take-home, or proctored, when stated.
- Office hours and instructor contact details.
- Attendance and participation rules.
- Grading categories and percentage weights.
- Late-work and makeup policies.
- Required materials and other restrictions.

Before extracted facts are used, students review them against the source page and excerpt. They can confirm, reject, or correct an item. Corrections remain separate from the original extracted information.

The app flags ambiguous dates, mismatched terms, conflicts, and unsupported information. It does not turn “Week 6” into a guessed calendar date. The dashboard highlights the next confirmed date and organizes the remaining reviewed details.

When a new syllabus is uploaded, the student can review what changed. The previous reviewed information remains in use until the new review is finished.

## 10. Course reminders

Students can opt into device notifications for confirmed syllabus dates, choosing a week before, the day before, or the morning of an event.

If an updated syllabus changes a date, the affected reminder requires confirmation rather than silently moving. Deleting the associated syllabus or course removes its reminders and cancels notifications on that device.

These are app notifications; automatic synchronization with Apple Calendar or Google Calendar is not part of the current feature.

## 11. Registration guidance

The app includes a guide to course requests, enrollment, add/drop, and withdrawal, with term-specific dates and links to official sources.

It distinguishes dropping a course from withdrawing and shows source information, when it was checked, and relevant audience or tentative-date labels.

**Boundary:** Students still complete registration changes in their school’s official system. Agora does not enroll, drop, or withdraw them from courses.

## 12. Profile, appearance, help, and data controls

Profile provides access to personal information, graduation year, transcript records, saved conversations, memories, and Help & FAQ. The app supports light, dark, and system appearance, with accessibility support in its interface.

Students have separate actions to sign out, clear data from the current device, or request account deletion. Course and syllabus deletion controls are also available.

The project includes authenticated online requests, account-specific data access, and chat input and usage controls. These safeguards still require deployment and testing; they are not a claim of independent security certification or regulatory compliance.

## Expansion roadmap — not current functionality

| Planned capability | Intended student benefit | Current status |
|---|---|---|
| Additional schools and majors | Use Agora with the correct identity, catalog, and requirements for each institution | Theme foundation exists; VT is the only enabled school |
| Editable multi-semester roadmaps | Build and revise a path toward graduation | Not implemented |
| Transfer planning | Explore how NOVA coursework could apply toward a destination degree | Planning document exists; no working transfer engine |
| Destination comparisons | Compare VT, UVA, JMU, and other destinations | Future expansion |
| Shared historical syllabi | Learn about previous sections before choosing a class | Deferred; current uploads are private |
| Professor/course feedback | Understand prior students’ experiences | No built-in review system or Rate My Professors integration |
| Syllabus-aware advisor | Ask the advisor about confirmed course dates and policies automatically | Dashboard exists; automatic chat integration remains to be added |
| Institutional tools and integrations | Support advisor review, university administration, and connected school systems | Future work; no live Canvas/SIS integration |

## Typical student journey

1. Create an account and enter the school experience.
2. Import a transcript and review the extracted record.
3. Import an official degree audit, if available.
4. Review academic progress and ask personalized questions.
5. Add current course sections and upload their syllabi.
6. Confirm extracted dates and policies, then enable useful reminders.
7. Return throughout the term for course details, tutoring, registration guidance, and saved conversations.

## Partner-facing description

**Agora helps students understand their degree and stay on top of their classes. It combines transcript and degree-audit information, a personalized AI advisor, tutoring tools, and reviewed syllabus details in one iPhone app. Starting at Virginia Tech, the long-term goal is a platform that adapts to each school and supports students through academic planning and future transfers.**

The immediate product milestone is a reliable end-to-end VT pilot, including verifying the new course and syllabus services in the running app. Broader school support and transfer planning are subsequent milestones rather than features to advertise as available today.
