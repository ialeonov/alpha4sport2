from typing import Literal

from pydantic import BaseModel, Field


class CoachChatMessage(BaseModel):
    role: Literal['user', 'assistant']
    content: str = Field(min_length=1, max_length=12000)


class WellnessEntryInput(BaseModel):
    date: str = Field(pattern=r'^\d{4}-\d{2}-\d{2}$')
    sleep: int = Field(ge=1, le=5)
    energy: int = Field(ge=1, le=5)
    stress: int = Field(ge=1, le=5)
    mood: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=500)


class CoachChatRequest(BaseModel):
    messages: list[CoachChatMessage] = Field(min_length=1, max_length=20)
    save_history: bool = True
    wellness_entries: list[WellnessEntryInput] | None = Field(default=None, max_length=14)


class CoachChatResponse(BaseModel):
    reply: str
    model: str
    context_summary: dict


class CoachWorkoutGenerateRequest(BaseModel):
    intensity_title: str = Field(min_length=1, max_length=40)
    min_exercises: int = Field(ge=1, le=20)
    max_exercises: int = Field(ge=1, le=20)
    user_notes: str | None = Field(default=None, max_length=500)
    wellness_entries: list[WellnessEntryInput] | None = Field(default=None, max_length=14)


class CoachWorkoutGenerateResponse(BaseModel):
    reply: str
    model: str
    context_summary: dict
    planner_summary: dict


class CoachHistoryMessage(BaseModel):
    id: int
    role: Literal['user', 'assistant']
    content: str
    created_at: str


class CoachHistoryResponse(BaseModel):
    messages: list[CoachHistoryMessage]


class OwnerCoachHistoryMessage(BaseModel):
    id: int
    user_id: int
    user_email: str
    user_display_name: str
    role: Literal['user', 'assistant']
    content: str
    created_at: str


class OwnerCoachHistoryResponse(BaseModel):
    messages: list[OwnerCoachHistoryMessage]
