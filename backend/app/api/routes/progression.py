from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.account_event import AccountEvent
from app.models.event_like import EventLike
from app.models.user import User
from app.schemas.progression import ProgressionProfileResponse, SickLeaveCreate
from app.services.progression_service import ProgressionService

router = APIRouter()


def _count_likes_received(db: Session, user_id: int) -> int:
    return db.scalar(
        select(func.count(EventLike.id))
        .join(AccountEvent, EventLike.event_id == AccountEvent.id)
        .where(AccountEvent.user_id == user_id)
    ) or 0


def _inject_likes(data: dict, db: Session, user_id: int) -> dict:
    data['profile']['totalLikesReceived'] = _count_likes_received(db, user_id)
    return data


@router.get('/profile', response_model=ProgressionProfileResponse)
def get_progression_profile(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    data = ProgressionService(db).get_profile(current_user.id)
    return _inject_likes(data, db, current_user.id)


@router.get('/profile/{user_id}', response_model=ProgressionProfileResponse)
def get_public_progression_profile(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    del current_user
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Пользователь не найден.',
        )
    data = ProgressionService(db).get_profile(user_id)
    return _inject_likes(data, db, user_id)


@router.post('/sick-leaves', response_model=ProgressionProfileResponse)
def create_sick_leave(
    payload: SickLeaveCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        return ProgressionService(db).create_sick_leave(
            user_id=current_user.id,
            start_date=payload.startDate,
            end_date=payload.endDate,
            reason=payload.reason,
        )
    except ValueError as error:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(error)) from error


@router.post('/sick-leaves/{sick_leave_id}/cancel', response_model=ProgressionProfileResponse)
def cancel_sick_leave(
    sick_leave_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    try:
        return ProgressionService(db).cancel_sick_leave(
            user_id=current_user.id,
            sick_leave_id=sick_leave_id,
        )
    except ValueError as error:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(error)) from error
