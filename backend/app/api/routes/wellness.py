from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.models.wellness import WellnessEntry
from app.schemas.wellness import WellnessEntryOut, WellnessEntryUpsert

router = APIRouter()


@router.get('', response_model=list[WellnessEntryOut])
def list_wellness_entries(
    start: date | None = None,
    end: date | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if start is None and end is None:
        end = date.today()
        start = end - timedelta(days=30)
    elif start is None:
        start = end
    elif end is None:
        end = start

    if start > end:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Start date must be before or equal to end date',
        )

    stmt = (
        select(WellnessEntry)
        .where(
            WellnessEntry.user_id == current_user.id,
            WellnessEntry.entry_date >= start,
            WellnessEntry.entry_date <= end,
        )
        .order_by(WellnessEntry.entry_date.desc())
    )
    return list(db.scalars(stmt))


@router.get('/{entry_date}', response_model=WellnessEntryOut)
def get_wellness_entry(
    entry_date: date,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    entry = db.scalar(
        select(WellnessEntry).where(
            WellnessEntry.user_id == current_user.id,
            WellnessEntry.entry_date == entry_date,
        )
    )
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Wellness entry not found')
    return entry


@router.put('/{entry_date}', response_model=WellnessEntryOut)
def upsert_wellness_entry(
    entry_date: date,
    payload: WellnessEntryUpsert,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    entry = db.scalar(
        select(WellnessEntry).where(
            WellnessEntry.user_id == current_user.id,
            WellnessEntry.entry_date == entry_date,
        )
    )
    if entry is None:
        entry = WellnessEntry(
            user_id=current_user.id,
            entry_date=entry_date,
            **payload.model_dump(),
        )
        db.add(entry)
    else:
        for key, value in payload.model_dump().items():
            setattr(entry, key, value)

    db.commit()
    db.refresh(entry)
    return entry


@router.delete('/{entry_date}', status_code=status.HTTP_204_NO_CONTENT)
def delete_wellness_entry(
    entry_date: date,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    entry = db.scalar(
        select(WellnessEntry).where(
            WellnessEntry.user_id == current_user.id,
            WellnessEntry.entry_date == entry_date,
        )
    )
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Wellness entry not found')
    db.delete(entry)
    db.commit()
    return None
