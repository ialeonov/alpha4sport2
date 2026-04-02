"""add slug and secondary muscles table

Revision ID: 0003_catalog_slug_secondary
Revises: 0002_exercise_catalog
Create Date: 2026-03-11
"""

from alembic import op
import sqlalchemy as sa


revision = '0003_catalog_slug_secondary'
down_revision = '0002_exercise_catalog'
branch_labels = None
depends_on = None

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


def _normalize_slug(value: str) -> str:
    normalized = value.strip().lower().translate(_CYRILLIC_TO_LATIN)
    slug_chars: list[str] = []
    previous_was_separator = False
    for char in normalized:
        if char.isascii() and char.isalnum():
            slug_chars.append(char)
            previous_was_separator = False
            continue
        if previous_was_separator:
            continue
        slug_chars.append('_')
        previous_was_separator = True

    slug = ''.join(slug_chars).strip('_')
    return slug or 'exercise'


def upgrade() -> None:
    op.add_column('exercise_catalog', sa.Column('slug', sa.String(length=160), nullable=True))
    op.create_table(
        'exercise_secondary_muscles',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('exercise_id', sa.Integer(), nullable=False),
        sa.Column('muscle', sa.String(length=40), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['exercise_id'], ['exercise_catalog.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(
        'ix_exercise_secondary_muscles_exercise_id',
        'exercise_secondary_muscles',
        ['exercise_id'],
        unique=False,
    )

    connection = op.get_bind()
    rows = connection.execute(
        sa.text('SELECT id, user_id, name, secondary_muscles FROM exercise_catalog ORDER BY user_id, id')
    ).mappings()

    used_slugs: dict[int, set[str]] = {}
    for row in rows:
        user_id = int(row['user_id'])
        base_slug = _normalize_slug(row['name'] or '')
        slug = base_slug
        suffix = 2
        user_slugs = used_slugs.setdefault(user_id, set())
        while slug in user_slugs:
            slug = f'{base_slug}_{suffix}'
            suffix += 1
        user_slugs.add(slug)

        connection.execute(
            sa.text('UPDATE exercise_catalog SET slug = :slug WHERE id = :exercise_id'),
            {'slug': slug, 'exercise_id': row['id']},
        )

        secondary_muscles = row['secondary_muscles'] or ''
        for index, muscle in enumerate((value.strip() for value in secondary_muscles.split(',')), start=1):
            if not muscle:
                continue
            connection.execute(
                sa.text(
                    'INSERT INTO exercise_secondary_muscles (exercise_id, muscle, position) '
                    'VALUES (:exercise_id, :muscle, :position)'
                ),
                {'exercise_id': row['id'], 'muscle': muscle, 'position': index},
            )

    op.alter_column('exercise_catalog', 'slug', existing_type=sa.String(length=160), nullable=False)
    op.create_unique_constraint('uq_exercise_catalog_user_slug', 'exercise_catalog', ['user_id', 'slug'])
    op.drop_column('exercise_catalog', 'secondary_muscles')


def downgrade() -> None:
    op.add_column('exercise_catalog', sa.Column('secondary_muscles', sa.Text(), nullable=True))

    connection = op.get_bind()
    rows = connection.execute(
        sa.text(
            'SELECT exercise_id, muscle FROM exercise_secondary_muscles '
            'ORDER BY exercise_id, position, id'
        )
    ).mappings()

    grouped: dict[int, list[str]] = {}
    for row in rows:
        grouped.setdefault(int(row['exercise_id']), []).append(str(row['muscle']))

    for exercise_id, muscles in grouped.items():
        connection.execute(
            sa.text('UPDATE exercise_catalog SET secondary_muscles = :secondary WHERE id = :exercise_id'),
            {'secondary': ','.join(muscles), 'exercise_id': exercise_id},
        )

    op.drop_constraint('uq_exercise_catalog_user_slug', 'exercise_catalog', type_='unique')
    op.drop_index('ix_exercise_secondary_muscles_exercise_id', table_name='exercise_secondary_muscles')
    op.drop_table('exercise_secondary_muscles')
    op.drop_column('exercise_catalog', 'slug')
