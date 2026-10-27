from tests.conftest import API, workout_payload


def _log(client, headers, day: str, weight: float, *, finished: bool = True, sets: int = 3):
    response = client.post(
        f'{API}/workouts',
        json=workout_payload(
            started_at=f'{day}T18:00:00+00:00',
            finished_at=f'{day}T19:00:00+00:00' if finished else None,
            sets=tuple((weight, 8) for _ in range(sets)),
        ),
        headers=headers,
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_finished_workouts_earn_xp_and_records(client, register):
    headers = register('athlete@example.com')
    _log(client, headers, '2026-10-06', 80)
    _log(client, headers, '2026-10-13', 85)

    data = client.get(f'{API}/progression/profile', headers=headers).json()
    profile = data['profile']
    assert profile['totalCompletedWorkouts'] == 2
    assert profile['totalXp'] > 0

    squat = next(r for r in data['allExerciseRecords'] if r['exerciseName'] == 'Присед')
    assert squat['bestWeight'] == 85


def test_drafts_do_not_count_until_finished(client, register):
    headers = register('athlete@example.com')
    _log(client, headers, '2026-10-06', 80, finished=False)

    profile = client.get(f'{API}/progression/profile', headers=headers).json()['profile']
    assert profile['totalCompletedWorkouts'] == 0


def test_deleting_a_workout_recalculates_records(client, register):
    headers = register('athlete@example.com')
    _log(client, headers, '2026-10-06', 80)
    heavy = _log(client, headers, '2026-10-13', 100)

    assert client.delete(f"{API}/workouts/{heavy['id']}", headers=headers).status_code == 204

    data = client.get(f'{API}/progression/profile', headers=headers).json()
    assert data['profile']['totalCompletedWorkouts'] == 1
    squat = next(r for r in data['allExerciseRecords'] if r['exerciseName'] == 'Присед')
    assert squat['bestWeight'] == 80


def test_too_short_workouts_do_not_count(client, register):
    # Засчитывается тренировка от 3 рабочих подходов или от 2 упражнений.
    headers = register('athlete@example.com')
    _log(client, headers, '2026-10-06', 80, sets=2)

    profile = client.get(f'{API}/progression/profile', headers=headers).json()['profile']
    assert profile['totalCompletedWorkouts'] == 0
