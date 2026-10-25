from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class AiUsageEvent(Base):
    """Один запрос к LLM: какая функция, сколько токенов, был ли ответ из кэша."""

    __tablename__ = 'ai_usage_events'

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey('users.id', ondelete='SET NULL'), index=True, nullable=True
    )
    feature: Mapped[str] = mapped_column(String(40), nullable=False)
    model: Mapped[str] = mapped_column(String(120), nullable=False, default='')
    prompt_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    completion_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # Токены не пришли от провайдера и оценены по длине текста.
    estimated: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    cache_hit: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)


class AiResponseCache(Base):
    """Серверный кэш ответов LLM, общий для всех устройств пользователя."""

    __tablename__ = 'ai_response_cache'
    __table_args__ = (
        UniqueConstraint('user_id', 'feature', 'cache_key', name='uq_ai_response_cache_key'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False
    )
    feature: Mapped[str] = mapped_column(String(40), nullable=False)
    cache_key: Mapped[str] = mapped_column(String(64), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
