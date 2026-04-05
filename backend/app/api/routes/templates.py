import secrets

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.models.workout import ExerciseCatalog, WorkoutTemplate, WorkoutTemplateExercise
from app.schemas.workout import TemplateCreate, TemplateOut, TemplateSharedOut

router = APIRouter()


def _hydrate_template(
    template: WorkoutTemplate,
    payload_exercises: list,
    db: Session,
    user_id: int,
) -> None:
    template.exercises.clear()
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

        template.exercises.append(
            WorkoutTemplateExercise(
                catalog_exercise_id=catalog_exercise.id if catalog_exercise else None,
                exercise_name=catalog_exercise.name if catalog_exercise else exercise_data.exercise_name,
                position=exercise_data.position,
                target_sets=exercise_data.target_sets,
                target_reps=exercise_data.target_reps,
                target_weight=exercise_data.target_weight,
            )
        )


@router.post('', response_model=TemplateOut)
def create_template(
    payload: TemplateCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    template = WorkoutTemplate(user_id=current_user.id, name=payload.name, notes=payload.notes)
    _hydrate_template(template, payload.exercises, db, current_user.id)
    db.add(template)
    db.commit()
    db.refresh(template)
    return template


@router.get('', response_model=list[TemplateOut])
def list_templates(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    stmt = (
        select(WorkoutTemplate)
        .where(WorkoutTemplate.user_id == current_user.id)
        .options(joinedload(WorkoutTemplate.exercises))
        .order_by(WorkoutTemplate.id.desc())
    )
    return list(db.scalars(stmt).unique())


@router.put('/{template_id}', response_model=TemplateOut)
def update_template(
    template_id: int,
    payload: TemplateCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    template = db.scalar(
        select(WorkoutTemplate).where(
            WorkoutTemplate.id == template_id,
            WorkoutTemplate.user_id == current_user.id,
        )
    )
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Template not found')

    template.name = payload.name
    template.notes = payload.notes
    _hydrate_template(template, payload.exercises, db, current_user.id)
    db.commit()
    db.refresh(template)
    return template


@router.delete('/{template_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_template(
    template_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    template = db.scalar(
        select(WorkoutTemplate).where(
            WorkoutTemplate.id == template_id,
            WorkoutTemplate.user_id == current_user.id,
        )
    )
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Template not found')

    db.delete(template)
    db.commit()
    return None


# ─── Sharing ──────────────────────────────────────────────────────────────────

@router.post('/{template_id}/share')
def share_template(
    template_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Generate a share token for the template. Idempotent — returns existing token if already shared."""
    template = db.scalar(
        select(WorkoutTemplate).where(
            WorkoutTemplate.id == template_id,
            WorkoutTemplate.user_id == current_user.id,
        )
    )
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Template not found')

    if template.share_token is None:
        template.share_token = secrets.token_urlsafe(16)
        db.commit()

    return {'share_token': template.share_token}


@router.delete('/{template_id}/share', status_code=status.HTTP_204_NO_CONTENT)
def revoke_template_share(
    template_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Revoke the share token, making the template private again."""
    template = db.scalar(
        select(WorkoutTemplate).where(
            WorkoutTemplate.id == template_id,
            WorkoutTemplate.user_id == current_user.id,
        )
    )
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Template not found')

    template.share_token = None
    db.commit()
    return None


@router.get('/shared/{token}', response_model=TemplateSharedOut)
def get_shared_template(
    token: str,
    db: Session = Depends(get_db),
):
    """Fetch a shared template by token. No authentication required."""
    template = db.scalar(
        select(WorkoutTemplate)
        .where(WorkoutTemplate.share_token == token)
        .options(joinedload(WorkoutTemplate.exercises))
    )
    if not template:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Template not found')

    return template


@router.post('/import/{token}', response_model=TemplateOut)
def import_shared_template(
    token: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Import a shared template into the current user's library."""
    source = db.scalar(
        select(WorkoutTemplate)
        .where(WorkoutTemplate.share_token == token)
        .options(joinedload(WorkoutTemplate.exercises))
    )
    if not source:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Template not found')

    new_template = WorkoutTemplate(
        user_id=current_user.id,
        name=source.name,
        notes=source.notes,
    )
    for src_ex in source.exercises:
        new_template.exercises.append(
            WorkoutTemplateExercise(
                catalog_exercise_id=None,
                exercise_name=src_ex.exercise_name,
                position=src_ex.position,
                target_sets=src_ex.target_sets,
                target_reps=src_ex.target_reps,
            )
        )

    db.add(new_template)
    db.commit()
    db.refresh(new_template)
    return new_template
