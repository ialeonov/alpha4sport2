from datetime import date, datetime

from pydantic import BaseModel, Field


class BodyEntryCreate(BaseModel):
    entry_date: date
    weight_kg: float | None = Field(default=None, ge=0, le=500)
    waist_cm: float | None = Field(default=None, ge=0, le=300)
    chest_cm: float | None = Field(default=None, ge=0, le=300)
    hips_cm: float | None = Field(default=None, ge=0, le=300)
    notes: str | None = Field(default=None, max_length=500)
    photo_path: str | None = None


class BodyEntryOut(BodyEntryCreate):
    id: int
    created_at: datetime

    model_config = {'from_attributes': True}
