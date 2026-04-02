from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class EventLike(Base):
    __tablename__ = 'event_likes'
    __table_args__ = (
        UniqueConstraint('user_id', 'event_id', name='uq_event_likes_user_event'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey('users.id', ondelete='CASCADE'), index=True
    )
    event_id: Mapped[int] = mapped_column(
        ForeignKey('account_events.id', ondelete='CASCADE'), index=True
    )
