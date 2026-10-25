"""Долгая геймификация: задания недели, уровни мышц, силовые клубы.

Всё считается из истории тренировок при каждом пересчёте прогрессии — как и
остальные награды в ProgressionService, — поэтому отдельных таблиц не нужно.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

from app.models.workout import Workout
from app.services.muscle_load import MuscleLoadCalculator
from app.services.progression_math import start_of_week

# Задания начисляют XP только с этой недели, чтобы не раздувать уже набранный
# опыт задним числом.
QUESTS_START = date(2026, 10, 26)
QUEST_XP = 15
QUEST_ALL_BONUS_XP = 25

MUSCLE_GROUPS: dict[str, tuple[str, ...]] = {
    'ноги': ('квадрицепсы', 'бицепс_бедра', 'ягодицы', 'икры'),
    'спину': ('широчайшие', 'трапеции'),
    'грудь': ('грудь',),
    'плечи': ('передние_дельты', 'средние_дельты', 'задние_дельты'),
    'руки': ('бицепс', 'трицепс'),
}
_VOLUME_QUEST_SETS = 10
_RPE_QUEST_SETS = 10


@dataclass(frozen=True)
class Quest:
    code: str
    title: str
    description: str
    progress: int
    target: int

    @property
    def completed(self) -> bool:
        return self.progress >= self.target

    def to_dict(self) -> dict:
        return {
            'code': self.code,
            'title': self.title,
            'description': self.description,
            'progress': min(self.progress, self.target),
            'target': self.target,
            'completed': self.completed,
            'xp': QUEST_XP,
        }


def _workout_day(workout: Workout) -> date | None:
    moment = workout.finished_at or workout.started_at
    return moment.date() if moment else None


def _in_range(workouts: list[Workout], start: date, end: date) -> list[Workout]:
    return [w for w in workouts if (d := _workout_day(w)) and start <= d <= end]


def _group_sets(loads: dict[str, float], group: str) -> float:
    return sum(loads.get(m, 0.0) for m in MUSCLE_GROUPS[group])


def build_week_quests(
    *,
    week_start: date,
    workouts: list[Workout],
    calculator: MuscleLoadCalculator,
    record_count: int,
    weekly_target: int,
) -> list[Quest]:
    """Три задания недели. Цели фиксируются по данным ДО начала недели, чтобы
    задание не менялось посреди недели; прогресс — по самой неделе."""
    week_end = week_start + timedelta(days=6)
    week_workouts = _in_range(workouts, week_start, week_end)
    before = _in_range(workouts, week_start - timedelta(days=14), week_start - timedelta(days=1))

    # 1. Объём на самую отстающую группу за прошлые две недели.
    before_loads = calculator.total_loads(before, reference=workouts)
    lagging = min(MUSCLE_GROUPS, key=lambda g: (_group_sets(before_loads, g), g))
    week_loads = calculator.total_loads(week_workouts, reference=workouts)
    volume = Quest(
        code='volume',
        title=f'{_VOLUME_QUEST_SETS} подходов на {lagging}',
        description='Эффективные подходы за неделю на группу, которая отстаёт',
        progress=int(_group_sets(week_loads, lagging)),
        target=_VOLUME_QUEST_SETS,
    )

    # 2. Личный рекорд.
    record = Quest(
        code='record',
        title='Побей личный рекорд',
        description='Новый рекорд веса или объёма в любом упражнении',
        progress=record_count,
        target=1,
    )

    # 3. Чередуется по неделям: регулярность или честный RPE.
    if week_start.isocalendar().week % 2 == 0:
        third = Quest(
            code='frequency',
            title=f'{weekly_target} тренировки за неделю',
            description='Цель недели из вашего профиля',
            progress=len([w for w in week_workouts if w.finished_at]),
            target=weekly_target,
        )
    else:
        rpe_sets = sum(
            1
            for w in week_workouts
            for e in w.exercises
            for s in e.sets
            if s.set_type != 'warmup' and s.reps > 0 and s.rpe
        )
        third = Quest(
            code='rpe',
            title=f'RPE в {_RPE_QUEST_SETS} подходах',
            description='Отмечайте, насколько тяжело — тренер точнее подберёт веса',
            progress=rpe_sets,
            target=_RPE_QUEST_SETS,
        )
    return [volume, record, third]


def quest_weeks(today: date) -> list[date]:
    """Недели, за которые начисляются задания: от старта до текущей."""
    weeks = []
    cursor = start_of_week(QUESTS_START)
    current = start_of_week(today)
    while cursor <= current:
        weeks.append(cursor)
        cursor += timedelta(days=7)
    return weeks


def week_end_moment(week_start: date, today: date) -> datetime:
    if week_start == start_of_week(today):
        return datetime.now(timezone.utc)
    end = week_start + timedelta(days=6)
    return datetime(end.year, end.month, end.day, 23, 59, 59, tzinfo=timezone.utc)


# ── Уровни мышц ──────────────────────────────────────────────────────────────

_MUSCLE_ORDER = (
    'грудь', 'широчайшие', 'трапеции', 'передние_дельты', 'средние_дельты',
    'задние_дельты', 'бицепс', 'трицепс', 'квадрицепсы', 'бицепс_бедра',
    'ягодицы', 'икры', 'пресс',
)


def muscle_level(sets: float) -> tuple[int, int, int]:
    """(уровень, порог текущего, порог следующего): порог уровня n — 10·n²
    эффективных подходов за всё время (10, 40, 90, 160, 250…)."""
    level = int(math.sqrt(max(sets, 0) / 10))
    return level, 10 * level * level, 10 * (level + 1) * (level + 1)


def build_muscle_levels(workouts: list[Workout], calculator: MuscleLoadCalculator) -> list[dict]:
    loads = calculator.total_loads(workouts)
    result = []
    for muscle in _MUSCLE_ORDER:
        sets = loads.get(muscle, 0.0)
        level, current, nxt = muscle_level(sets)
        result.append({
            'muscle': muscle,
            'sets': round(sets),
            'level': level,
            'levelStartSets': current,
            'nextLevelSets': nxt,
        })
    return result


# ── Силовые клубы ────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Club:
    key: str
    title: str
    include: tuple[str, ...]
    exclude: tuple[str, ...]
    thresholds: tuple[int, ...]


CLUBS = (
    Club('bench', 'Жим лёжа', ('жим лёжа', 'жим лежа'), ('француз', 'узк', 'гантел'), (60, 80, 100, 120, 140)),
    Club('squat', 'Приседания', ('присед',), ('сплит', 'болгар', 'гоблет'), (60, 100, 140, 180)),
    Club('deadlift', 'Становая тяга', ('становая',), ('румын',), (100, 140, 180, 220)),
    Club('leg_press', 'Жим ногами', ('жим ногами',), (), (100, 150, 200, 250, 300)),
)


def club_for(exercise_name: str) -> Club | None:
    name = exercise_name.lower().replace('ё', 'е')
    for club in CLUBS:
        includes = [i.replace('ё', 'е') for i in club.include]
        if any(i in name for i in includes) and not any(x in name for x in club.exclude):
            return club
    return None


def club_code(club: Club, threshold: int) -> str:
    return f'club_{club.key}_{threshold}'


def club_title(code: str) -> str | None:
    for club in CLUBS:
        for threshold in club.thresholds:
            if club_code(club, threshold) == code:
                return f'Клуб {threshold} кг: {club.title.lower()}'
    return None


def best_lift_by_club(exercise_records: dict) -> dict[str, float]:
    """Лучший вес по каждому клубу из снимков рекордов упражнений."""
    best: dict[str, float] = {}
    for snapshot in exercise_records.values():
        club = club_for(snapshot.exercise_name)
        if club is not None:
            best[club.key] = max(best.get(club.key, 0.0), snapshot.best_weight)
    return best

