from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.body import BodyEntry
from app.models.user import User
from app.models.workout import Workout, WorkoutExercise

router = APIRouter()


@router.get('/json')
def export_json(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    workouts = list(
        db.scalars(
            select(Workout)
            .where(Workout.user_id == current_user.id)
            .options(joinedload(Workout.exercises).joinedload(WorkoutExercise.sets))
            .order_by(Workout.started_at.asc())
        ).unique()
    )
    body_entries = list(
        db.scalars(select(BodyEntry).where(BodyEntry.user_id == current_user.id).order_by(BodyEntry.entry_date.asc()))
    )

    return {
        'exported_at': date.today().isoformat(),
        'workouts': [
            {
                'id': w.id,
                'name': w.name,
                'notes': w.notes,
                'started_at': w.started_at,
                'finished_at': w.finished_at,
                'exercises': [
                    {
                        'exercise_name': ex.exercise_name,
                        'position': ex.position,
                        'notes': ex.notes,
                        'sets': [
                            {
                                'position': s.position,
                                'reps': s.reps,
                                'weight': s.weight,
                                'rpe': s.rpe,
                                'notes': s.notes,
                            }
                            for s in ex.sets
                        ],
                    }
                    for ex in w.exercises
                ],
            }
            for w in workouts
        ],
        'body_entries': [
            {
                'entry_date': be.entry_date,
                'weight_kg': be.weight_kg,
                'waist_cm': be.waist_cm,
                'chest_cm': be.chest_cm,
                'hips_cm': be.hips_cm,
                'notes': be.notes,
                'photo_path': be.photo_path,
            }
            for be in body_entries
        ],
    }
