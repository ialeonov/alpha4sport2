from datetime import date, timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.body import BodyEntry
from app.models.user import User
from app.models.workout import ExerciseSet, Workout, WorkoutExercise

router = APIRouter()


def _normalize_exercise_name(value: str) -> str:
    return value.strip().lower().replace('ё', 'е')


@router.get('/exercise/{exercise_name}')
def exercise_progress(
    exercise_name: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    normalized_name = _normalize_exercise_name(exercise_name)
    stmt = (
        select(Workout.started_at, ExerciseSet.weight, ExerciseSet.reps)
        .join(WorkoutExercise, WorkoutExercise.workout_id == Workout.id)
        .join(ExerciseSet, ExerciseSet.workout_exercise_id == WorkoutExercise.id)
        .where(
            Workout.user_id == current_user.id,
            func.replace(func.lower(WorkoutExercise.exercise_name), 'ё', 'е') == normalized_name,
        )
        .order_by(Workout.started_at.asc())
    )
    rows = db.execute(stmt).all()
    return [
        {
            'date': row.started_at,
            'weight': row.weight,
            'reps': row.reps,
            'estimated_1rm': ((row.weight or 0) * (1 + row.reps / 30)) if row.weight else None,
        }
        for row in rows
    ]


@router.get('/weekly-volume')
def weekly_volume(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    week_start_expr = func.date_trunc(text("'week'"), Workout.started_at)
    stmt = (
        select(
            week_start_expr.label('week_start'),
            func.sum((ExerciseSet.weight * ExerciseSet.reps)).label('volume'),
        )
        .join(WorkoutExercise, WorkoutExercise.workout_id == Workout.id)
        .join(ExerciseSet, ExerciseSet.workout_exercise_id == WorkoutExercise.id)
        .where(Workout.user_id == current_user.id, ExerciseSet.weight.isnot(None))
        .group_by(week_start_expr)
        .order_by(week_start_expr.asc())
    )
    rows = db.execute(stmt).all()
    return [{'week_start': row.week_start, 'volume': float(row.volume or 0)} for row in rows]


@router.get('/bodyweight-trend')
def bodyweight_trend(days: int = 90, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    since = date.today() - timedelta(days=days)
    stmt = (
        select(BodyEntry.entry_date, BodyEntry.weight_kg)
        .where(BodyEntry.user_id == current_user.id, BodyEntry.entry_date >= since, BodyEntry.weight_kg.isnot(None))
        .order_by(BodyEntry.entry_date.asc())
    )
    rows = db.execute(stmt).all()
    return [{'date': row.entry_date, 'weight_kg': row.weight_kg} for row in rows]
