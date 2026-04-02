# Database schema (v1)

## users
- id (PK)
- email (unique)
- hashed_password
- is_active
- created_at

## workouts
- id (PK)
- user_id (FK users.id)
- name
- notes
- started_at
- finished_at
- created_at

## workout_exercises
- id (PK)
- workout_id (FK workouts.id)
- exercise_name
- position
- notes

## exercise_sets
- id (PK)
- workout_exercise_id (FK workout_exercises.id)
- position
- reps
- weight
- rpe
- notes

## workout_templates
- id (PK)
- user_id (FK users.id)
- name
- notes

## workout_template_exercises
- id (PK)
- template_id (FK workout_templates.id)
- exercise_name
- position
- target_sets
- target_reps

## body_entries
- id (PK)
- user_id (FK users.id)
- entry_date
- weight_kg
- waist_cm
- chest_cm
- hips_cm
- notes
- photo_path
- created_at
