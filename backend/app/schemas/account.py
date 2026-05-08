from datetime import datetime
from typing import Literal

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


GoalType = Literal['масса', 'сила', 'похудение', 'поддержание']
ExperienceType = Literal['новичок', 'средний', 'продвинутый']
GenderType = Literal['мужской', 'женский']


class FitnessProfileOut(BaseModel):
    goals: list[GoalType] = Field(default_factory=list)
    experience: ExperienceType | None = None
    gender: GenderType | None = None
    injuries: str | None = None
    daysPerWeek: int | None = None


class FitnessProfileUpdate(BaseModel):
    goals: list[GoalType] = Field(default_factory=list, max_length=2)
    experience: ExperienceType | None = None
    gender: GenderType | None = None
    injuries: str | None = Field(default=None, max_length=500)
    daysPerWeek: int | None = Field(default=None, ge=1, le=7)
