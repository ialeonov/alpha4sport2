from tests.conftest import API, workout_payload


def test_create_list_get_update_delete(client, register):
    headers = register('athlete@example.com')

    created = client.post(f'{API}/workouts', json=workout_payload(), headers=headers)
    assert created.status_code == 200, created.text
    workout = created.json()
    assert workout['name'] == 'Ноги'
    assert [s['weight'] for s in workout['exercises'][0]['sets']] == [80, 80]

    listed = client.get(f'{API}/workouts', headers=headers).json()
    assert [w['id'] for w in listed] == [workout['id']]

    fetched = client.get(f"{API}/workouts/{workout['id']}", headers=headers)
    assert fetched.status_code == 200

    updated = client.put(
        f"{API}/workouts/{workout['id']}",
        json=workout_payload(name='Ноги + плечи', sets=((85, 6),)),
        headers=headers,
    )
    assert updated.status_code == 200, updated.text
    body = updated.json()
    assert body['name'] == 'Ноги + плечи'
    assert [(s['weight'], s['reps']) for s in body['exercises'][0]['sets']] == [(85, 6)]

    deleted = client.delete(f"{API}/workouts/{workout['id']}", headers=headers)
    assert deleted.status_code == 204
    assert client.get(f'{API}/workouts', headers=headers).json() == []


def test_unfinished_workout_is_a_draft(client, register):
    headers = register('athlete@example.com')
    created = client.post(f'{API}/workouts', json=workout_payload(finished_at=None), headers=headers)
    assert created.status_code == 200, created.text
    assert created.json()['finished_at'] is None


def test_users_do_not_see_each_others_workouts(client, register):
    alice = register('alice@example.com')
    bob = register('bob@example.com')
    workout = client.post(f'{API}/workouts', json=workout_payload(), headers=alice).json()

    assert client.get(f'{API}/workouts', headers=bob).json() == []
    assert client.get(f"{API}/workouts/{workout['id']}", headers=bob).status_code == 404
    assert client.put(
        f"{API}/workouts/{workout['id']}", json=workout_payload(), headers=bob
    ).status_code == 404
    assert client.delete(f"{API}/workouts/{workout['id']}", headers=bob).status_code == 404


def test_list_filters_by_date_range(client, register):
    headers = register('athlete@example.com')
    for day in ('2026-09-10', '2026-10-05', '2026-10-20'):
        response = client.post(
            f'{API}/workouts',
            json=workout_payload(started_at=f'{day}T18:00:00+00:00', finished_at=f'{day}T19:00:00+00:00'),
            headers=headers,
        )
        assert response.status_code == 200, response.text

    october = client.get(
        f'{API}/workouts',
        params={'from_date': '2026-10-01', 'to_date': '2026-10-31'},
        headers=headers,
    ).json()
    assert sorted(w['started_at'][:10] for w in october) == ['2026-10-05', '2026-10-20']

    days = client.get(f'{API}/workouts/days', headers=headers).json()
    assert len(days) == 3


def test_invalid_workouts_are_rejected(client, register):
    headers = register('athlete@example.com')

    backwards = workout_payload(
        started_at='2026-10-20T19:00:00+00:00', finished_at='2026-10-20T18:00:00+00:00'
    )
    assert client.post(f'{API}/workouts', json=backwards, headers=headers).status_code == 422

    negative = workout_payload(sets=((-5, 8),))
    assert client.post(f'{API}/workouts', json=negative, headers=headers).status_code == 422

    bad_type = workout_payload()
    bad_type['exercises'][0]['sets'][0]['set_type'] = 'drop'
    assert client.post(f'{API}/workouts', json=bad_type, headers=headers).status_code == 422
