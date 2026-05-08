from fastapi import APIRouter, Depends, status
from sqlalchemy import desc, select, update
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_owner_user
from app.db.session import get_db
from app.models.announcement import Announcement
from app.models.user import User
from app.schemas.announcement import (
    AnnouncementEnvelope,
    AnnouncementOut,
    AnnouncementUpsertRequest,
)

router = APIRouter()


def _serialize_announcement(item: Announcement) -> AnnouncementOut:
    return AnnouncementOut(
        id=item.id,
        title=item.title,
        body=item.body,
        is_active=item.is_active,
        created_by_user_id=item.created_by_user_id,
        created_at=item.created_at.isoformat(),
        updated_at=item.updated_at.isoformat(),
    )


@router.get('/active', response_model=AnnouncementEnvelope)
def get_active_announcement(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    del current_user
    announcement = db.scalar(
        select(Announcement)
        .where(Announcement.is_active.is_(True))
        .order_by(desc(Announcement.updated_at), desc(Announcement.id))
        .limit(1)
    )
    return {
        'announcement': _serialize_announcement(announcement)
        if announcement
        else None,
    }


@router.get('/admin/current', response_model=AnnouncementEnvelope)
def get_admin_current_announcement(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_owner_user),
):
    del current_user
    announcement = db.scalar(
        select(Announcement)
        .order_by(desc(Announcement.updated_at), desc(Announcement.id))
        .limit(1)
    )
    return {
        'announcement': _serialize_announcement(announcement)
        if announcement
        else None,
    }


@router.post('/admin/current', response_model=AnnouncementOut)
def upsert_current_announcement(
    payload: AnnouncementUpsertRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_owner_user),
):
    title = ' '.join(payload.title.strip().split())
    body = payload.body.strip()

    db.execute(
        update(Announcement)
        .where(Announcement.is_active.is_(True))
        .values(is_active=False)
    )

    announcement = Announcement(
        title=title,
        body=body,
        is_active=True,
        created_by_user_id=current_user.id,
    )
    db.add(announcement)
    db.commit()
    db.refresh(announcement)
    return _serialize_announcement(announcement)


@router.delete('/admin/current', status_code=status.HTTP_204_NO_CONTENT)
def deactivate_current_announcement(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_owner_user),
):
    del current_user
    announcement = db.scalar(
        select(Announcement)
        .where(Announcement.is_active.is_(True))
        .order_by(desc(Announcement.updated_at), desc(Announcement.id))
        .limit(1)
    )
    if announcement:
        announcement.is_active = False
        db.commit()
    return None
