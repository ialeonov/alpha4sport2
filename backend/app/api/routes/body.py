from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.body import BodyEntry
from app.models.user import User
from app.schemas.body import BodyEntryCreate, BodyEntryOut

router = APIRouter()


@router.post('', response_model=BodyEntryOut)
def create_body_entry(
    payload: BodyEntryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    entry = BodyEntry(user_id=current_user.id, **payload.model_dump())
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.get('', response_model=list[BodyEntryOut])
def list_body_entries(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    stmt = select(BodyEntry).where(BodyEntry.user_id == current_user.id).order_by(BodyEntry.entry_date.desc())
    return list(db.scalars(stmt))


@router.delete('/{entry_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_body_entry(entry_id: int, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    entry = db.scalar(select(BodyEntry).where(BodyEntry.id == entry_id, BodyEntry.user_id == current_user.id))
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Body entry not found')
    db.delete(entry)
    db.commit()
    return None
