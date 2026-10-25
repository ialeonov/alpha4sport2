from sqlalchemy import ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class UserProfile(Base):
    __tablename__ = 'user_profiles'

    user_id: Mapped[int] = mapped_column(
        ForeignKey('users.id', ondelete='CASCADE'),
        primary_key=True,
    )
    goal: Mapped[str | None] = mapped_column(String(50))
    experience: Mapped[str | None] = mapped_column(String(50))
    gender: Mapped[str | None] = mapped_column(String(20))
    injuries: Mapped[str | None] = mapped_column(Text)
    days_per_week: Mapped[int | None] = mapped_column(Integer)
    birth_year: Mapped[int | None] = mapped_column(Integer)
    height_cm: Mapped[int | None] = mapped_column(Integer)
    preferred_days: Mapped[str | None] = mapped_column(String(40))
    coach_notes: Mapped[str | None] = mapped_column(Text)
