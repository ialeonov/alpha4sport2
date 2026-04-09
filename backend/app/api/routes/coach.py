from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.coach import CoachChatRequest, CoachChatResponse, CoachHistoryResponse
from app.services.coach_service import CoachService, CoachServiceError

router = APIRouter()


@router.get('/history', response_model=CoachHistoryResponse)
async def coach_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    messages = service.list_history(user_id=current_user.id)
    return {
        'messages': [
            {
                'id': item.id,
                'role': item.role,
                'content': item.content,
                'created_at': item.created_at.isoformat(),
            }
            for item in messages
        ]
    }


@router.post('/chat', response_model=CoachChatResponse)
async def coach_chat(
    payload: CoachChatRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    try:
        result = await service.reply(
            user=current_user,
            messages=[message.model_dump() for message in payload.messages],
        )
        latest_user_message = next(
            (message.content for message in reversed(payload.messages) if message.role == 'user'),
            None,
        )
        if latest_user_message:
            service.save_exchange(
                user_id=current_user.id,
                user_text=latest_user_message,
                assistant_text=result['reply'],
            )
        return result
    except CoachServiceError as exc:
        error_text = str(exc)
        status_code = status.HTTP_502_BAD_GATEWAY
        if 'не настроен' in error_text.lower():
            status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        raise HTTPException(status_code=status_code, detail=error_text) from exc
