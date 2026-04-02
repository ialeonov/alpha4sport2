from datetime import datetime

from pydantic import BaseModel, Field


class PublicUserSummary(BaseModel):
    id: int
    displayName: str
    avatarUrl: str | None = None
    level: int
    totalXp: int
    currentStreak: int
    lastActivityAt: datetime | None = None


class AccountEventUser(BaseModel):
    id: int
    displayName: str
    avatarUrl: str | None = None


class AccountEventOut(BaseModel):
    id: int
    eventType: str
    description: str
    createdAt: datetime
    user: AccountEventUser
    likesCount: int = 0
    isLikedByMe: bool = False


class UpdateDisplayNameRequest(BaseModel):
    displayName: str = Field(min_length=2, max_length=40)
