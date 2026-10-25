"""Нагрузка на мышцы в «эффективных подходах».

Та же модель, что у тепловой карты в приложении
(frontend/lib/features/heatmap/domain/muscle_load_calculator.dart), чтобы
AI-коуч видел те же цифры, что и пользователь на вкладке «Мышцы».
"""

from __future__ import annotations

from collections.abc import Iterable

from app.models.workout import ExerciseCatalog, Workout

_CORE = 'кор'
_CORE_ALIASES = {'разгибатель_спины', 'поясница'}
_PRIMARY_FACTOR = 1.0
_SECONDARY_FACTOR = 0.5
_STABILIZER_FACTOR = 0.2


def _canonical(muscle: str | None) -> str:
    value = (muscle or '').strip()
    return _CORE if value in _CORE_ALIASES else value


def estimate_1rm(weight: float, reps: float) -> float:
    return weight if reps <= 1 else weight * (1 + reps / 30)


def session_diminishing_returns(sets: float) -> float:
    if sets <= 6:
        return sets
    if sets <= 10:
        return 6 + (sets - 6) * 0.7
    return 8.8 + (sets - 10) * 0.4


def _intensity_factor(weight: float | None, reps: float, rpe: float | None, best: float) -> float:
    if rpe:
        if rpe >= 8:
            return 1.0
        if rpe >= 7:
            return 0.85
        if rpe >= 6:
            return 0.65
        return 0.45
    if not weight or best <= 0:
        return 1.0
    ratio = estimate_1rm(weight, reps) / best
    if ratio >= 0.9:
        return 1.0
    if ratio <= 0.65:
        return 0.3
    return 0.3 + (ratio - 0.65) / 0.25 * 0.7


def _rep_factor(reps: float) -> float:
    if reps <= 3:
        return 0.75
    if reps <= 30:
        return 1.0
    return 0.7


class MuscleLoadCalculator:
    def __init__(self, catalog: Iterable[ExerciseCatalog]):
        self._by_id: dict[int, ExerciseCatalog] = {}
        self._by_name: dict[str, ExerciseCatalog] = {}
        for item in catalog:
            self._by_id[item.id] = item
            self._by_name[_normalize(item.name)] = item

    def _resolve(self, catalog_id: int | None, name: str) -> ExerciseCatalog | None:
        if catalog_id is not None and catalog_id in self._by_id:
            return self._by_id[catalog_id]
        return self._by_name.get(_normalize(name))

    def best_e1rm(self, workouts: Iterable[Workout]) -> dict[str, float]:
        best: dict[str, float] = {}
        for workout in workouts:
            for exercise in workout.exercises:
                key = _normalize(exercise.exercise_name)
                for s in exercise.sets:
                    if s.set_type == 'warmup' or not s.weight or s.reps <= 0 or s.reps > 30:
                        continue
                    best[key] = max(best.get(key, 0.0), estimate_1rm(float(s.weight), s.reps))
        return best

    def workout_loads(self, workout: Workout, best_e1rm: dict[str, float]) -> dict[str, float]:
        raw: dict[str, float] = {}
        for exercise in workout.exercises:
            entry = self._resolve(exercise.catalog_exercise_id, exercise.exercise_name)
            if entry is None:
                continue
            primary = _canonical(entry.primary_muscle)
            secondary: list[str] = []
            for link in entry.secondary_muscle_links:
                muscle = _canonical(link.muscle)
                if muscle and muscle != primary and muscle not in secondary:
                    secondary.append(muscle)
            best = best_e1rm.get(_normalize(exercise.exercise_name), 0.0)
            for s in exercise.sets:
                if s.set_type == 'warmup' or s.reps <= 0:
                    continue
                score = _rep_factor(s.reps) * _intensity_factor(
                    float(s.weight) if s.weight else None, s.reps, s.rpe, best
                )
                if primary:
                    raw[primary] = raw.get(primary, 0.0) + score * _PRIMARY_FACTOR
                for muscle in secondary:
                    factor = _STABILIZER_FACTOR if muscle == _CORE else _SECONDARY_FACTOR
                    raw[muscle] = raw.get(muscle, 0.0) + score * factor
        return {muscle: session_diminishing_returns(value) for muscle, value in raw.items()}

    def total_loads(
        self, workouts: list[Workout], reference: list[Workout] | None = None
    ) -> dict[str, float]:
        best = self.best_e1rm([*(reference or []), *workouts])
        totals: dict[str, float] = {}
        for workout in workouts:
            for muscle, value in self.workout_loads(workout, best).items():
                totals[muscle] = totals.get(muscle, 0.0) + value
        return totals


def _normalize(name: str | None) -> str:
    return (name or '').strip().lower().replace('ё', 'е')
