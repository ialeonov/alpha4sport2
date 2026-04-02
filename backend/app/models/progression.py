from datetime import date, datetime

from sqlalchemy import JSON, Date, DateTime, Float, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.session import Base


class UserProgression(Base):
    __tablename__ = 'user_progressions'

    user_id: Mapped[int] = mapped_column(
        ForeignKey('users.id', ondelete='CASCADE'),
        primary_key=True,
    )
    total_xp: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    current_streak: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    best_streak: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_completed_workouts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    total_pr_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    ideal_weeks_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    ideal_months_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    last_calculated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ProgressAchievement(Base):
    __tablename__ = 'progress_achievements'
    __table_args__ = (
        UniqueConstraint('user_id', 'code', name='uq_progress_achievement_user_code'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    code: Mapped[str] = mapped_column(String(80), nullable=False)
    achieved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    metadata_json: Mapped[dict | None] = mapped_column(JSON)


class ProgressRewardEvent(Base):
    __tablename__ = 'progress_reward_events'
    __table_args__ = (
        UniqueConstraint('user_id', 'event_key', name='uq_progress_reward_event_user_key'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    event_key: Mapped[str] = mapped_column(String(160), nullable=False)
    event_type: Mapped[str] = mapped_column(String(80), nullable=False)
    xp_awarded: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    metadata_json: Mapped[dict | None] = mapped_column(JSON)


class ProgressExerciseRecord(Base):
    __tablename__ = 'progress_exercise_records'
    __table_args__ = (
        UniqueConstraint('user_id', 'exercise_key', name='uq_progress_record_user_exercise'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    exercise_key: Mapped[str] = mapped_column(String(160), nullable=False)
    exercise_name: Mapped[str] = mapped_column(String(120), nullable=False)
    catalog_exercise_id: Mapped[int | None] = mapped_column(
        ForeignKey('exercise_catalog.id', ondelete='SET NULL'),
        index=True,
    )
    best_weight: Mapped[float] = mapped_column(Float, default=0, nullable=False)
    best_1rm: Mapped[float] = mapped_column(Float, default=0, nullable=False)
    best_volume: Mapped[float] = mapped_column(Float, default=0, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class ProgressRecordEvent(Base):
    __tablename__ = 'progress_record_events'
    __table_args__ = (
        UniqueConstraint(
            'user_id',
            'workout_id',
            'exercise_key',
            'record_type',
            name='uq_progress_record_event_identity',
        ),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    workout_id: Mapped[int] = mapped_column(ForeignKey('workouts.id', ondelete='CASCADE'), index=True)
    exercise_key: Mapped[str] = mapped_column(String(160), nullable=False)
    exercise_name: Mapped[str] = mapped_column(String(120), nullable=False)
    record_type: Mapped[str] = mapped_column(String(40), nullable=False)
    value: Mapped[float] = mapped_column(Float, nullable=False)
    achieved_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class SickLeave(Base):
    __tablename__ = 'sick_leaves'

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    reason: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(16), default='active', nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
