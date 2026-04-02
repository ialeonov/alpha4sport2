from fastapi import APIRouter

from app.api.routes import account_events, auth, body, exercises, export, progress, progression, templates, users, workouts

api_router = APIRouter()
api_router.include_router(auth.router, prefix='/auth', tags=['auth'])
api_router.include_router(workouts.router, prefix='/workouts', tags=['workouts'])
api_router.include_router(templates.router, prefix='/templates', tags=['templates'])
api_router.include_router(exercises.router, prefix='/exercises', tags=['exercises'])
api_router.include_router(body.router, prefix='/body', tags=['body'])
api_router.include_router(progress.router, prefix='/progress', tags=['progress'])
api_router.include_router(progression.router, prefix='/progression', tags=['progression'])
api_router.include_router(users.router, prefix='/users', tags=['users'])
api_router.include_router(account_events.router, prefix='/account-events', tags=['account-events'])
api_router.include_router(export.router, prefix='/export', tags=['export'])
