from typing import Literal

from pydantic import BaseModel, Field


class CoachChatMessage(BaseModel):
    role: Literal['user', 'assistant']
    content: str = Field(min_length=1, max_length=12000)


class CoachChatRequest(BaseModel):
    messages: list[CoachChatMessage] = Field(min_length=1, max_length=20)


class CoachChatResponse(BaseModel):
    reply: str
    model: str
    context_summary: dict


class CoachHistoryMessage(BaseModel):
    id: int
    role: Literal['user', 'assistant']
    content: str
    created_at: str


class CoachHistoryResponse(BaseModel):
    messages: list[CoachHistoryMessage]
