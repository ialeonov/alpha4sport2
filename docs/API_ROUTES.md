# API routes (v1)

Base prefix: `/api/v1`

## Auth
- `POST /auth/bootstrap?email=&password=` create first personal account
- `POST /auth/login` get JWT token (OAuth2 password form)
- `GET /auth/me` current user

## Workouts
- `POST /workouts` create workout with exercises/sets
- `GET /workouts` list workouts
- `POST /workouts/from-template/{template_id}` start workout from template
- `GET /workouts/previous/{exercise_name}?limit=5` recent values for selected exercise
- `GET /workouts/{workout_id}` workout details
- `PUT /workouts/{workout_id}` edit workout
- `DELETE /workouts/{workout_id}` delete workout

## Templates
- `POST /templates` create template
- `GET /templates` list templates
- `PUT /templates/{template_id}` edit template
- `DELETE /templates/{template_id}` delete template

## Body tracking
- `POST /body` create body entry
- `GET /body` list entries
- `DELETE /body/{entry_id}` delete entry

## Progress
- `GET /progress/exercise/{exercise_name}` history for chart
- `GET /progress/weekly-volume` weekly volume aggregate
- `GET /progress/bodyweight-trend?days=90` bodyweight trend

## Export
- `GET /export/json` full data export
