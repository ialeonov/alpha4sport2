"""Общая настройка тестов API: отдельная SQLite-база на прогон, чистые
таблицы на каждый тест, без обращений к AI-провайдеру."""

import os
import tempfile
from collections.abc import Callable

_TMP_DIR = tempfile.mkdtemp(prefix='alpha4sport-tests-')
os.environ['DATABASE_URL'] = f'sqlite:///{_TMP_DIR}/test.db'
os.environ['UPLOAD_DIR'] = f'{_TMP_DIR}/uploads'
os.environ['SECRET_KEY'] = 'test-secret'
os.environ['AI_COACH_API_KEY'] = ''
os.environ['AI_COACH_MODEL'] = ''

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import app.models  # noqa: E402,F401  — регистрирует все таблицы
from app.db.session import Base, engine  # noqa: E402
from app.main import app  # noqa: E402

API = '/api/v1'


@pytest.fixture(autouse=True)
def clean_db():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture
def register(client: TestClient) -> Callable[[str], dict[str, str]]:
    """Регистрирует пользователя и возвращает заголовки с его токеном."""

    def _register(email: str, password: str = 'secret-pass-1') -> dict[str, str]:
        response = client.post(f'{API}/auth/register', json={'email': email, 'password': password})
        assert response.status_code == 201, response.text
        return {'Authorization': f"Bearer {response.json()['access_token']}"}

    return _register


def workout_payload(
    *,
    name: str = 'Ноги',
    started_at: str = '2026-10-20T18:00:00+00:00',
    finished_at: str | None = '2026-10-20T19:00:00+00:00',
    sets: tuple[tuple[float | None, int], ...] = ((80, 8), (80, 8)),
    exercise_name: str = 'Присед',
) -> dict:
    return {
        'name': name,
        'notes': None,
        'started_at': started_at,
        'finished_at': finished_at,
        'exercises': [
            {
                'exercise_name': exercise_name,
                'position': 1,
                'sets': [
                    {'position': i + 1, 'reps': reps, 'weight': weight, 'set_type': 'work'}
                    for i, (weight, reps) in enumerate(sets)
                ],
            }
        ],
    }
