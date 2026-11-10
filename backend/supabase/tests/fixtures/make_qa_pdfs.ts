// Writes the synthetic QA syllabi as real (text-layer) PDFs so the iOS upload
// path, including on-device PDFKit text extraction, can be exercised.
//   deno run -A backend/supabase/tests/fixtures/make_qa_pdfs.ts

import { QA_V1_PAGES, QA_V2_PAGES } from "./qa_syllabi.ts";
import type { PageText } from "../../functions/courses/extraction.ts";

function escape(text: string): string {
  return text.replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)").replace(/[^\x20-\x7e]/g, "-");
}

function wrap(line: string, width = 88): string[] {
  const words = line.split(" ");
  const out: string[] = [];
  let current = "";
  for (const word of words) {
    if ((current + " " + word).trim().length > width) {
      out.push(current);
      current = word;
    } else {
      current = (current + " " + word).trim();
    }
  }
  out.push(current);
  return out;
}

export function buildPDF(pages: PageText[]): Uint8Array<ArrayBuffer> {
  const objects: string[] = [];
  const add = (body: string) => objects.push(body); // object number = index + 1
  add("<< /Type /Catalog /Pages 2 0 R >>");
  add("PAGES_PLACEHOLDER");
  add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
  const pageRefs: number[] = [];
  for (const page of pages) {
    const lines = page.text.split("\n").flatMap((l) => (l ? wrap(l) : [""]));
    const stream = ["BT", "/F1 11 Tf", "14 TL", "54 740 Td", ...lines.map((l) => `(${escape(l)}) '`), "ET"].join("\n");
    add(`<< /Length ${stream.length} >>\nstream\n${stream}\nendstream`);
    const contentRef = objects.length;
    add(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentRef} 0 R >>`);
    pageRefs.push(objects.length);
  }
  objects[1] = `<< /Type /Pages /Kids [${pageRefs.map((n) => `${n} 0 R`).join(" ")}] /Count ${pageRefs.length} >>`;

  let out = "%PDF-1.4\n";
  const offsets: number[] = [];
  objects.forEach((body, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) out += `${String(offset).padStart(10, "0")} 00000 n \n`;
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(out);
}

if (import.meta.main) {
  const dir = new URL(".", import.meta.url);
  await Deno.writeFile(new URL("qa_syllabus_v1.pdf", dir), buildPDF(QA_V1_PAGES));
  await Deno.writeFile(new URL("qa_syllabus_v2.pdf", dir), buildPDF(QA_V2_PAGES));
  console.log("Wrote qa_syllabus_v1.pdf and qa_syllabus_v2.pdf");
}
