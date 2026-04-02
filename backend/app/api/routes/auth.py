from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.security import create_access_token, get_password_hash, verify_password
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import RegisterRequest, Token, UserOut
from app.services.account_event_service import (
    AccountEventService,
    avatar_url_for_user,
    display_name_for_user,
)
from app.services.exercise_catalog import ensure_seed_catalog

router = APIRouter()


@router.post('/login', response_model=Token)
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == form_data.username))
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Incorrect email or password')

    token = create_access_token(subject=str(user.id))
    return Token(access_token=token)


@router.post('/register', response_model=Token, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    email = payload.email.lower()
    existing = db.scalar(select(User).where(User.email == email))
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='User already exists')

    user = User(email=email, hashed_password=get_password_hash(payload.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    ensure_seed_catalog(db, user.id)
    AccountEventService(db).log_once(
        user_id=user.id,
        event_key=f'user_registered:{user.id}',
        event_type='registration',
        description='Создал аккаунт.',
        created_at=user.created_at,
    )
    db.commit()

    token = create_access_token(subject=str(user.id))
    return Token(access_token=token)


@router.post('/bootstrap', response_model=UserOut)
def bootstrap_user(email: str, password: str, db: Session = Depends(get_db)):
    existing = db.scalar(select(User).where(User.email == email))
    if existing:
        ensure_seed_catalog(db, existing.id)
        return {
            'id': existing.id,
            'email': existing.email,
            'display_name': display_name_for_user(existing),
            'avatar_url': avatar_url_for_user(existing),
        }

    user = User(email=email, hashed_password=get_password_hash(password))
    db.add(user)
    db.commit()
    db.refresh(user)
    ensure_seed_catalog(db, user.id)
    AccountEventService(db).log_once(
        user_id=user.id,
        event_key=f'user_registered:{user.id}',
        event_type='registration',
        description='Создал аккаунт.',
        created_at=user.created_at,
    )
    db.commit()
    return {
        'id': user.id,
        'email': user.email,
        'display_name': display_name_for_user(user),
        'avatar_url': avatar_url_for_user(user),
    }


@router.get('/me', response_model=UserOut)
def me(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    ensure_seed_catalog(db, current_user.id)
    return {
        'id': current_user.id,
        'email': current_user.email,
        'display_name': display_name_for_user(current_user),
        'avatar_url': avatar_url_for_user(current_user),
    }
