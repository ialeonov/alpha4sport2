from __future__ import annotations

import functools
import json
import re
from collections import Counter
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import httpx
from sqlalchemy import delete, func, select, text
from sqlalchemy.orm import Session, joinedload

from app.core.config import settings
from app.models.body import BodyEntry
from app.models.coach import CoachChatMessage
from app.models.user import User
from app.models.user_profile import UserProfile
from app.models.workout import ExerciseCatalog, ExerciseSet, Workout, WorkoutExercise
from app.services.account_event_service import display_name_for_user


class CoachServiceError(Exception):
    pass


_APP_DISPLAY_NAME = 'Путь Силы'
_APP_TIMEZONE = ZoneInfo('Europe/Moscow')

# ── Мышечные тиры ─────────────────────────────────────────────────────────────
_EXCLUDED_MUSCLES: frozenset[str] = frozenset({'предплечья', 'кор', 'голень'})
_TIER2_MUSCLES: frozenset[str] = frozenset({'трицепс', 'бицепс', 'задние_дельты', 'трапеции', 'пресс'})
_TIER3_MUSCLES: frozenset[str] = frozenset({'икры'})

# Рекомендуемые паттерны для каждой целевой мышцы
_MUSCLE_TO_PATTERNS: dict[str, list[str]] = {
    'грудь': ['горизонтальный_жим', 'сведение'],
    'широчайшие': ['вертикальная_тяга', 'горизонтальная_тяга'],
    'трапеции': ['горизонтальная_тяга', 'наклон'],
    'квадрицепсы': ['приседание', 'разгибание'],
    'бицепс_бедра': ['наклон', 'выпад'],
    'ягодицы': ['выпад', 'приседание', 'наклон'],
    'средние_дельты': ['вертикальный_жим', 'подъем'],
    'задние_дельты': ['горизонтальная_тяга', 'подъем'],
    'передние_дельты': ['вертикальный_жим'],
    'трицепс': ['разгибание'],
    'бицепс': ['сгибание'],
    'пресс': ['сгибание_корпуса', 'стабилизация_корпуса'],
    'икры': ['другое'],
}

_GOAL_VOLUME_GUIDANCE: dict[str, dict[str, str]] = {
    'масса': {'sets': '4-5', 'reps': '6-10', 'note': 'базовые движения в приоритете, прогрессия по весу'},
    'сила': {'sets': '4-6', 'reps': '3-6', 'note': 'тяжёлые веса, длинный отдых между подходами'},
    'похудение': {'sets': '3-4', 'reps': '12-15', 'note': 'акцент на базовые, суперсеты допустимы'},
    'поддержание': {'sets': '3', 'reps': '8-12', 'note': 'сбалансированный объём и интенсивность'},
}


def _build_tier1_muscles(gender: str | None, goals: list[str]) -> frozenset[str]:
    base = {'грудь', 'широчайшие', 'квадрицепсы', 'бицепс_бедра', 'ягодицы', 'средние_дельты'}
    if gender == 'женский' or 'похудение' in goals:
        base.add('пресс')
    return frozenset(base)


def _muscle_tier(muscle: str, tier1: frozenset[str]) -> int | None:
    """None = excluded (никогда не включать как цель тренировки)."""
    if muscle in _EXCLUDED_MUSCLES:
        return None
    if muscle in tier1:
        return 1
    if muscle in _TIER2_MUSCLES:
        return 2
    if muscle in _TIER3_MUSCLES:
        return 3
    return 99


@functools.lru_cache(maxsize=1)
def _load_exercise_catalog_lookup() -> dict[str, dict]:
    """Загружает JSON-каталог упражнений, кэширует на весь процесс."""
    candidates = (
        Path(__file__).resolve().parents[2] / 'docs' / 'fit_catalog.json',
        Path(__file__).resolve().parents[3] / 'docs' / 'fit_catalog.json',
    )
    catalog_path = next((p for p in candidates if p.exists()), candidates[0])
    try:
        with open(catalog_path, encoding='utf-8') as f:
            data = json.load(f)
        return {
            ex['name'].strip().lower(): ex
            for ex in data.get('exercises', [])
            if ex.get('name')
        }
    except Exception:
        return {}


class CoachService:
    _history_limit = 200

    def __init__(self, db: Session):
        self.db = db

    async def reply(
        self,
        *,
        user: User,
        messages: list[dict[str, str]],
        wellness_entries: list[dict] | None = None,
    ) -> dict:
        context_summary = self._build_context_summary(user)
        content, model = await self._request_completion(
            self._build_chat_messages(
                context_summary=context_summary,
                messages=messages,
                wellness_entries=wellness_entries,
            )
        )
        return {
            'reply': content,
            'model': model,
            'context_summary': context_summary,
        }

    async def generate_workout(
        self,
        *,
        user: User,
        intensity_title: str,
        min_exercises: int,
        max_exercises: int,
        user_notes: str | None = None,
        wellness_entries: list[dict] | None = None,
    ) -> dict:
        if min_exercises > max_exercises:
            raise CoachServiceError('Некорректный диапазон количества упражнений.')

        context_summary = self._build_context_summary(user)
        planner_summary = self._build_workout_planner_summary(
            context_summary=context_summary,
            min_exercises=min_exercises,
            max_exercises=max_exercises,
            wellness_entries=wellness_entries,
        )
        llm_messages = self._build_workout_generation_messages(
            context_summary=context_summary,
            planner_summary=planner_summary,
            intensity_title=intensity_title,
            min_exercises=min_exercises,
            max_exercises=max_exercises,
            user_notes=user_notes,
            wellness_entries=wellness_entries,
        )
        content, model = await self._request_completion(llm_messages, temperature=0.25)

        available_exercises = (
            context_summary.get('trainingSummary', {}).get('availableExercises') or []
        )
        available_names = {
            str(ex.get('name') or '').strip().lower()
            for ex in available_exercises
            if ex.get('name')
        }
        exercise_to_muscle = {
            str(ex.get('name') or '').strip().lower(): str(ex.get('primaryMuscle') or '').strip()
            for ex in available_exercises
            if ex.get('name')
        }
        blocked_muscles = {
            str(item.get('muscle') or '').strip()
            for item in (planner_summary.get('muscleRecovery') or [])
            if item.get('recoveryStatus') == 'blocked'
        }

        validated_data, errors = self._parse_and_validate_workout(
            content, available_names, blocked_muscles, exercise_to_muscle,
            min_exercises, max_exercises,
        )

        if validated_data is None or len(validated_data.get('exercises') or []) < min_exercises:
            error_summary = '; '.join(errors) if errors else 'невалидный JSON или недостаточно упражнений'
            retry_message = (
                f'Предыдущий ответ содержал ошибки: {error_summary}. '
                'Исправь и верни только валидный JSON.'
            )
            retry_messages = llm_messages + [
                {'role': 'assistant', 'content': content},
                {'role': 'user', 'content': retry_message},
            ]
            content, model = await self._request_completion(retry_messages, temperature=0.25)
            validated_data, _ = self._parse_and_validate_workout(
                content, available_names, blocked_muscles, exercise_to_muscle,
                min_exercises, max_exercises,
            )
            if validated_data is None or len(validated_data.get('exercises') or []) < min_exercises:
                raise CoachServiceError(
                    'Не удалось сгенерировать тренировку, попробуйте ещё раз'
                )

        return {
            'reply': json.dumps(validated_data, ensure_ascii=False),
            'model': model,
            'context_summary': context_summary,
            'planner_summary': planner_summary,
        }

    @staticmethod
    def _parse_workout_json(content: str) -> dict | None:
        """Пытается извлечь JSON из ответа LLM. Возвращает None при неудаче."""
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            pass
        match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', content, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(1))
            except json.JSONDecodeError:
                pass
        match = re.search(r'\{.*\}', content, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                pass
        return None

    @staticmethod
    def _validate_workout_json(
        workout_data: dict,
        available_names: set[str],
        blocked_muscles: set[str],
        exercise_to_muscle: dict[str, str],
        min_exercises: int,
        max_exercises: int,
    ) -> tuple[dict, list[str]]:
        """Применяет правила валидации. Возвращает (исправленные данные, список ошибок)."""
        errors: list[str] = []
        exercises = workout_data.get('exercises') or []
        filtered = []

        for ex in exercises:
            name = str(ex.get('exercise_name') or '').strip()
            name_lower = name.lower()

            # Правило 1: упражнение должно быть в каталоге
            if name_lower not in available_names:
                errors.append(f'Упражнение "{name}" не найдено в каталоге пользователя')
                continue

            # Правило 3: мышца не должна быть заблокирована
            muscle = exercise_to_muscle.get(name_lower, '')
            if muscle and muscle in blocked_muscles:
                errors.append(
                    f'Упражнение "{name}" нагружает мышцу "{muscle}" со статусом "blocked"'
                )
                continue

            # Правило 2: sets в диапазоне 1-6
            sets_val = ex.get('sets')
            if isinstance(sets_val, int):
                if sets_val < 1:
                    errors.append(f'Упражнение "{name}": sets={sets_val} некорректно, пропущено')
                    continue
                if sets_val > 6:
                    errors.append(f'Упражнение "{name}": sets={sets_val} обрезано до 6')
                    ex = {**ex, 'sets': 6}

            filtered.append(ex)

        # Правило 4: обрезаем излишек
        if len(filtered) > max_exercises:
            filtered = filtered[:max_exercises]

        result = {**workout_data, 'exercises': filtered}

        ex_count = len(filtered)
        if ex_count < min_exercises:
            errors.append(
                f'После фильтрации осталось {ex_count} упр., минимум {min_exercises}'
            )

        return result, errors

    def _parse_and_validate_workout(
        self,
        content: str,
        available_names: set[str],
        blocked_muscles: set[str],
        exercise_to_muscle: dict[str, str],
        min_exercises: int,
        max_exercises: int,
    ) -> tuple[dict | None, list[str]]:
        """Парсит JSON и валидирует тренировку. Возвращает (данные | None, ошибки)."""
        workout_data = self._parse_workout_json(content)
        if workout_data is None:
            return None, ['Не удалось распарсить JSON из ответа LLM']
        return self._validate_workout_json(
            workout_data, available_names, blocked_muscles, exercise_to_muscle,
            min_exercises, max_exercises,
        )

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
                CoachChatMessage(
                    user_id=user_id,
                    role='assistant',
                    content=assistant_text,
                    created_at=now,
                ),
            ]
        )
        self.db.flush()
        self._trim_history(user_id=user_id)
        self.db.commit()

    def list_all_history(self, *, limit: int = 1000) -> list[dict]:
        normalized_limit = max(1, min(limit, 1000))
        rows = self.db.execute(
            select(CoachChatMessage, User)
            .join(User, User.id == CoachChatMessage.user_id)
            .order_by(CoachChatMessage.created_at.desc(), CoachChatMessage.id.desc())
            .limit(normalized_limit)
        ).all()
        return [
            {
                'id': message.id,
                'user_id': owner.id,
                'user_email': owner.email,
                'user_display_name': display_name_for_user(owner),
                'role': message.role,
                'content': message.content,
                'created_at': message.created_at,
            }
            for message, owner in rows
        ]

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

    def clear_history(self, *, user_id: int) -> None:
        self.db.execute(delete(CoachChatMessage).where(CoachChatMessage.user_id == user_id))
        self.db.commit()

    async def reply_stream(
        self,
        *,
        user: User,
        messages: list[dict[str, str]],
        wellness_entries: list[dict] | None = None,
    ):
        context_summary = self._build_context_summary(user)
        chat_messages = self._build_chat_messages(
            context_summary=context_summary,
            messages=messages,
            wellness_entries=wellness_entries,
        )
        async for chunk in self._request_completion_stream(chat_messages):
            yield chunk

    async def _request_completion_stream(
        self,
        messages: list[dict[str, str]],
        temperature: float | None = None,
    ):
        if not settings.ai_coach_api_key or not settings.ai_coach_model:
            raise CoachServiceError('AI-коуч не настроен на сервере.')

        payload = {
            'model': settings.ai_coach_model,
            'messages': messages,
            'temperature': temperature if temperature is not None else settings.ai_coach_temperature,
            'stream': True,
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
                async with client.stream('POST', endpoint, headers=headers, json=payload) as response:
                    response.raise_for_status()
                    async for line in response.aiter_lines():
                        if not line.startswith('data: '):
                            continue
                        data = line[6:]
                        if data == '[DONE]':
                            break
                        try:
                            parsed = json.loads(data)
                            chunk = parsed.get('choices', [{}])[0].get('delta', {}).get('content') or ''
                            if chunk:
                                yield chunk
                        except json.JSONDecodeError:
                            pass
        except httpx.HTTPStatusError as exc:
            detail = exc.response.text.strip()
            raise CoachServiceError(
                f'LLM провайдер вернул ошибку {exc.response.status_code}: '
                f'{detail or "пустой ответ"}'
            ) from exc
        except httpx.HTTPError as exc:
            raise CoachServiceError('Не удалось связаться с LLM провайдером.') from exc

    async def _request_completion(
        self,
        messages: list[dict[str, str]],
        temperature: float | None = None,
    ) -> tuple[str, str]:
        if not settings.ai_coach_api_key or not settings.ai_coach_model:
            raise CoachServiceError('AI-коуч не настроен на сервере.')

        payload = {
            'model': settings.ai_coach_model,
            'messages': messages,
            'temperature': temperature if temperature is not None else settings.ai_coach_temperature,
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
                f'LLM провайдер вернул ошибку {exc.response.status_code}: '
                f'{detail or "пустой ответ"}'
            ) from exc
        except httpx.HTTPError as exc:
            raise CoachServiceError('Не удалось связаться с LLM провайдером.') from exc

        data = response.json()
        content = data.get('choices', [{}])[0].get('message', {}).get('content', '').strip()
        if not content:
            raise CoachServiceError('LLM провайдер вернул пустой ответ.')
        return content, data.get('model') or settings.ai_coach_model

    def _build_chat_messages(
        self,
        *,
        context_summary: dict,
        messages: list[dict[str, str]],
        wellness_entries: list[dict] | None = None,
    ) -> list[dict[str, str]]:
        today = datetime.now(_APP_TIMEZONE).date()
        system_prompt = settings.ai_coach_system_prompt.strip() or (
            f'Ты персональный фитнес-коуч внутри приложения "{_APP_DISPLAY_NAME}". '
            'Отвечай на русском языке, дружелюбно и конкретно. '
            'Опирайся только на предоставленную статистику пользователя. '
            'Если данных недостаточно, прямо скажи об этом. '
            'Не выдумывай медицинские диагнозы и не заменяй врача. '
            'Давай практические рекомендации по тренировкам, восстановлению и нагрузке. '
            'Для рекомендаций по упражнениям используй прежде всего упражнения из персонального каталога '
            'пользователя и из его недавних тренировок. Не предлагай упражнения, которых нет в его доступном '
            'списке, если только пользователь прямо не просит альтернативу. '
            'При анализе опирайся на: частоту тренировок, распределение мышечных групп, recentWorkouts, '
            'muscleDistribution, состав упражнений, число рабочих подходов, длительность тренировок и восстановление. '
            'В muscleDistribution поле recentSets7d — это суммарное число подходов на данную мышцу за последние 7 дней (не за одну тренировку). '
            'Тоннаж — вторичный и шумный показатель. Не делай по тоннажу главный вывод о качестве тренировки. '
            'RPE в подходах — сигнал интенсивности: RPE 7 умеренно, 8-9 тяжело, 10 до отказа. '
            'Учитывай RPE при оценке усталости и восстановления. '
            'Не переспрашивай и не уточняй — дай лучший ответ на основе имеющихся данных.'
        )
        runtime_prompt = (
            f'Текущая дата: {today.isoformat()} '
            f'(формат дд.мм.гггг: {today.day:02d}.{today.month:02d}.{today.year}). '
            'Если пользователь спрашивает про сегодня, завтра, вчера, текущую неделю или текущий месяц, '
            'ориентируйся именно на эту дату.'
        )
        wellness_log = _format_wellness_for_context(wellness_entries)
        context_with_wellness = {**context_summary}
        if wellness_log:
            context_with_wellness['wellnessLog'] = wellness_log
        # Для чата достаточно topExercisesRecent + muscleDistribution; полный каталог не нужен
        if 'trainingSummary' in context_with_wellness:
            ts = {**context_with_wellness['trainingSummary']}
            ts.pop('availableExercises', None)
            context_with_wellness['trainingSummary'] = ts
        context_prompt = (
            'Ниже краткий профиль и сводка по пользователю. Используй это как источник контекста.\n'
            f'{json.dumps(context_with_wellness, ensure_ascii=False)}'
        )
        wellness_note = _wellness_today_note(wellness_entries, today)
        wellness_system = (
            f'Самочувствие пользователя сегодня: {wellness_note} '
            'Учитывай это при анализе восстановления и рекомендациях по нагрузке.'
            if wellness_note
            else None
        )
        return [
            {'role': 'system', 'content': system_prompt},
            {'role': 'system', 'content': runtime_prompt},
            {'role': 'system', 'content': context_prompt},
            *([{'role': 'system', 'content': wellness_system}] if wellness_system else []),
            *messages,
        ]

    def _build_workout_generation_messages(
        self,
        *,
        context_summary: dict,
        planner_summary: dict,
        intensity_title: str,
        min_exercises: int,
        max_exercises: int,
        user_notes: str | None = None,
        wellness_entries: list[dict] | None = None,
    ) -> list[dict[str, str]]:
        today = datetime.now(_APP_TIMEZONE).date()
        system_prompt = (
            f'Ты AI-коуч приложения "{_APP_DISPLAY_NAME}". '
            'Твоя задача — составить следующую силовую тренировку на сегодня как продолжение уже идущего '
            'тренировочного процесса, а не как случайный набор упражнений. '
            'Опирайся только на plannerSummary и contextSummary. '
            '\n\nОБЯЗАТЕЛЬНЫЕ ПРАВИЛА:\n'
            '1. Мышцы с recoveryStatus="blocked" (тренировались < 48ч назад) нельзя включать как цель тренировки. '
            '   Это жёсткое ограничение — не нарушай его даже если нет других вариантов.\n'
            '2. Мышцы с muscleTier=null (предплечья, кор, голень) никогда не являются целью тренировки — '
            '   они могут быть вторичными, но не должны определять выбор упражнений.\n'
            '3. Сначала упражнения с exerciseType="базовое", затем exerciseType="изоляция". '
            '   Не ставь изоляцию раньше базового упражнения на ту же мышцу.\n'
            '4. Не включай два упражнения с одинаковым movementPattern в одну тренировку '
            '   (например, два горизонтальных жима). Исключение — если мышца явно в фокусе и нет альтернативы.\n'
            '5. Если в plannerSummary есть injuryConstraints — это абсолютное ограничение. '
            '   Не включай упражнения, которые нагружают указанную зону.\n'
            '6. Следуй profileGuidance.volumeGuidance для количества подходов и повторений.\n'
            '7. Выбирай упражнения только из candidateExercises (priority → secondary). '
            '   Не изобретай упражнения которых нет в списке.\n'
            'Для тяжёлых базовых упражнений можешь добавлять warmup_sets, но только там, где они реально нужны. '
            'В warmup_sets нельзя указывать рабочие подходы, только подводящие. '
            'Верни только JSON без markdown и без пояснений вне JSON.'
        )
        notes_part = (
            f' Пожелания пользователя к тренировке: «{user_notes}». '
            'Учти их, если они не противоречат алгоритму восстановления и нагрузки.'
            if user_notes and user_notes.strip()
            else ''
        )
        wellness_note = _wellness_today_note(wellness_entries, today)
        wellness_part = f' {wellness_note}' if wellness_note else ''
        runtime_prompt = (
            f'Сегодня {today.isoformat()}. '
            f'Интенсивность: {intensity_title}. '
            f'Нужно ровно {min_exercises}-{max_exercises} упражнений.'
            f'{notes_part}'
            f'{wellness_part}'
        )
        response_format_prompt = (
            'Формат ответа: '
            '{"name":"Название тренировки","exercises":[{"exercise_name":"Жим лёжа","sets":4,'
            '"reps":"6-8","notes":"короткая подсказка","warmup_sets":[{"reps":"10","notes":"лёгкий разминочный"},'
            '{"reps":"6","notes":"подводящий"},{"reps":"3","notes":"выход на рабочий вес"}]}]} '
            'Поле name обязательно. '
            f'В exercises должно быть только {min_exercises}-{max_exercises} упражнений. '
            'exercise_name должен быть строкой. '
            'sets должен быть целым числом от 1 до 6. '
            'reps должен быть строкой, например "6-8", "8-10" или "12". '
            'warmup_sets можно добавлять только там, где они реально нужны. '
            'В warmup_sets не указывай рабочие подходы, только подводящие. '
            'notes можно оставить пустым.'
        )
        # candidateExercises в plannerSummary уже содержит отфильтрованный список; полный каталог в contextSummary избыточен
        context_summary_for_llm = {
            **context_summary,
            'trainingSummary': {
                k: v
                for k, v in context_summary.get('trainingSummary', {}).items()
                if k != 'availableExercises'
            },
        }
        planner_prompt = (
            'Ниже структурированный анализ для генерации тренировки. '
            'Сначала определи, какие мышцы и упражнения сейчас уместны, потом собери цельную тренировку.\n'
            f'plannerSummary={json.dumps(planner_summary, ensure_ascii=False)}\n'
            f'contextSummary={json.dumps(context_summary_for_llm, ensure_ascii=False)}'
        )
        combined_system = '\n\n'.join([system_prompt, runtime_prompt, response_format_prompt])
        user_content = (
            f'{planner_prompt}\n\n'
            'Составь тренировку на сегодня по данным приложения. '
            'Учитывай историю тренировок, недавнюю нагрузку, восстановление, доступные упражнения '
            'и признаки прогрессии. Верни только JSON.'
        )
        return [
            {'role': 'system', 'content': combined_system},
            {'role': 'user', 'content': user_content},
        ]

    def _build_context_summary(self, user: User) -> dict:
        today = datetime.now(_APP_TIMEZONE).date()
        fitness_profile = self.db.scalar(
            select(UserProfile).where(UserProfile.user_id == user.id)
        )
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
                Workout.started_at
                >= datetime.combine(today - timedelta(days=30), time.min, tzinfo=timezone.utc),
            )
        ) or 0
        recent_workout_count_7d = self.db.scalar(
            select(func.count())
            .select_from(Workout)
            .where(
                Workout.user_id == user.id,
                Workout.started_at
                >= datetime.combine(today - timedelta(days=7), time.min, tzinfo=timezone.utc),
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
                Workout.started_at
                >= datetime.combine(today - timedelta(days=21), time.min, tzinfo=timezone.utc),
                ExerciseSet.weight.isnot(None),
            )
            .group_by(week_start_expr)
            .order_by(week_start_expr.desc())
            .limit(6)
        ).all()

        exercise_workout_weights: dict[str, list[tuple[date, float]]] = {}
        top_exercises_30d: Counter[str] = Counter()
        top_exercises = Counter()
        workouts_summary = []
        for workout in recent_workouts:
            total_sets = 0
            total_volume = 0.0
            warmup_sets = 0
            exercises_summary = []
            _wdate = workout.started_at.date() if workout.started_at else None
            _within_30d = _wdate is not None and (today - _wdate).days <= 30
            for exercise in workout.exercises:
                top_exercises[exercise.exercise_name] += 1
                if _within_30d:
                    top_exercises_30d[exercise.exercise_name] += 1
                _work_weights = [
                    float(s.weight)
                    for s in exercise.sets
                    if s.weight is not None
                    and getattr(s, 'set_type', 'work') != 'warmup'
                    and s.reps > 0
                ]
                if _work_weights and _wdate:
                    exercise_workout_weights.setdefault(exercise.exercise_name, []).append(
                        (_wdate, max(_work_weights))
                    )
                exercise_volume = 0.0
                exercise_warmup_sets = 0
                sets_compact = []
                for set_item in exercise.sets:
                    if set_item.reps > 0:
                        total_sets += 1
                        if getattr(set_item, 'set_type', 'work') == 'warmup':
                            warmup_sets += 1
                            exercise_warmup_sets += 1
                    if set_item.weight is not None:
                        set_vol = float(set_item.weight) * set_item.reps
                        total_volume += set_vol
                        exercise_volume += set_vol
                    parts = []
                    if getattr(set_item, 'set_type', 'work') == 'warmup':
                        parts.append('WU')
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
                ex_entry: dict[str, Any] = {
                    'name': exercise.exercise_name,
                    'sets': ' / '.join(sets_compact),
                }
                if primary_muscle:
                    ex_entry['muscle'] = primary_muscle
                if exercise_warmup_sets:
                    ex_entry['warmupSets'] = exercise_warmup_sets
                note = _trim_text(exercise.notes, 200)
                if note:
                    ex_entry['notes'] = note
                exercises_summary.append(ex_entry)

            duration_minutes = None
            if workout.started_at and workout.finished_at:
                duration_minutes = round(
                    (workout.finished_at - workout.started_at).total_seconds() / 60
                )
            w_entry: dict[str, Any] = {
                'date': workout.started_at.date().isoformat() if workout.started_at else None,
                'name': workout.name,
                'exercises': exercises_summary,
            }
            working_sets = total_sets - warmup_sets
            if duration_minutes is not None:
                w_entry['durationMin'] = duration_minutes
            if working_sets:
                w_entry['workingSets'] = working_sets
            if warmup_sets:
                w_entry['warmupSets'] = warmup_sets
            note = _trim_text(workout.notes, 240)
            if note:
                w_entry['notes'] = note
            workouts_summary.append(w_entry)

        # ── Тренды прогрессии: топ-10 упражнений по частоте за 30 дней ───────
        for _ename in exercise_workout_weights:
            exercise_workout_weights[_ename].sort(key=lambda t: t[0], reverse=True)
        progression_trends: list[dict] = []
        for _ename, _ in top_exercises_30d.most_common(10):
            _entries = exercise_workout_weights.get(_ename, [])[:4]
            if len(_entries) < 2:
                continue
            _weights = [round(w, 2) for _, w in _entries]
            _diff = _weights[0] - _weights[-1]
            if _diff >= 2.5:
                _trend = 'growing'
            elif _diff <= -2.5:
                _trend = 'declining'
            else:
                _trend = 'stalled'
            _days_span = (_entries[0][0] - _entries[-1][0]).days
            _weeks = max(1, round(_days_span / 7))
            if _weeks == 1:
                _period = '1 неделя'
            elif 2 <= _weeks <= 4:
                _period = f'{_weeks} недели'
            else:
                _period = f'{_weeks} недель'
            progression_trends.append({
                'name': _ename,
                'trend': _trend,
                'weights': _weights,
                'period': _period,
            })

        muscle_last_date: dict[str, str] = {}
        muscle_recent_sets_7d: Counter[str] = Counter()
        for workout in recent_workouts:
            workout_date_obj = workout.started_at.date() if workout.started_at else None
            workout_date = workout_date_obj.isoformat() if workout_date_obj else None
            for exercise in workout.exercises:
                muscle = (
                    muscle_map.get(exercise.catalog_exercise_id)
                    or muscle_map_by_name.get(exercise.exercise_name)
                )
                if muscle and workout_date:
                    if muscle not in muscle_last_date or workout_date > muscle_last_date[muscle]:
                        muscle_last_date[muscle] = workout_date
                    if workout_date_obj and (today - workout_date_obj).days <= 7:
                        muscle_recent_sets_7d[muscle] += sum(
                            1 for s in exercise.sets
                            if s.reps > 0 and getattr(s, 'set_type', 'work') != 'warmup'
                        )

        muscle_distribution = [
            {
                'muscle': muscle,
                'lastTrainedDate': muscle_last_date[muscle],
                'recentSets7d': muscle_recent_sets_7d[muscle],
            }
            for muscle in sorted(
                muscle_last_date,
                key=lambda muscle: muscle_last_date[muscle],
                reverse=True,
            )
        ]

        latest_body = body_entries[0] if body_entries else None
        oldest_recent_weight = next(
            (entry for entry in reversed(body_entries) if entry.weight_kg is not None),
            None,
        )
        latest_recent_weight = next(
            (entry for entry in body_entries if entry.weight_kg is not None),
            None,
        )

        weight_trend = None
        if oldest_recent_weight and latest_recent_weight and oldest_recent_weight.id != latest_recent_weight.id:
            weight_trend = round(
                (latest_recent_weight.weight_kg or 0) - (oldest_recent_weight.weight_kg or 0),
                2,
            )

        profile_data: dict = {}
        if fitness_profile is not None:
            goals = [goal for goal in (fitness_profile.goal or '').split(',') if goal]
            if goals:
                profile_data['goals'] = goals
            if fitness_profile.experience:
                profile_data['experience'] = fitness_profile.experience
            if fitness_profile.gender:
                profile_data['gender'] = fitness_profile.gender
            if fitness_profile.injuries:
                profile_data['injuries'] = fitness_profile.injuries
            if fitness_profile.days_per_week:
                profile_data['daysPerWeek'] = fitness_profile.days_per_week

        return {
            'app': {
                'name': _APP_DISPLAY_NAME,
                'timezone': 'Europe/Moscow',
            },
            'user': {
                'displayName': display_name_for_user(user),
                **({'fitnessProfile': profile_data} if profile_data else {}),
            },
            'trainingSummary': {
                'totalWorkouts': workout_count_total,
                'workoutsLast7Days': recent_workout_count_7d,
                'workoutsLast30Days': recent_workout_count,
                'daysSinceLastWorkout': (
                    (today - recent_workouts[0].started_at.date()).days
                    if recent_workouts and recent_workouts[0].started_at
                    else None
                ),
                'topExercisesRecent': [
                    {'name': name, 'muscle': muscle_map_by_name.get(name), 'timesInLast12': count}
                    for name, count in top_exercises.most_common(5)
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
            'progressionTrends': progression_trends,
        }

    def _build_workout_planner_summary(
        self,
        *,
        context_summary: dict,
        min_exercises: int,
        max_exercises: int,
        wellness_entries: list[dict] | None = None,
    ) -> dict:
        recent_workouts = (context_summary.get('recentWorkouts') or [])[:12]
        available_exercises = (
            context_summary.get('trainingSummary', {}).get('availableExercises') or []
        )
        top_exercises_recent = (
            context_summary.get('trainingSummary', {}).get('topExercisesRecent') or []
        )
        body_metrics = context_summary.get('bodyMetrics') or {}
        today = datetime.now(_APP_TIMEZONE).date()

        fitness_profile: dict = context_summary.get('user', {}).get('fitnessProfile') or {}
        goals: list[str] = fitness_profile.get('goals') or []
        gender: str | None = fitness_profile.get('gender')
        experience: str | None = fitness_profile.get('experience')
        injuries: str | None = fitness_profile.get('injuries')

        tier1 = _build_tier1_muscles(gender=gender, goals=goals)
        catalog_lookup = _load_exercise_catalog_lookup()

        exercise_usage_14d: Counter[str] = Counter()
        exercise_last_date: dict[str, str] = {}
        muscle_last_date: dict[str, str] = {}
        recent_sets_by_muscle_7d: Counter[str] = Counter()
        recent_sets_by_muscle_3d: Counter[str] = Counter()
        heavy_rpe_by_muscle_7d: Counter[str] = Counter()
        exercise_examples: dict[str, list[dict[str, Any]]] = {}

        for workout_index, workout in enumerate(recent_workouts):
            workout_date = _safe_parse_date(workout.get('date'))
            exercises = (workout.get('exercises') or [])[:20]
            for exercise in exercises:
                name = str(exercise.get('name') or '').strip()
                muscle = str(exercise.get('muscle') or '').strip()
                sets_text = str(exercise.get('sets') or '').strip()
                if not name:
                    continue
                if workout_date and (today - workout_date).days <= 14:
                    exercise_usage_14d[name] += 1
                if workout_date:
                    last_date = exercise_last_date.get(name)
                    if last_date is None or workout_date.isoformat() > last_date:
                        exercise_last_date[name] = workout_date.isoformat()
                if muscle and workout_date:
                    last_muscle_date = muscle_last_date.get(muscle)
                    if last_muscle_date is None or workout_date.isoformat() > last_muscle_date:
                        muscle_last_date[muscle] = workout_date.isoformat()
                    if (today - workout_date).days <= 7:
                        recent_sets_by_muscle_7d[muscle] += _count_sets_from_compact(sets_text)
                        heavy_rpe_by_muscle_7d[muscle] += _count_heavy_sets_from_compact(sets_text)
                    if (today - workout_date).days <= 3:
                        recent_sets_by_muscle_3d[muscle] += _count_sets_from_compact(sets_text)
                exercise_examples.setdefault(name, []).append(
                    {
                        'date': workout.get('date'),
                        'sets': sets_text,
                        'muscle': muscle or None,
                        'workoutName': workout.get('name'),
                        'workoutIndex': workout_index,
                    }
                )

        muscle_pool = sorted(
            {
                str(item.get('primaryMuscle') or '').strip()
                for item in available_exercises
                if str(item.get('primaryMuscle') or '').strip()
            }
        )
        scored_muscles = []
        for muscle in muscle_pool:
            tier = _muscle_tier(muscle, tier1)
            last_date = _safe_parse_date(muscle_last_date.get(muscle))
            days_since = (today - last_date).days if last_date else 999
            recent_3d = recent_sets_by_muscle_3d[muscle]
            recent_7d = recent_sets_by_muscle_7d[muscle]
            heavy_7d = heavy_rpe_by_muscle_7d[muscle]

            # Жёсткое правило 48ч: мышца тренировалась сегодня или вчера с объёмом
            if days_since == 0 or (days_since == 1 and recent_3d >= 4):
                recovery_status = 'blocked'
            elif recent_3d >= 6 or heavy_7d >= 3:
                recovery_status = 'fatigued'
            else:
                recovery_status = 'ready'

            score = (days_since * 1.4) - (recent_3d * 2.8) - (recent_7d * 0.8) - (heavy_7d * 1.5)
            scored_muscles.append(
                {
                    'muscle': muscle,
                    'muscleTier': tier,
                    'daysSince': days_since if days_since != 999 else None,
                    'recentSets3d': recent_3d,
                    'recentSets7d': recent_7d,
                    'heavySets7d': heavy_7d,
                    'recoveryStatus': recovery_status,
                    'score': round(score, 2),
                }
            )
        scored_muscles.sort(key=lambda item: item['score'], reverse=True)

        # Рекомендуемые мышцы: только tier 1 (при наличии), затем tier 2
        # Excluded-мышцы (tier=None) никогда не попадают в рекомендации
        tier1_ready = [
            item['muscle'] for item in scored_muscles
            if item['muscleTier'] == 1 and item['recoveryStatus'] != 'blocked'
        ]
        tier2_ready = [
            item['muscle'] for item in scored_muscles
            if item['muscleTier'] == 2 and item['recoveryStatus'] != 'blocked'
        ]
        recommended_focus = (tier1_ready[:3] if tier1_ready else tier2_ready[:3])

        avoid_focus = [
            item['muscle']
            for item in scored_muscles
            if item['recoveryStatus'] in ('blocked', 'fatigued')
        ][:5]

        # Кандидаты с паттернами движений из JSON-каталога
        candidates_priority = []
        candidates_secondary = []
        candidates_avoid = []
        for entry in available_exercises:
            name = str(entry.get('name') or '').strip()
            muscle = str(entry.get('primaryMuscle') or '').strip()
            if not name:
                continue

            catalog_entry = catalog_lookup.get(name.lower()) or {}
            exercise_type = catalog_entry.get('exercise_type') or ''
            movement_pattern = catalog_entry.get('movement_pattern') or ''

            # Опытный фильтр: новичок — только базовые
            if experience == 'новичок' and exercise_type == 'изоляция':
                continue

            last_date = _safe_parse_date(exercise_last_date.get(name))
            days_since = (today - last_date).days if last_date else None
            recent_count = exercise_usage_14d[name]
            history = exercise_examples.get(name, [])
            anchor = history[0] if history else None
            reasons = []
            if muscle in recommended_focus:
                reasons.append('мышца нуждается в акценте')
            if days_since is None:
                reasons.append('есть в каталоге, но давно не использовалось')
            elif days_since >= 7:
                reasons.append(f'не было {days_since} дн.')
            if recent_count == 0:
                reasons.append('не использовалось в последние 14 дней')
            elif recent_count == 1 and (days_since or 0) >= 5:
                reasons.append('редкое недавнее использование')
            if anchor and anchor.get('sets'):
                reasons.append(f'последний пример: {anchor["sets"]}')

            item = {
                'name': name,
                'muscle': muscle or None,
                'exerciseType': exercise_type or None,
                'movementPattern': movement_pattern or None,
                'daysSince': days_since,
                'recentCount14d': recent_count,
                'reason': '; '.join(reasons[:3]) if reasons else None,
                'lastPerformance': anchor.get('sets') if anchor else None,
            }
            if muscle in avoid_focus and (days_since is None or days_since <= 4):
                candidates_avoid.append(item)
            elif muscle in recommended_focus:
                candidates_priority.append(item)
            else:
                candidates_secondary.append(item)

        candidates_priority.sort(
            key=lambda item: (
                999 if item['daysSince'] is None else -item['daysSince'],
                -item['recentCount14d'],
            )
        )
        candidates_secondary.sort(
            key=lambda item: (
                item['recentCount14d'],
                999 if item['daysSince'] is None else -item['daysSince'],
            )
        )
        candidates_avoid.sort(
            key=lambda item: (
                item['daysSince'] if item['daysSince'] is not None else -1,
                -item['recentCount14d'],
            )
        )

        progression_anchors = []
        for entry in top_exercises_recent[:5]:
            name = str(entry.get('name') or '').strip()
            if not name:
                continue
            history = exercise_examples.get(name, [])
            if not history:
                continue
            progression_anchors.append(
                {
                    'exercise': name,
                    'muscle': entry.get('muscle'),
                    'lastPerformance': history[0].get('sets'),
                    'lastDate': history[0].get('date'),
                }
            )

        fatigue_flags = []
        for item in scored_muscles:
            if item['recoveryStatus'] == 'blocked':
                fatigue_flags.append(
                    f'{item["muscle"]}: тренировалась < 48ч назад — исключить из фокуса'
                )
            elif item['recentSets3d'] >= 6:
                fatigue_flags.append(f'Высокая нагрузка на {item["muscle"]} за 3 дня')
            elif item['heavySets7d'] >= 3:
                fatigue_flags.append(f'Много тяжёлых подходов на {item["muscle"]} за 7 дней')

        # Паттерны движений для рекомендуемых мышц
        suggested_patterns: list[str] = []
        seen_patterns: set[str] = set()
        for muscle in recommended_focus:
            for pattern in _MUSCLE_TO_PATTERNS.get(muscle, []):
                if pattern not in seen_patterns:
                    seen_patterns.add(pattern)
                    suggested_patterns.append(pattern)

        # Профильные рекомендации
        profile_guidance: dict[str, Any] = {}
        for goal in goals:
            if goal in _GOAL_VOLUME_GUIDANCE:
                profile_guidance['volumeGuidance'] = _GOAL_VOLUME_GUIDANCE[goal]
                break
        if experience:
            profile_guidance['experience'] = experience
            if experience == 'новичок':
                profile_guidance['exerciseComplexity'] = 'только базовые движения, 3 подхода, изоляция исключена'
            elif experience == 'продвинутый':
                profile_guidance['exerciseComplexity'] = 'базовые + изоляция, сложные паттерны допустимы'
        if gender == 'женский':
            profile_guidance['genderNote'] = 'акцент на ноги, ягодицы, пресс'

        wellness_signals = _build_wellness_signals(wellness_entries, today)
        if wellness_signals.get('fatigueFlags'):
            fatigue_flags = (wellness_signals['fatigueFlags'] + fatigue_flags)[:8]

        return {
            'targetExerciseCount': {
                'min': min_exercises,
                'max': max_exercises,
            },
            'splitGuess': _guess_split_from_workouts(recent_workouts),
            'recommendedFocusMuscles': recommended_focus,
            'avoidFocusMuscles': avoid_focus,
            'muscleRecovery': scored_muscles,
            'candidateExercises': {
                'priority': candidates_priority[:12],
                'secondary': candidates_secondary[:18],
                'avoid': candidates_avoid[:12],
            },
            'progressionTrends': context_summary.get('progressionTrends') or [],
            'progressionAnchors': progression_anchors[:6],
            'fatigueFlags': fatigue_flags[:8],
            'weeklyVolumeTrend': (context_summary.get('recentWeeklyVolume') or [])[:4],
            'bodySignals': {
                'weightTrendRecentKg': body_metrics.get('weightTrendRecentKg'),
            },
            'movementPatternGuidance': {
                'suggestedPatterns': suggested_patterns[:6],
                'rule': (
                    'Не ставь в одну тренировку два упражнения с одинаковым movementPattern. '
                    'Сначала базовые (exerciseType=базовое), затем изоляция.'
                ),
            },
            'profileGuidance': profile_guidance or None,
            'injuryConstraints': injuries.strip() if injuries and injuries.strip() else None,
            'wellnessSignals': wellness_signals if wellness_signals.get('today') else None,
        }

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


def _safe_parse_date(raw: Any) -> date | None:
    if not raw:
        return None
    if isinstance(raw, date):
        return raw
    try:
        return date.fromisoformat(str(raw))
    except ValueError:
        return None


def _count_sets_from_compact(sets_text: str) -> int:
    if not sets_text:
        return 0
    return len([chunk for chunk in sets_text.split(' / ') if chunk.strip()])


def _count_heavy_sets_from_compact(sets_text: str) -> int:
    if not sets_text:
        return 0
    heavy = 0
    for chunk in sets_text.split(' / '):
        if '@' not in chunk:
            continue
        try:
            rpe_text = chunk.split('@', 1)[1].split('×', 1)[0].strip()
            if float(rpe_text) >= 8.5:
                heavy += 1
        except ValueError:
            continue
    return heavy


def _format_wellness_for_context(wellness_entries: list[dict] | None) -> list[dict] | None:
    if not wellness_entries:
        return None
    result = []
    for entry in sorted(wellness_entries, key=lambda e: e.get('date', ''), reverse=True)[:7]:
        item: dict[str, Any] = {
            'date': entry.get('date'),
            'sleep': entry.get('sleep'),
            'energy': entry.get('energy'),
            'stress': entry.get('stress'),
            'mood': entry.get('mood'),
        }
        if entry.get('comment'):
            item['comment'] = entry['comment']
        result.append(item)
    return result or None


def _wellness_today_note(wellness_entries: list[dict] | None, today: date) -> str | None:
    if not wellness_entries:
        return None
    today_str = today.isoformat()
    entry = next((e for e in wellness_entries if e.get('date') == today_str), None)
    if not entry:
        return None

    s = entry.get('sleep', 3)
    e = entry.get('energy', 3)
    st = entry.get('stress', 3)
    m = entry.get('mood', 3)

    base = f'сон {s}/5, энергия {e}/5, стресс {st}/5, настроение {m}/5'
    if entry.get('comment'):
        base += f', заметка: "{entry["comment"]}"'

    if st >= 4:
        advice = '⚠️ Высокий стресс — снизь интенсивность, избегай работы до отказа.'
    elif s <= 2 or e <= 2:
        advice = '⚠️ Низкая энергия или плохой сон — предпочтителен умеренный объём.'
    elif m <= 2:
        advice = '⚠️ Низкое настроение — возможна адаптация нагрузки.'
    elif s >= 4 and e >= 4 and m >= 4:
        advice = '✅ Отличное самочувствие — можно работать на полную.'
    else:
        advice = ''

    return f'{base}. {advice}'.strip()


def _build_wellness_signals(wellness_entries: list[dict] | None, today: date) -> dict:
    if not wellness_entries:
        return {}

    today_str = today.isoformat()
    today_entry = next((e for e in wellness_entries if e.get('date') == today_str), None)

    if not today_entry:
        return {}

    s = today_entry.get('sleep', 3)
    e = today_entry.get('energy', 3)
    st = today_entry.get('stress', 3)
    m = today_entry.get('mood', 3)

    flags: list[str] = []
    intensity_modifier = 'normal'

    if st >= 4:
        flags.append('Высокий стресс сегодня — снизить интенсивность, исключить работу до отказа')
        intensity_modifier = 'reduce'
    if s <= 2:
        flags.append('Плохой сон — предпочтителен умеренный объём, избегай максимальных весов')
        intensity_modifier = 'reduce'
    if e <= 2:
        flags.append('Низкая энергия — сократить объём или выбрать упражнения с меньшим КПД')
        intensity_modifier = 'reduce'
    if m <= 2:
        flags.append('Низкое настроение — рассмотри более мотивирующие упражнения или снижение объёма')
    if s >= 4 and e >= 4 and m >= 4 and st <= 2:
        intensity_modifier = 'boost'

    return {
        'today': {
            'sleep': s,
            'energy': e,
            'stress': st,
            'mood': m,
            'comment': today_entry.get('comment'),
        },
        'intensityModifier': intensity_modifier,
        'fatigueFlags': flags,
    }


def _guess_split_from_workouts(recent_workouts: list[dict]) -> str:
    if len(recent_workouts) < 3:
        return 'mixed'
    dominant_muscles = []
    for workout in recent_workouts[:6]:
        counter = Counter(
            str(exercise.get('muscle') or '').strip()
            for exercise in (workout.get('exercises') or [])
            if str(exercise.get('muscle') or '').strip()
        )
        if not counter:
            continue
        dominant_muscles.append(counter.most_common(1)[0][0])
    unique = set(dominant_muscles)
    if len(unique) >= 5:
        return 'full_body_or_mixed'
    if {'грудь', 'спина', 'ноги'}.issubset(unique):
        return 'body_part_split'
    if 'ноги' in unique and len(unique) <= 3:
        return 'upper_lower_or_push_pull_legs'
    return 'mixed'
