from datetime import date, datetime

from pydantic import BaseModel, Field


class WellnessEntryUpsert(BaseModel):
    sleep: int = Field(ge=1, le=5)
    energy: int = Field(ge=1, le=5)
    stress: int = Field(ge=1, le=5)
    mood: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=500)


class WellnessEntryOut(WellnessEntryUpsert):
    id: int
    entry_date: date
    created_at: datetime
    updated_at: datetime

    model_config = {'from_attributes': True}
