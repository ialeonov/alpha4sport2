from __future__ import annotations

import json
from collections import Counter
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

import httpx
from sqlalchemy import delete, func, select, text
from sqlalchemy.orm import Session, joinedload

from app.core.config import settings
from app.models.body import BodyEntry
from app.models.coach import CoachChatMessage
from app.models.user import User
from app.models.workout import ExerciseCatalog, ExerciseSet, Workout, WorkoutExercise
from app.services.account_event_service import display_name_for_user


class CoachServiceError(Exception):
    pass


_APP_DISPLAY_NAME = 'Путь Силы'
_APP_TIMEZONE = ZoneInfo('Europe/Moscow')


class CoachService:
    _history_limit = 40

    def __init__(self, db: Session):
        self.db = db

    async def reply(self, *, user: User, messages: list[dict[str, str]]) -> dict:
        if not settings.ai_coach_api_key or not settings.ai_coach_model:
            raise CoachServiceError('AI-коуч не настроен на сервере.')

        context_summary = self._build_context_summary(user)
        payload = {
            'model': settings.ai_coach_model,
            'messages': self._build_llm_messages(context_summary, messages),
            'temperature': settings.ai_coach_temperature,
        }

        headers = {
            'Authorization': f'Bearer {settings.ai_coach_api_key}',
            'Content-Type': 'application/json',
        }
        if settings.ai_coach_referer:
            headers['HTTP-Referer'] = settings.ai_coach_referer
        if settings.ai_coach_title:
            headers['X-Title'] = settings.ai_coach_title

        endpoint = f'{settings.ai_coach_base_url.rstrip("/")}/chat/completions'
        timeout = httpx.Timeout(settings.ai_coach_timeout_seconds)

        try:
            async with httpx.AsyncClient(timeout=timeout) as client:
                response = await client.post(endpoint, headers=headers, json=payload)
                response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text.strip()
            raise CoachServiceError(
                f'LLM провайдер вернул ошибку {exc.response.status_code}: {detail or "пустой ответ"}'
            ) from exc
        except httpx.HTTPError as exc:
            raise CoachServiceError('Не удалось связаться с LLM провайдером.') from exc

        data = response.json()
        content = data.get('choices', [{}])[0].get('message', {}).get('content', '').strip()
        if not content:
            raise CoachServiceError('LLM провайдер вернул пустой ответ.')

        return {
            'reply': content,
            'model': data.get('model') or settings.ai_coach_model,
            'context_summary': context_summary,
        }

    def list_history(self, *, user_id: int, limit: int = 30) -> list[CoachChatMessage]:
        normalized_limit = max(1, min(limit, self._history_limit))
        messages = list(
            self.db.scalars(
                select(CoachChatMessage)
                .where(CoachChatMessage.user_id == user_id)
                .order_by(CoachChatMessage.created_at.desc(), CoachChatMessage.id.desc())
                .limit(normalized_limit)
            )
        )
        messages.reverse()
        return messages

    def save_exchange(self, *, user_id: int, user_text: str, assistant_text: str) -> None:
        now = datetime.now(timezone.utc)
        self.db.add_all(
            [
                CoachChatMessage(user_id=user_id, role='user', content=user_text, created_at=now),
                CoachChatMessage(user_id=user_id, role='assistant', content=assistant_text, created_at=now),
            ]
        )
        self.db.flush()
        self._trim_history(user_id=user_id)
        self.db.commit()

    def delete_message(self, *, user_id: int, message_id: int) -> bool:
        message = self.db.scalar(
            select(CoachChatMessage).where(
                CoachChatMessage.id == message_id,
                CoachChatMessage.user_id == user_id,
            )
        )
        if message is None:
            return False
        self.db.delete(message)
        self.db.commit()
        return True

    def _build_llm_messages(self, context_summary: dict, messages: list[dict[str, str]]) -> list[dict[str, str]]:
        today = datetime.now(_APP_TIMEZONE).date()
        system_prompt = settings.ai_coach_system_prompt.strip() or (
            f'Ты персональный фитнес-коуч внутри приложения "{_APP_DISPLAY_NAME}". '
            'Отвечай на русском языке, дружелюбно и конкретно. '
            'Опирайся только на предоставленную статистику пользователя. '
            'Если данных недостаточно, прямо скажи об этом. '
            'Не выдумывай медицинские диагнозы и не заменяй врача. '
            'Давай практические рекомендации по тренировкам, восстановлению и нагрузке. '
            'Для рекомендаций по упражнениям используй прежде всего упражнения из персонального каталога пользователя '
            'и из его недавних тренировок. Не предлагай упражнения, которых нет в его доступном списке, '
            'если только пользователь прямо не просит альтернативу. '
            'При анализе опирайся на: частоту тренировок, распределение мышечных групп (поле primaryMuscle), '
            'muscleDistribution (когда последний раз тренировалась каждая мышца), состав упражнений, '
            'число рабочих подходов, длительность тренировок (durationMinutes) и восстановление. '
            'Тоннаж — вторичный и шумный показатель, особенно для жима ногами и подобных движений. '
            'Не делай по тоннажу главный вывод о качестве тренировки. '
            'RPE (Rate of Perceived Exertion) в подходах — сигнал интенсивности: '
            'RPE 7 — умеренно, RPE 8-9 — тяжело, RPE 10 — до отказа. '
            'Учитывай RPE при оценке усталости и восстановления. '
            'Формат ответа: отвечай кратко если вопрос простой. '
            'Используй списки только когда перечисляешь конкретные рекомендации или упражнения. '
            'Не переспрашивай и не уточняй — давай лучший ответ на основе имеющихся данных.'
        )
        runtime_prompt = (
            f'Текущее приложение: "{_APP_DISPLAY_NAME}". '
            f'Сегодняшняя дата: {today.isoformat()} '
            f'(формат дд.мм.гггг: {today.day:02d}.{today.month:02d}.{today.year}). '
            'Если пользователь спрашивает про сегодня, завтра, вчера, текущую неделю или текущий месяц, '
            'ориентируйся именно на эту дату и не используй другую. '
            'Если пользователь прямо спрашивает, кто создал приложение или кто тебя сделал, '
            'отвечай кратко: "Иван Леонов". '
            'Не упоминай создателя самостоятельно, если об этом не спрашивали.'
        )
        context_prompt = (
            'Ниже краткий профиль и сводка по пользователю. '
            'Используй это как источник контекста для ответа.\n'
            f'{json.dumps(context_summary, ensure_ascii=False)}'
        )
        return [
            {'role': 'system', 'content': system_prompt},
            {'role': 'system', 'content': runtime_prompt},
            {'role': 'system', 'content': context_prompt},
            *messages,
        ]

    def _build_context_summary(self, user: User) -> dict:
        today = datetime.now(_APP_TIMEZONE).date()
        body_entries = list(
            self.db.scalars(
                select(BodyEntry)
                .where(BodyEntry.user_id == user.id)
                .order_by(BodyEntry.entry_date.desc())
                .limit(8)
            )
        )
        recent_workouts = list(
            self.db.scalars(
                select(Workout)
                .where(Workout.user_id == user.id)
                .options(joinedload(Workout.exercises).joinedload(WorkoutExercise.sets))
                .order_by(Workout.started_at.desc(), Workout.id.desc())
                .limit(12)
            ).unique()
        )
        catalog_exercises = list(
            self.db.scalars(
                select(ExerciseCatalog)
                .where(ExerciseCatalog.user_id == user.id)
                .order_by(ExerciseCatalog.name.asc())
            )
        )
        # Lookup: catalog_exercise_id → primary_muscle (and by name for fallback)
        muscle_map: dict[int, str] = {ex.id: ex.primary_muscle for ex in catalog_exercises}
        muscle_map_by_name: dict[str, str] = {ex.name: ex.primary_muscle for ex in catalog_exercises}

        workout_count_total = self.db.scalar(
            select(func.count()).select_from(Workout).where(Workout.user_id == user.id)
        ) or 0
        recent_workout_count = self.db.scalar(
            select(func.count())
            .select_from(Workout)
            .where(
                Workout.user_id == user.id,
                Workout.started_at >= datetime.combine(today - timedelta(days=30), time.min, tzinfo=timezone.utc),
            )
        ) or 0

        week_start_expr = func.date_trunc(text("'week'"), Workout.started_at)
        volume_rows = self.db.execute(
            select(
                week_start_expr.label('week_start'),
                func.sum(ExerciseSet.weight * ExerciseSet.reps).label('volume'),
            )
            .join(WorkoutExercise, WorkoutExercise.workout_id == Workout.id)
            .join(ExerciseSet, ExerciseSet.workout_exercise_id == WorkoutExercise.id)
            .where(
                Workout.user_id == user.id,
                Workout.started_at >= datetime.combine(today - timedelta(days=42), time.min, tzinfo=timezone.utc),
                ExerciseSet.weight.isnot(None),
            )
            .group_by(week_start_expr)
            .order_by(week_start_expr.desc())
            .limit(6)
        ).all()

        top_exercises = Counter()
        workouts_summary = []
        for workout in recent_workouts:
            total_sets = 0
            total_volume = 0.0
            exercises_summary = []
            for exercise in workout.exercises:
                top_exercises[exercise.exercise_name] += 1
                exercise_volume = 0.0
                sets_compact = []
                for set_item in exercise.sets:
                    if set_item.reps > 0:
                        total_sets += 1
                    if set_item.weight is not None:
                        set_vol = float(set_item.weight) * set_item.reps
                        total_volume += set_vol
                        exercise_volume += set_vol
                    parts = []
                    if set_item.weight is not None:
                        parts.append(f'{set_item.weight:g}kg')
                    parts.append(f'{set_item.reps}r')
                    if set_item.rpe is not None:
                        parts.append(f'@{set_item.rpe:g}')
                    note = _trim_text(set_item.notes, 60)
                    if note:
                        parts.append(f'[{note}]')
                    sets_compact.append('×'.join(parts))

                primary_muscle = (
                    muscle_map.get(exercise.catalog_exercise_id)
                    or muscle_map_by_name.get(exercise.exercise_name)
                )
                ex_entry: dict = {
                    'name': exercise.exercise_name,
                    'sets': ' / '.join(sets_compact),
                }
                if primary_muscle:
                    ex_entry['muscle'] = primary_muscle
                if exercise_volume:
                    ex_entry['vol'] = round(exercise_volume, 1)
                note = _trim_text(exercise.notes, 200)
                if note:
                    ex_entry['notes'] = note
                exercises_summary.append(ex_entry)

            duration_minutes = None
            if workout.started_at and workout.finished_at:
                duration_minutes = round(
                    (workout.finished_at - workout.started_at).total_seconds() / 60
                )
            w_entry: dict = {
                'date': workout.started_at.date().isoformat() if workout.started_at else None,
                'name': workout.name,
                'exercises': exercises_summary,
            }
            if duration_minutes is not None:
                w_entry['durationMin'] = duration_minutes
            if total_sets:
                w_entry['totalSets'] = total_sets
            if total_volume:
                w_entry['totalVol'] = round(total_volume, 1)
            note = _trim_text(workout.notes, 240)
            if note:
                w_entry['notes'] = note
            workouts_summary.append(w_entry)

        # Muscle group distribution from recent workouts
        muscle_last_date: dict[str, str] = {}
        muscle_recent_sets: Counter = Counter()
        for workout in recent_workouts:
            workout_date = workout.started_at.date().isoformat() if workout.started_at else None
            for exercise in workout.exercises:
                muscle = (
                    muscle_map.get(exercise.catalog_exercise_id)
                    or muscle_map_by_name.get(exercise.exercise_name)
                )
                if muscle and workout_date:
                    if muscle not in muscle_last_date or workout_date > muscle_last_date[muscle]:
                        muscle_last_date[muscle] = workout_date
                    muscle_recent_sets[muscle] += sum(1 for s in exercise.sets if s.reps > 0)

        muscle_distribution = [
            {
                'muscle': muscle,
                'lastTrainedDate': muscle_last_date[muscle],
                'recentSets': muscle_recent_sets[muscle],
            }
            for muscle in sorted(muscle_last_date, key=lambda m: muscle_last_date[m], reverse=True)
        ]

        latest_body = body_entries[0] if body_entries else None
        oldest_recent_weight = next((entry for entry in reversed(body_entries) if entry.weight_kg is not None), None)
        latest_recent_weight = next((entry for entry in body_entries if entry.weight_kg is not None), None)

        weight_trend = None
        if oldest_recent_weight and latest_recent_weight and oldest_recent_weight.id != latest_recent_weight.id:
            weight_trend = round((latest_recent_weight.weight_kg or 0) - (oldest_recent_weight.weight_kg or 0), 2)

        return {
            'app': {
                'name': _APP_DISPLAY_NAME,
                'today': today.isoformat(),
                'timezone': 'Europe/Moscow',
            },
            'user': {
                'displayName': display_name_for_user(user),
            },
            'trainingSummary': {
                'totalWorkouts': workout_count_total,
                'workoutsLast30Days': recent_workout_count,
                'topExercisesRecent': [
                    {'name': name, 'muscle': muscle_map_by_name.get(name)}
                    for name, _ in top_exercises.most_common(5)
                ],
                'availableExercises': [
                    {'name': ex.name, 'primaryMuscle': ex.primary_muscle}
                    for ex in catalog_exercises
                ],
                'muscleDistribution': muscle_distribution,
            },
            'bodyMetrics': None
            if latest_body is None
            else {
                'entryDate': latest_body.entry_date.isoformat(),
                'weightKg': latest_body.weight_kg,
                'waistCm': latest_body.waist_cm,
                'chestCm': latest_body.chest_cm,
                'hipsCm': latest_body.hips_cm,
                'notes': _trim_text(latest_body.notes, 160),
                'weightTrendRecentKg': weight_trend,
            },
            'recentWeeklyVolume': [
                {
                    'weekStart': row.week_start.date().isoformat(),
                    'volume': round(float(row.volume or 0), 1),
                }
                for row in volume_rows
            ],
            'recentWorkouts': workouts_summary,
        }

    def clear_history(self, *, user_id: int) -> None:
        self.db.execute(
            delete(CoachChatMessage).where(CoachChatMessage.user_id == user_id)
        )
        self.db.commit()

    def _trim_history(self, *, user_id: int) -> None:
        ids_to_keep = list(
            self.db.scalars(
                select(CoachChatMessage.id)
                .where(CoachChatMessage.user_id == user_id)
                .order_by(CoachChatMessage.created_at.desc(), CoachChatMessage.id.desc())
                .limit(self._history_limit)
            )
        )
        if not ids_to_keep:
            return
        self.db.execute(
            delete(CoachChatMessage).where(
                CoachChatMessage.user_id == user_id,
                CoachChatMessage.id.not_in(ids_to_keep),
            )
        )


def _trim_text(value: str | None, limit: int) -> str | None:
    if not value:
        return None
    text = ' '.join(value.split())
    if len(text) <= limit:
        return text
    return f'{text[: limit - 1].rstrip()}...'
