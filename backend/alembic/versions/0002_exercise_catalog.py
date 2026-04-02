"""add exercise catalog and links

Revision ID: 0002_exercise_catalog
Revises: 0001_initial
Create Date: 2026-03-09
"""

from alembic import op
import sqlalchemy as sa


revision = '0002_exercise_catalog'
down_revision = '0001_initial'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'exercise_catalog',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=120), nullable=False),
        sa.Column('primary_muscle', sa.String(length=40), nullable=False),
        sa.Column('secondary_muscles', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_exercise_catalog_user_id', 'exercise_catalog', ['user_id'], unique=False)

    op.add_column('workout_exercises', sa.Column('catalog_exercise_id', sa.Integer(), nullable=True))
    op.create_index('ix_workout_exercises_catalog_exercise_id', 'workout_exercises', ['catalog_exercise_id'], unique=False)
    op.create_foreign_key(
        'fk_workout_exercises_catalog_exercise_id',
        'workout_exercises',
        'exercise_catalog',
        ['catalog_exercise_id'],
        ['id'],
        ondelete='SET NULL',
    )

    op.add_column('workout_template_exercises', sa.Column('catalog_exercise_id', sa.Integer(), nullable=True))
    op.create_index(
        'ix_workout_template_exercises_catalog_exercise_id',
        'workout_template_exercises',
        ['catalog_exercise_id'],
        unique=False,
    )
    op.create_foreign_key(
        'fk_workout_template_exercises_catalog_exercise_id',
        'workout_template_exercises',
        'exercise_catalog',
        ['catalog_exercise_id'],
        ['id'],
        ondelete='SET NULL',
    )


def downgrade() -> None:
    op.drop_constraint('fk_workout_template_exercises_catalog_exercise_id', 'workout_template_exercises', type_='foreignkey')
    op.drop_index('ix_workout_template_exercises_catalog_exercise_id', table_name='workout_template_exercises')
    op.drop_column('workout_template_exercises', 'catalog_exercise_id')

    op.drop_constraint('fk_workout_exercises_catalog_exercise_id', 'workout_exercises', type_='foreignkey')
    op.drop_index('ix_workout_exercises_catalog_exercise_id', table_name='workout_exercises')
    op.drop_column('workout_exercises', 'catalog_exercise_id')

    op.drop_index('ix_exercise_catalog_user_id', table_name='exercise_catalog')
    op.drop_table('exercise_catalog')
