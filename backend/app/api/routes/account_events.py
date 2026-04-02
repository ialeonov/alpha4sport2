from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.account_event import AccountEvent
from app.models.user import User
from app.schemas.account import AccountEventOut
from app.services.account_event_service import AccountEventService

router = APIRouter()


@router.get('', response_model=list[AccountEventOut])
def list_account_events(
    limit: int = 40,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    limit = max(1, min(limit, 50))
    return AccountEventService(db).list_events(limit=limit, current_user_id=current_user.id)


@router.post('/{event_id}/like')
def toggle_event_like(
    event_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    event = db.get(AccountEvent, event_id)
    if event is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Событие не найдено.')
    return AccountEventService(db).toggle_like(user_id=current_user.id, event_id=event_id)
