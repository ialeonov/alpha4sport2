from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.config import settings
from app.db.session import get_db
from app.models.user import User
from app.schemas.account import PublicUserSummary, UpdateDisplayNameRequest
from app.schemas.auth import UserOut
from app.services.account_event_service import AccountEventService, avatar_url_for_user, display_name_for_user

router = APIRouter()

_ALLOWED_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp'}
_MAX_AVATAR_SIZE_BYTES = 5 * 1024 * 1024


@router.get('', response_model=list[PublicUserSummary])
def list_users(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    del current_user
    return AccountEventService(db).list_users()


@router.post('/me/avatar', response_model=UserOut)
async def upload_avatar(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    extension = Path(file.filename or '').suffix.lower()
    if extension not in _ALLOWED_EXTENSIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Поддерживаются только jpg, jpeg, png и webp.',
        )

    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Файл пустой.')
    if len(content) > _MAX_AVATAR_SIZE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Размер аватара не должен превышать 5 МБ.',
        )

    avatars_dir = Path(settings.upload_dir) / 'avatars'
    avatars_dir.mkdir(parents=True, exist_ok=True)
    file_name = f'{current_user.id}_{uuid4().hex}{extension}'
    target_path = avatars_dir / file_name
    target_path.write_bytes(content)

    current_user.avatar_path = f'avatars/{file_name}'
    db.commit()
    db.refresh(current_user)
    return {
        'id': current_user.id,
        'email': current_user.email,
        'display_name': display_name_for_user(current_user),
        'avatar_url': avatar_url_for_user(current_user),
    }


@router.patch('/me', response_model=UserOut)
def update_profile(
    payload: UpdateDisplayNameRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    normalized_name = ' '.join(payload.displayName.strip().split())
    if len(normalized_name) < 2:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Имя должно содержать минимум 2 символа.',
        )

    current_user.display_name = normalized_name
    db.commit()
    db.refresh(current_user)
    return {
        'id': current_user.id,
        'email': current_user.email,
        'display_name': display_name_for_user(current_user),
        'avatar_url': avatar_url_for_user(current_user),
    }
