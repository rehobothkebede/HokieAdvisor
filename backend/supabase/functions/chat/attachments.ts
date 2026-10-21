// Attachments sent with the newest user message: at most one photo (base64
// JPEG/PNG, already downscaled on the device) and one document (text the app
// extracted from a PDF or text file). The iOS limits are 1.5 MB and 20,000
// characters; the server allows a little headroom over both.

export const MAX_IMAGE_BYTES = 2_000_000;
export const MAX_DOCUMENT_CHARS = 25_000;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png"]);

export type ChatAttachments = {
  image?: { name: string; mimeType: string; dataBase64: string };
  document?: { name: string; text: string };
};

export type OpenAIContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string; detail: "auto" } };

export type AttachmentError = { code: string; message: string; status: number };

export function parseAttachments(raw: unknown): ChatAttachments | AttachmentError {
  if (raw == null) return {};
  if (!Array.isArray(raw)) return invalid("Attachments must be a list.");

  const result: ChatAttachments = {};
  for (const item of raw) {
    if (!item || typeof item !== "object") return invalid("An attachment could not be read.");
    const entry = item as Record<string, unknown>;
    const name = typeof entry.name === "string" && entry.name.trim() ? entry.name.trim().slice(0, 200) : "attachment";

    if (entry.type === "image") {
      if (result.image) return invalid("Attach one photo at a time.");
      const mimeType = typeof entry.mime_type === "string" ? entry.mime_type.toLowerCase() : "";
      const data = typeof entry.data_base64 === "string" ? entry.data_base64.replace(/\s/g, "") : "";
      if (!ALLOWED_IMAGE_TYPES.has(mimeType)) return invalid("Photos must be JPEG or PNG.");
      if (!data || data.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(data)) {
        return invalid("The photo data could not be read.");
      }
      if (decodedLength(data) > MAX_IMAGE_BYTES) {
        return {
          code: "CHAT_ATTACHMENT_TOO_LARGE",
          message: "That photo is too large to send (max 2 MB). Try cropping it.",
          status: 413,
        };
      }
      result.image = { name, mimeType, dataBase64: data };
    } else if (entry.type === "document") {
      if (result.document) return invalid("Attach one document at a time.");
      const text = typeof entry.text === "string" ? entry.text.trim() : "";
      if (!text) return invalid("That document has no readable text.");
      if (text.length > MAX_DOCUMENT_CHARS) {
        return {
          code: "CHAT_ATTACHMENT_TOO_LARGE",
          message: `That document is too long (max ${MAX_DOCUMENT_CHARS.toLocaleString("en-US")} characters of text).`,
          status: 413,
        };
      }
      result.document = { name, text };
    } else {
      return invalid("Only photos and documents can be attached.");
    }
  }
  return result;
}

export function isAttachmentError(value: ChatAttachments | AttachmentError): value is AttachmentError {
  return "code" in value;
}

export function hasAttachments(attachments: ChatAttachments): boolean {
  return Boolean(attachments.image || attachments.document);
}

// The newest user message as OpenAI content: document text ahead of the
// student's words, and the photo as a vision input.
export function userContent(text: string, attachments: ChatAttachments): string | OpenAIContentPart[] {
  const body = attachments.document
    ? `Attached document "${attachments.document.name}":\n"""\n${attachments.document.text}\n"""\n\n${text}`
    : text;
  if (!attachments.image) return body;
  return [
    { type: "text", text: body },
    {
      type: "image_url",
      image_url: { url: `data:${attachments.image.mimeType};base64,${attachments.image.dataBase64}`, detail: "auto" },
    },
  ];
}

function decodedLength(base64: string): number {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return (base64.length / 4) * 3 - padding;
}

function invalid(message: string): AttachmentError {
  return { code: "CHAT_ATTACHMENT_INVALID", message, status: 400 };
}
