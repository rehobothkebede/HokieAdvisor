import logging
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from app.routes.errors import error_detail
from app.services import ai_guard
from app.services.ai_guard import VerifiedUser, require_user
from app.services.ai_service import chat_with_advisor, chat_stream_with_advisor
from app.services.coe_service import get_coe_context_for_major, resolve_full_major_name

# Retired for the pilot: see ai_guard.retired_for_pilot.
router = APIRouter(prefix="/chat", tags=["Advisor Chat"], dependencies=[Depends(ai_guard.retired_for_pilot)])

# Mirrors the chat Edge Function's input caps.
MAX_MESSAGES = 40
MAX_MESSAGE_CHARS = 8000
ALLOWED_ROLES = {"user", "assistant"}
_AI_FAILED = "We could not reach MyAdvisor right now. Please try again."
logger = logging.getLogger(__name__)


class Message(BaseModel):
    role: str
    content: str


class TranscriptEntry(BaseModel):
    code: str
    name: str
    grade: Optional[str] = None
    semester: Optional[str] = None
    credits: Optional[float] = None


class ChatRequest(BaseModel):
    messages: list[Message]
    major: str = "Computer Science"
    transcript: list[TranscriptEntry] = []
    in_progress_courses: list[str] = []
    transcript_notes: list[str] = []
    chat_memories: list[str] = []


class ChatResponse(BaseModel):
    reply: str
    truncated: bool = False


@router.post("", response_model=ChatResponse)
def chat(request: ChatRequest, user: VerifiedUser = Depends(require_user)):
    """
    Send a conversation to the Hokie Advisor AI (tutor / advisor).
    Pass the full message history so the bot retains context across turns.

    Optional: include `major` (e.g. "Computer Science", "ECE") to inject
    the department's course catalog into the AI's context window.

    Example body:
    {
      "major": "Computer Science",
      "messages": [
        {"role": "user", "content": "I'm really stressed about picking next semester's courses."}
      ]
    }
    """
    messages = _sanitize_messages(request.messages)
    course_context = ""
    if request.major:
        full_name = resolve_full_major_name(request.major)
        course_context = f"Student's major: {full_name}\n\n" + get_coe_context_for_major(request.major)

    transcript = [e.model_dump() for e in request.transcript]
    ai_guard.reserve(user, "chat")  # last step before the single paid call
    try:
        reply, truncated = chat_with_advisor(
            messages,
            course_context=course_context,
            transcript=transcript,
            in_progress_courses=request.in_progress_courses,
            transcript_notes=request.transcript_notes,
            chat_memories=request.chat_memories,
        )
    except Exception:
        logger.warning("Legacy chat AI request failed")
        raise HTTPException(status_code=502, detail=error_detail("CHAT_AI_REQUEST_FAILED", _AI_FAILED)) from None

    return ChatResponse(reply=reply, truncated=truncated)


def _sanitize_messages(messages: list[Message]) -> list[dict[str, str]]:
    """Keep only user/assistant turns, the last MAX_MESSAGES of them, and enforce
    the per-message cap on the newest turn (older turns are truncated)."""
    cleaned = [
        {"role": m.role, "content": m.content}
        for m in messages
        if m.role in ALLOWED_ROLES and m.content.strip()
    ][-MAX_MESSAGES:]
    if not cleaned or cleaned[-1]["role"] != "user":
        raise HTTPException(status_code=400, detail=error_detail("CHAT_MESSAGES_REQUIRED", "Send a message to start the conversation."))
    if len(cleaned[-1]["content"]) > MAX_MESSAGE_CHARS:
        raise HTTPException(
            status_code=400,
            detail=error_detail("CHAT_MESSAGE_TOO_LONG", f"That message is too long. Keep it under {MAX_MESSAGE_CHARS:,} characters."),
        )
    for message in cleaned[:-1]:
        if len(message["content"]) > MAX_MESSAGE_CHARS:
            message["content"] = message["content"][:MAX_MESSAGE_CHARS] + "…"
    return cleaned


@router.post("/stream")
def chat_stream(request: ChatRequest, user: VerifiedUser = Depends(require_user)):
    """Stream the AI advisor response token by token via Server-Sent Events."""
    messages = _sanitize_messages(request.messages)
    course_context = ""
    if request.major:
        full_name = resolve_full_major_name(request.major)
        course_context = f"Student's major: {full_name}\n\n" + get_coe_context_for_major(request.major)

    transcript = [e.model_dump() for e in request.transcript]
    ai_guard.reserve(user, "chat")
    try:
        generator = chat_stream_with_advisor(
            messages,
            course_context=course_context,
            transcript=transcript,
            in_progress_courses=request.in_progress_courses,
            transcript_notes=request.transcript_notes,
            chat_memories=request.chat_memories,
        )
    except Exception:
        logger.warning("Legacy chat stream AI request failed")
        raise HTTPException(status_code=502, detail=error_detail("CHAT_AI_REQUEST_FAILED", _AI_FAILED)) from None

    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
