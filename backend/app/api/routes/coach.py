import json

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, require_owner_user
from app.db.session import get_db, SessionLocal
from app.models.user import User
from app.schemas.coach import (
    CoachChatRequest,
    CoachChatResponse,
    CoachHistoryResponse,
    CoachMemoryEntry,
    CoachMemoryResponse,
    CoachWorkoutGenerateRequest,
    CoachWorkoutGenerateResponse,
    DailyInsightResponse,
    AiUsageReport,
    OwnerCoachHistoryResponse,
    ProgressInsightsRequest,
    ProgressInsightsResponse,
)
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


@router.get('/owner/usage', response_model=AiUsageReport)
async def owner_ai_usage(
    days: int = 30,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_owner_user),
):
    return CoachService(db).usage_report(days=max(1, min(days, 365)))


@router.get('/owner/history', response_model=OwnerCoachHistoryResponse)
async def owner_coach_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_owner_user),
):
    service = CoachService(db)
    messages = service.list_all_history()
    return {
        'messages': [
            {
                'id': item['id'],
                'user_id': item['user_id'],
                'user_email': item['user_email'],
                'user_display_name': item['user_display_name'],
                'role': item['role'],
                'content': item['content'],
                'created_at': item['created_at'].isoformat(),
            }
            for item in messages
        ]
    }


@router.delete('/history', status_code=status.HTTP_204_NO_CONTENT)
async def clear_coach_history(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    service.clear_history(user_id=current_user.id)
    return None


@router.delete('/history/{message_id}', status_code=status.HTTP_204_NO_CONTENT)
async def delete_coach_history_message(
    message_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    deleted = service.delete_message(user_id=current_user.id, message_id=message_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Сообщение не найдено.',
        )
    return None


async def _run_memory_update(user_id: int, user_text: str, assistant_text: str) -> None:
    """Фоновое обновление памяти коуча — выполняется после ответа."""
    db = SessionLocal()
    try:
        service = CoachService(db)
        await service.update_memory_from_exchange(
            user_id=user_id,
            user_text=user_text,
            assistant_text=assistant_text,
        )
    finally:
        db.close()


@router.post('/chat', response_model=CoachChatResponse)
async def coach_chat(
    payload: CoachChatRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    try:
        result = await service.reply(
            user=current_user,
            messages=[message.model_dump() for message in payload.messages],
            wellness_entries=[e.model_dump() for e in payload.wellness_entries]
            if payload.wellness_entries
            else None,
        )
        latest_user_message = next(
            (message.content for message in reversed(payload.messages) if message.role == 'user'),
            None,
        )
        if payload.save_history and latest_user_message:
            service.save_exchange(
                user_id=current_user.id,
                user_text=latest_user_message,
                assistant_text=result['reply'],
            )
            background_tasks.add_task(
                _run_memory_update,
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


@router.post('/chat/stream')
async def coach_chat_stream(
    payload: CoachChatRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    latest_user_message = next(
        (m.content for m in reversed(payload.messages) if m.role == 'user'),
        None,
    )
    messages = [m.model_dump() for m in payload.messages]
    wellness_entries = [e.model_dump() for e in payload.wellness_entries] if payload.wellness_entries else None
    user_id = current_user.id

    async def generate():
        full_reply = ''
        try:
            async for chunk in service.reply_stream(
                user=current_user,
                messages=messages,
                wellness_entries=wellness_entries,
            ):
                full_reply += chunk
                yield f"data: {json.dumps({'chunk': chunk}, ensure_ascii=False)}\n\n"
        except CoachServiceError as exc:
            yield f"data: {json.dumps({'error': str(exc)}, ensure_ascii=False)}\n\n"
            return

        if payload.save_history and latest_user_message and full_reply:
            service.save_exchange(
                user_id=user_id,
                user_text=latest_user_message,
                assistant_text=full_reply,
            )
            background_tasks.add_task(
                _run_memory_update,
                user_id=user_id,
                user_text=latest_user_message,
                assistant_text=full_reply,
            )
        yield f"data: {json.dumps({'done': True})}\n\n"

    return StreamingResponse(
        generate(),
        media_type='text/event-stream',
        headers={
            'Cache-Control': 'no-cache',
            'X-Accel-Buffering': 'no',
            'Connection': 'keep-alive',
        },
    )


@router.post('/progress-insights', response_model=ProgressInsightsResponse)
async def progress_insights(
    payload: ProgressInsightsRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    try:
        result = await service.generate_progress_insights(
            exercises=[ex.model_dump() for ex in payload.exercises],
            user_id=current_user.id,
        )
        return result
    except CoachServiceError as exc:
        error_text = str(exc)
        status_code = status.HTTP_502_BAD_GATEWAY
        if 'не настроен' in error_text.lower():
            status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        raise HTTPException(status_code=status_code, detail=error_text) from exc


@router.post('/generate-workout', response_model=CoachWorkoutGenerateResponse)
async def generate_coach_workout(
    payload: CoachWorkoutGenerateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    try:
        return await service.generate_workout(
            user=current_user,
            intensity_title=payload.intensity_title,
            min_exercises=payload.min_exercises,
            max_exercises=payload.max_exercises,
            user_notes=payload.user_notes,
            wellness_entries=[e.model_dump() for e in payload.wellness_entries]
            if payload.wellness_entries
            else None,
        )
    except CoachServiceError as exc:
        error_text = str(exc)
        status_code = status.HTTP_502_BAD_GATEWAY
        if 'не настроен' in error_text.lower():
            status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        raise HTTPException(status_code=status_code, detail=error_text) from exc


@router.get('/daily-insight', response_model=DailyInsightResponse)
async def daily_insight(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    try:
        return await service.generate_daily_insight(user=current_user)
    except CoachServiceError as exc:
        error_text = str(exc)
        status_code = status.HTTP_502_BAD_GATEWAY
        if 'не настроен' in error_text.lower():
            status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        raise HTTPException(status_code=status_code, detail=error_text) from exc


@router.get('/memory', response_model=CoachMemoryResponse)
async def get_coach_memory(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    entries = service.list_memory(user_id=current_user.id)
    return {
        'entries': [
            {
                'id': e.id,
                'key': e.key,
                'value': e.value,
                'confidence': e.confidence,
                'source': e.source,
                'updated_at': e.updated_at.isoformat(),
            }
            for e in entries
        ]
    }


@router.delete('/memory', status_code=status.HTTP_204_NO_CONTENT)
async def clear_coach_memory(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    service.clear_memory(user_id=current_user.id)
    return None


@router.delete('/memory/{memory_id}', status_code=status.HTTP_204_NO_CONTENT)
async def delete_coach_memory_entry(
    memory_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    service = CoachService(db)
    deleted = service.delete_memory_entry(user_id=current_user.id, memory_id=memory_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Запись не найдена.')
    return None
