import json
import re
from pathlib import Path

from sqlalchemy import Select, or_, select
from sqlalchemy.orm import Session, selectinload

from app.models.workout import ExerciseCatalog, ExerciseSecondaryMuscle

CATALOG_JSON_PATH = Path(__file__).resolve().parents[2] / 'docs' / 'fit_catalog.json'

_CYRILLIC_TO_LATIN = str.maketrans(
    {
        'а': 'a',
        'б': 'b',
        'в': 'v',
        'г': 'g',
        'д': 'd',
        'е': 'e',
        'ё': 'e',
        'ж': 'zh',
        'з': 'z',
        'и': 'i',
        'й': 'y',
        'к': 'k',
        'л': 'l',
        'м': 'm',
        'н': 'n',
        'о': 'o',
        'п': 'p',
        'р': 'r',
        'с': 's',
        'т': 't',
        'у': 'u',
        'ф': 'f',
        'х': 'h',
        'ц': 'ts',
        'ч': 'ch',
        'ш': 'sh',
        'щ': 'sch',
        'ъ': '',
        'ы': 'y',
        'ь': '',
        'э': 'e',
        'ю': 'yu',
        'я': 'ya',
    }
)
_SLUG_SANITIZER = re.compile(r'[^a-z0-9]+')


def list_catalog_exercises_stmt(user_id: int) -> Select[tuple[ExerciseCatalog]]:
    return (
        select(ExerciseCatalog)
        .options(selectinload(ExerciseCatalog.secondary_muscle_links))
        .where(ExerciseCatalog.user_id == user_id)
        .order_by(ExerciseCatalog.name.asc(), ExerciseCatalog.id.asc())
    )


def normalize_slug(value: str) -> str:
    transliterated = value.strip().lower().translate(_CYRILLIC_TO_LATIN)
    normalized = _SLUG_SANITIZER.sub('_', transliterated).strip('_')
    return normalized or 'exercise'


def validate_muscles(primary_muscle: str, secondary_muscles: list[str]) -> list[str]:
    primary = primary_muscle.strip()
    if not primary:
        raise ValueError('Primary muscle is required')

    cleaned: list[str] = []
    seen: set[str] = set()
    for value in secondary_muscles:
        muscle = value.strip()
        if not muscle or muscle == primary or muscle in seen:
            continue
        seen.add(muscle)
        cleaned.append(muscle)
    return cleaned


def slug_exists(db: Session, user_id: int, slug: str, exclude_id: int | None = None) -> bool:
    stmt = select(ExerciseCatalog.id).where(
        ExerciseCatalog.user_id == user_id,
        ExerciseCatalog.slug == slug,
    )
    if exclude_id is not None:
        stmt = stmt.where(ExerciseCatalog.id != exclude_id)
    return db.scalar(stmt) is not None


def build_unique_slug(db: Session, user_id: int, name: str, exclude_id: int | None = None) -> str:
    base_slug = normalize_slug(name)
    candidate = base_slug
    suffix = 2
    while slug_exists(db, user_id, candidate, exclude_id=exclude_id):
        candidate = f'{base_slug}_{suffix}'
        suffix += 1
    return candidate


def load_seed_catalog() -> list[dict[str, object]]:
    payload = json.loads(CATALOG_JSON_PATH.read_text(encoding='utf-8'))
    exercises = payload.get('exercises')
    if not isinstance(exercises, list):
        raise ValueError('Некорректный формат сид-данных каталога упражнений')

    seen_slugs: set[str] = set()
    normalized_exercises: list[dict[str, object]] = []

    for raw_exercise in exercises:
        if not isinstance(raw_exercise, dict):
            raise ValueError('Некорректная запись упражнения в сид-данных')

        name = str(raw_exercise.get('name', '')).strip()
        slug = str(raw_exercise.get('slug', '')).strip()
        primary_muscle = str(raw_exercise.get('primary_muscle', '')).strip()
        secondary_values = [str(value).strip() for value in raw_exercise.get('secondary_muscles', [])]

        if not name or not slug:
            raise ValueError('Каждое упражнение должно содержать name и slug')
        if slug in seen_slugs:
            raise ValueError(f'Найден повторяющийся slug в сид-данных: {slug}')
        seen_slugs.add(slug)

        normalized_exercises.append(
            {
                'name': name,
                'slug': slug,
                'primary_muscle': primary_muscle,
                'secondary_muscles': validate_muscles(primary_muscle, secondary_values),
            }
        )

    return normalized_exercises


def ensure_seed_catalog(db: Session, user_id: int) -> int:
    seed_catalog = load_seed_catalog()
    existing_exercises = list(db.scalars(list_catalog_exercises_stmt(user_id)))
    by_slug = {exercise.slug: exercise for exercise in existing_exercises}
    created = 0
    changed = False

    for item in seed_catalog:
        slug = str(item['slug'])
        name = str(item['name'])
        primary_muscle = str(item['primary_muscle'])
        secondary_muscles = list(item['secondary_muscles'])

        exercise = by_slug.get(slug)

        if exercise is None:
            exercise = ExerciseCatalog(
                user_id=user_id,
                slug=slug if not slug_exists(db, user_id, slug) else build_unique_slug(db, user_id, name),
                name=name,
                primary_muscle=primary_muscle,
            )
            db.add(exercise)
            existing_exercises.append(exercise)
            created += 1
            changed = True
        else:
            if exercise.name == name and exercise.slug != slug and not slug_exists(db, user_id, slug, exclude_id=exercise.id):
                exercise.slug = slug
                changed = True
            if not exercise.primary_muscle.strip():
                exercise.primary_muscle = primary_muscle
                changed = True
            if not exercise.name.strip():
                exercise.name = name
                changed = True

        if exercise.slug == slug and exercise.name != name:
            exercise.name = name
            changed = True
        if exercise.primary_muscle != primary_muscle:
            exercise.primary_muscle = primary_muscle
            changed = True
        current_secondary = [link.muscle for link in exercise.secondary_muscle_links]
        if current_secondary != secondary_muscles:
            exercise.secondary_muscle_links = [
                ExerciseSecondaryMuscle(muscle=muscle, position=index + 1)
                for index, muscle in enumerate(secondary_muscles)
            ]
            changed = True
        by_slug[exercise.slug] = exercise

    if changed:
        db.commit()
    return created


def serialize_exercise_catalog(exercise: ExerciseCatalog) -> dict[str, object]:
    secondary = [link.muscle for link in exercise.secondary_muscle_links]
    return {
        'id': exercise.id,
        'name': exercise.name,
        'slug': exercise.slug,
        'primary_muscle': exercise.primary_muscle,
        'secondary_muscles': secondary,
    }
