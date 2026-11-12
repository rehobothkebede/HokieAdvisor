from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.routes.errors import error_detail
from app.services import ai_guard
from app.services.ai_guard import VerifiedUser, require_user
from app.services.ai_service import recommend_tutoring

# AI tutoring recommendations are outside the pilot: see ai_guard.retired_for_pilot.
router = APIRouter(prefix="/tutoring", tags=["Tutoring"], dependencies=[Depends(ai_guard.retired_for_pilot)])


class TutoringRequest(BaseModel):
    struggling_courses: List[str]
    completed_courses: List[str] = []
    major: str = ""


class TutoringResource(BaseModel):
    name: str
    type: str
    description: str
    link: Optional[str] = None


class TutoringResponse(BaseModel):
    resources: List[TutoringResource]
    tips: List[str]
    encouragement: str


@router.post("/recommend", response_model=TutoringResponse)
def get_tutoring_recommendations(request: TutoringRequest, user: VerifiedUser = Depends(require_user)):
    """
    Generate tutoring and academic support recommendations for a struggling student.
    """
    if not request.struggling_courses:
        raise HTTPException(
            status_code=400,
            detail=error_detail("TUTORING_COURSES_REQUIRED", "struggling_courses cannot be empty"),
        )

    ai_guard.reserve(user, "chat")
    try:
        result = recommend_tutoring(
            struggling_courses=request.struggling_courses,
            completed_courses=request.completed_courses,
            major=request.major,
        )
    except Exception:
        raise HTTPException(
            status_code=502,
            detail=error_detail("TUTORING_AI_REQUEST_FAILED", "We could not load recommendations right now. Please try again."),
        ) from None

    return TutoringResponse(**result)
