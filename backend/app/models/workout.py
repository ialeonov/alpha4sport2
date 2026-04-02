from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


class Workout(Base):
    __tablename__ = 'workouts'

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)

    exercises: Mapped[list['WorkoutExercise']] = relationship(
        back_populates='workout', cascade='all, delete-orphan', order_by='WorkoutExercise.position'
    )


class WorkoutExercise(Base):
    __tablename__ = 'workout_exercises'

    id: Mapped[int] = mapped_column(primary_key=True)
    workout_id: Mapped[int] = mapped_column(ForeignKey('workouts.id', ondelete='CASCADE'), index=True)
    catalog_exercise_id: Mapped[int | None] = mapped_column(
        ForeignKey('exercise_catalog.id', ondelete='SET NULL'),
        index=True,
    )
    exercise_name: Mapped[str] = mapped_column(String(120), nullable=False, index=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)

    workout: Mapped[Workout] = relationship(back_populates='exercises')
    sets: Mapped[list['ExerciseSet']] = relationship(
        back_populates='workout_exercise', cascade='all, delete-orphan', order_by='ExerciseSet.position'
    )


class ExerciseSet(Base):
    __tablename__ = 'exercise_sets'

    id: Mapped[int] = mapped_column(primary_key=True)
    workout_exercise_id: Mapped[int] = mapped_column(ForeignKey('workout_exercises.id', ondelete='CASCADE'), index=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    reps: Mapped[int] = mapped_column(Integer, nullable=False)
    weight: Mapped[float | None] = mapped_column(Float)
    rpe: Mapped[float | None] = mapped_column(Float)
    notes: Mapped[str | None] = mapped_column(Text)

    workout_exercise: Mapped[WorkoutExercise] = relationship(back_populates='sets')


class WorkoutTemplate(Base):
    __tablename__ = 'workout_templates'

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)

    exercises: Mapped[list['WorkoutTemplateExercise']] = relationship(
        back_populates='template', cascade='all, delete-orphan', order_by='WorkoutTemplateExercise.position'
    )


class WorkoutTemplateExercise(Base):
    __tablename__ = 'workout_template_exercises'

    id: Mapped[int] = mapped_column(primary_key=True)
    template_id: Mapped[int] = mapped_column(ForeignKey('workout_templates.id', ondelete='CASCADE'), index=True)
    catalog_exercise_id: Mapped[int | None] = mapped_column(
        ForeignKey('exercise_catalog.id', ondelete='SET NULL'),
        index=True,
    )
    exercise_name: Mapped[str] = mapped_column(String(120), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    target_sets: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    target_reps: Mapped[str | None] = mapped_column(String(40))

    template: Mapped[WorkoutTemplate] = relationship(back_populates='exercises')


class ExerciseCatalog(Base):
    __tablename__ = 'exercise_catalog'
    __table_args__ = (
        UniqueConstraint('user_id', 'slug', name='uq_exercise_catalog_user_slug'),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id', ondelete='CASCADE'), index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    slug: Mapped[str] = mapped_column(String(160), nullable=False)
    primary_muscle: Mapped[str] = mapped_column(String(40), nullable=False)
    secondary_muscle_links: Mapped[list['ExerciseSecondaryMuscle']] = relationship(
        back_populates='exercise',
        cascade='all, delete-orphan',
        order_by='ExerciseSecondaryMuscle.position',
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)


class ExerciseSecondaryMuscle(Base):
    __tablename__ = 'exercise_secondary_muscles'

    id: Mapped[int] = mapped_column(primary_key=True)
    exercise_id: Mapped[int] = mapped_column(
        ForeignKey('exercise_catalog.id', ondelete='CASCADE'),
        index=True,
        nullable=False,
    )
    muscle: Mapped[str] = mapped_column(String(40), nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=1)

    exercise: Mapped[ExerciseCatalog] = relationship(back_populates='secondary_muscle_links')
