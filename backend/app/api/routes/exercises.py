from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.models.workout import ExerciseCatalog, ExerciseSecondaryMuscle
from app.schemas.workout import ExerciseCatalogCreate, ExerciseCatalogOut, ExerciseCatalogUpdate
from app.services.exercise_catalog import (
    build_unique_slug,
    ensure_seed_catalog,
    list_catalog_exercises_stmt,
    serialize_exercise_catalog,
    validate_muscles,
)

router = APIRouter()


@router.get('', response_model=list[ExerciseCatalogOut])
def list_exercises(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    ensure_seed_catalog(db, current_user.id)
    exercises = list(db.scalars(list_catalog_exercises_stmt(current_user.id)))
    return [ExerciseCatalogOut(**serialize_exercise_catalog(exercise)) for exercise in exercises]


@router.post('', response_model=ExerciseCatalogOut)
def create_exercise(
    payload: ExerciseCatalogCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    normalized_name = payload.name.strip()
    if not normalized_name:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Название упражнения обязательно')

    duplicate = db.scalar(
        select(ExerciseCatalog).where(
            ExerciseCatalog.user_id == current_user.id,
            ExerciseCatalog.name == normalized_name,
        )
    )
    if duplicate:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Упражнение уже существует')

    primary_muscle = payload.primary_muscle.strip()
    try:
        secondary_clean = validate_muscles(primary_muscle, payload.secondary_muscles)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    exercise = ExerciseCatalog(
        user_id=current_user.id,
        slug=build_unique_slug(db, current_user.id, normalized_name),
        name=normalized_name,
        primary_muscle=primary_muscle,
        secondary_muscle_links=[
            ExerciseSecondaryMuscle(muscle=muscle, position=index + 1)
            for index, muscle in enumerate(secondary_clean)
        ],
    )
    db.add(exercise)
    db.commit()
    db.refresh(exercise)
    return ExerciseCatalogOut(**serialize_exercise_catalog(exercise))


@router.put('/{exercise_id}', response_model=ExerciseCatalogOut)
def update_exercise(
    exercise_id: int,
    payload: ExerciseCatalogUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    exercise = db.scalar(
        select(ExerciseCatalog).where(
            ExerciseCatalog.id == exercise_id,
            ExerciseCatalog.user_id == current_user.id,
        )
    )
    if not exercise:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Упражнение не найдено')

    normalized_name = payload.name.strip()
    if not normalized_name:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Название упражнения обязательно')

    duplicate = db.scalar(
        select(ExerciseCatalog).where(
            ExerciseCatalog.user_id == current_user.id,
            ExerciseCatalog.name == normalized_name,
            ExerciseCatalog.id != exercise_id,
        )
    )
    if duplicate:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Упражнение уже существует')

    primary_muscle = payload.primary_muscle.strip()
    try:
        secondary_clean = validate_muscles(primary_muscle, payload.secondary_muscles)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    exercise.name = normalized_name
    exercise.primary_muscle = primary_muscle
    exercise.secondary_muscle_links = [
        ExerciseSecondaryMuscle(muscle=muscle, position=index + 1)
        for index, muscle in enumerate(secondary_clean)
    ]
    db.commit()
    db.refresh(exercise)
    return ExerciseCatalogOut(**serialize_exercise_catalog(exercise))


@router.delete('/{exercise_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_exercise(
    exercise_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    exercise = db.scalar(
        select(ExerciseCatalog).where(
            ExerciseCatalog.id == exercise_id,
            ExerciseCatalog.user_id == current_user.id,
        )
    )
    if not exercise:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Упражнение не найдено')

    db.delete(exercise)
    db.commit()
    return None
