from tests.conftest import API


def test_register_login_and_me(client, register):
    headers = register('athlete@example.com')

    me = client.get(f'{API}/auth/me', headers=headers)
    assert me.status_code == 200
    assert me.json()['email'] == 'athlete@example.com'

    login = client.post(
        f'{API}/auth/login',
        data={'username': 'athlete@example.com', 'password': 'secret-pass-1'},
    )
    assert login.status_code == 200
    assert login.json()['access_token']


def test_duplicate_registration_is_rejected(client, register):
    register('athlete@example.com')
    response = client.post(
        f'{API}/auth/register',
        json={'email': 'athlete@example.com', 'password': 'secret-pass-1'},
    )
    assert response.status_code == 409


def test_wrong_password_and_missing_token(client, register):
    register('athlete@example.com')
    wrong = client.post(
        f'{API}/auth/login',
        data={'username': 'athlete@example.com', 'password': 'not-the-password'},
    )
    assert wrong.status_code == 401
    assert client.get(f'{API}/workouts').status_code == 401


def test_short_password_is_rejected(client):
    response = client.post(f'{API}/auth/register', json={'email': 'a@example.com', 'password': 'short'})
    assert response.status_code == 422
