from pydantic import BaseModel, Field


class AnnouncementOut(BaseModel):
    id: int
    title: str
    body: str
    is_active: bool
    created_by_user_id: int | None = None
    created_at: str
    updated_at: str


class AnnouncementEnvelope(BaseModel):
    announcement: AnnouncementOut | None = None


class AnnouncementUpsertRequest(BaseModel):
    title: str = Field(min_length=3, max_length=160)
    body: str = Field(min_length=3, max_length=4000)
