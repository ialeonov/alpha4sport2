from datetime import datetime

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class CoachUserMemory(Base):
    __tablename__ = 'coach_user_memory'
    __table_args__ = (
        UniqueConstraint('user_id', 'key', name='uq_coach_user_memory_user_key'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False
    )
    key: Mapped[str] = mapped_column(String(80), nullable=False)
    value: Mapped[str] = mapped_column(Text, nullable=False)
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.8)
    source: Mapped[str] = mapped_column(String(40), nullable=False, default='chat')
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
