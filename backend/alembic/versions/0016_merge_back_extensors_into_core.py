"""merge back extensors into core

Revision ID: 0016_merge_back_extensors_core
Revises: 0015_user_profile
Create Date: 2026-04-27
"""

from alembic import op
import sqlalchemy as sa


revision = '0016_merge_back_extensors_core'
down_revision = '0015_user_profile'
branch_labels = None
depends_on = None

CORE_MUSCLE = 'кор'
MUSCLE_ALIASES = {
    'разгибатель_спины': CORE_MUSCLE,
    'поясница': CORE_MUSCLE,
}


def _canonicalize_muscle(value: str) -> str:
    return MUSCLE_ALIASES.get(value.strip(), value.strip())


def upgrade() -> None:
    connection = op.get_bind()

    connection.execute(
        sa.text(
            'UPDATE exercise_catalog '
            'SET primary_muscle = :core '
            'WHERE primary_muscle IN :aliases'
        ).bindparams(sa.bindparam('aliases', expanding=True)),
        {'core': CORE_MUSCLE, 'aliases': tuple(MUSCLE_ALIASES)},
    )

    exercise_rows = connection.execute(
        sa.text('SELECT id, primary_muscle FROM exercise_catalog')
    ).mappings()
    primary_by_exercise_id = {
        int(row['id']): _canonicalize_muscle(str(row['primary_muscle'] or ''))
        for row in exercise_rows
    }

    link_rows = connection.execute(
        sa.text(
            'SELECT id, exercise_id, muscle, position '
            'FROM exercise_secondary_muscles '
            'ORDER BY exercise_id, position, id'
        )
    ).mappings()

    seen_by_exercise_id: dict[int, set[str]] = {}
    next_position_by_exercise_id: dict[int, int] = {}

    for row in link_rows:
        link_id = int(row['id'])
        exercise_id = int(row['exercise_id'])
        muscle = _canonicalize_muscle(str(row['muscle'] or ''))
        primary = primary_by_exercise_id.get(exercise_id, '')
        seen = seen_by_exercise_id.setdefault(exercise_id, set())

        if not muscle or muscle == primary or muscle in seen:
            connection.execute(
                sa.text('DELETE FROM exercise_secondary_muscles WHERE id = :id'),
                {'id': link_id},
            )
            continue

        seen.add(muscle)
        next_position = next_position_by_exercise_id.get(exercise_id, 1)
        next_position_by_exercise_id[exercise_id] = next_position + 1

        if muscle != row['muscle'] or next_position != row['position']:
            connection.execute(
                sa.text(
                    'UPDATE exercise_secondary_muscles '
                    'SET muscle = :muscle, position = :position '
                    'WHERE id = :id'
                ),
                {'id': link_id, 'muscle': muscle, 'position': next_position},
            )


def downgrade() -> None:
    pass
