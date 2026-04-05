from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete as sa_delete, func, select
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.account_event import AccountEvent
from app.models.user import User
from app.models.workout import ExerciseCatalog, ExerciseSet, Workout, WorkoutExercise, WorkoutTemplate
from app.schemas.workout import WorkoutCreate, WorkoutOut, WorkoutUpdate
from app.services.account_event_service import AccountEventService
from app.services.progression_service import ProgressionService

router = APIRouter()


def _normalize_exercise_name(value: str) -> str:
    return value.strip().lower().replace('ё', 'е')


def _normalized_exercise_name_expr():
    return func.replace(func.lower(WorkoutExercise.exercise_name), 'ё', 'е')


def _hydrate_exercises(workout: Workout, payload_exercises: list, db: Session, user_id: int) -> None:
    workout.exercises.clear()
    for exercise_data in payload_exercises:
        catalog_exercise = None
        if exercise_data.catalog_exercise_id is not None:
            catalog_exercise = db.scalar(
                select(ExerciseCatalog).where(
                    ExerciseCatalog.id == exercise_data.catalog_exercise_id,
                    ExerciseCatalog.user_id == user_id,
                )
            )
            if not catalog_exercise:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f'Catalog exercise {exercise_data.catalog_exercise_id} not found',
                )

        exercise = WorkoutExercise(
            catalog_exercise_id=catalog_exercise.id if catalog_exercise else None,
            exercise_name=catalog_exercise.name if catalog_exercise else exercise_data.exercise_name,
            position=exercise_data.position,
            notes=exercise_data.notes,
        )
        exercise.sets = [
            ExerciseSet(
                position=set_data.position,
                reps=set_data.reps,
                weight=set_data.weight,
                rpe=set_data.rpe,
                notes=set_data.notes,
            )
            for set_data in exercise_data.sets
        ]
        workout.exercises.append(exercise)


@router.post('', response_model=WorkoutOut)
def create_workout(
    payload: WorkoutCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    workout = Workout(
        user_id=current_user.id,
        name=payload.name,
        notes=payload.notes,
        started_at=payload.started_at,
        finished_at=payload.finished_at,
    )
    _hydrate_exercises(workout, payload.exercises, db, current_user.id)
    db.add(workout)
    db.commit()
    db.refresh(workout)
    if workout.finished_at is not None:
        AccountEventService(db).log_once(
            user_id=current_user.id,
            event_key=f'workout_completed:{workout.id}',
            event_type='workout_completed',
            description=f'Завершил тренировку "{workout.name}".',
            created_at=datetime.now(timezone.utc),
        )
        db.commit()
    ProgressionService(db).recalculate_for_user(current_user.id)
    return workout


@router.get('', response_model=list[WorkoutOut])
def list_workouts(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    stmt = (
        select(Workout)
        .where(Workout.user_id == current_user.id)
        .options(joinedload(Workout.exercises).joinedload(WorkoutExercise.sets))
        .order_by(Workout.started_at.desc())
    )
    return list(db.scalars(stmt).unique())


@router.post('/from-template/{template_id}', response_model=WorkoutOut)
def start_from_template(
    template_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    template = db.scalar(
        select(WorkoutTemplate)
        .where(WorkoutTemplate.id == template_id, WorkoutTemplate.user_id == current_user.id)
        .options(joinedload(WorkoutTemplate.exercises))
    )
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Template not found')

    workout = Workout(
        user_id=current_user.id,
        name=template.name,
        notes=template.notes,
        started_at=datetime.now(timezone.utc),
        finished_at=None,
    )
    for tpl_exercise in template.exercises:
        sets_count = max(tpl_exercise.target_sets, 1)
        workout.exercises.append(
            WorkoutExercise(
                catalog_exercise_id=tpl_exercise.catalog_exercise_id,
                exercise_name=tpl_exercise.exercise_name,
                position=tpl_exercise.position,
                notes=None,
                sets=[
                    ExerciseSet(
                        position=i + 1,
                        reps=0,
                        weight=tpl_exercise.target_weight,
                        rpe=None,
                        notes=None,
                    )
                    for i in range(sets_count)
                ],
            )
        )

    db.add(workout)
    db.commit()
    db.refresh(workout)
    if workout.finished_at is not None:
        AccountEventService(db).log_once(
            user_id=current_user.id,
            event_key=f'workout_completed:{workout.id}',
            event_type='workout_completed',
            description=f'Завершил тренировку "{workout.name}".',
            created_at=workout.finished_at,
        )
        db.commit()
    ProgressionService(db).recalculate_for_user(current_user.id)
    return workout


@router.get('/previous/{exercise_name}')
def previous_exercise_values(
    exercise_name: str,
    limit: int = 5,
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
            _normalized_exercise_name_expr() == normalized_name,
        )
        .order_by(Workout.started_at.desc(), ExerciseSet.position.desc())
        .limit(limit)
    )
    rows = db.execute(stmt).all()
    return [{'date': row.started_at, 'weight': row.weight, 'reps': row.reps} for row in rows]


@router.get('/{workout_id}', response_model=WorkoutOut)
def get_workout(workout_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    stmt = (
        select(Workout)
        .where(Workout.id == workout_id, Workout.user_id == current_user.id)
        .options(joinedload(Workout.exercises).joinedload(WorkoutExercise.sets))
    )
    workout = db.scalar(stmt)
    if not workout:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Workout not found')
    return workout


@router.put('/{workout_id}', response_model=WorkoutOut)
def update_workout(
    workout_id: int,
    payload: WorkoutUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    workout = db.scalar(select(Workout).where(Workout.id == workout_id, Workout.user_id == current_user.id))
    if not workout:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Workout not found')

    workout.name = payload.name
    workout.notes = payload.notes
    workout.started_at = payload.started_at
    workout.finished_at = payload.finished_at
    _hydrate_exercises(workout, payload.exercises, db, current_user.id)
    db.commit()
    db.refresh(workout)
    if workout.finished_at is not None:
        AccountEventService(db).log_once(
            user_id=current_user.id,
            event_key=f'workout_completed:{workout.id}',
            event_type='workout_completed',
            description=f'Завершил тренировку "{workout.name}".',
            created_at=datetime.now(timezone.utc),
        )
        db.commit()
    ProgressionService(db).recalculate_for_user(current_user.id)
    return workout


@router.delete('/{workout_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_workout(workout_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    workout = db.scalar(select(Workout).where(Workout.id == workout_id, Workout.user_id == current_user.id))
    if not workout:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Workout not found')
    user_id = workout.user_id
    # Удаляем события, связанные с этой тренировкой
    db.execute(
        sa_delete(AccountEvent).where(
            (AccountEvent.event_key == f'workout_completed:{workout_id}') |
            AccountEvent.event_key.like(f'record:{workout_id}:%')
        )
    )
    db.delete(workout)
    db.commit()
    ProgressionService(db).recalculate_for_user(user_id)
    return None
