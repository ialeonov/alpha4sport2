"""initial schema

Revision ID: 0001_initial
Revises:
Create Date: 2026-03-09
"""

from alembic import op
import sqlalchemy as sa


revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(length=320), nullable=False),
        sa.Column('hashed_password', sa.String(length=255), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.text('true')),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_users_id'), 'users', ['id'], unique=False)
    op.create_index(op.f('ix_users_email'), 'users', ['email'], unique=True)

    op.create_table(
        'workouts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=120), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('started_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('finished_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_workouts_user_id', 'workouts', ['user_id'], unique=False)

    op.create_table(
        'workout_exercises',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('workout_id', sa.Integer(), nullable=False),
        sa.Column('exercise_name', sa.String(length=120), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['workout_id'], ['workouts.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_workout_exercises_workout_id', 'workout_exercises', ['workout_id'], unique=False)
    op.create_index('ix_workout_exercises_exercise_name', 'workout_exercises', ['exercise_name'], unique=False)

    op.create_table(
        'exercise_sets',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('workout_exercise_id', sa.Integer(), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('reps', sa.Integer(), nullable=False),
        sa.Column('weight', sa.Float(), nullable=True),
        sa.Column('rpe', sa.Float(), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['workout_exercise_id'], ['workout_exercises.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_exercise_sets_workout_exercise_id', 'exercise_sets', ['workout_exercise_id'], unique=False)

    op.create_table(
        'workout_templates',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=120), nullable=False),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_workout_templates_user_id', 'workout_templates', ['user_id'], unique=False)

    op.create_table(
        'workout_template_exercises',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('template_id', sa.Integer(), nullable=False),
        sa.Column('exercise_name', sa.String(length=120), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('target_sets', sa.Integer(), nullable=False),
        sa.Column('target_reps', sa.String(length=40), nullable=True),
        sa.ForeignKeyConstraint(['template_id'], ['workout_templates.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_workout_template_exercises_template_id', 'workout_template_exercises', ['template_id'], unique=False)

    op.create_table(
        'body_entries',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('entry_date', sa.Date(), nullable=False),
        sa.Column('weight_kg', sa.Float(), nullable=True),
        sa.Column('waist_cm', sa.Float(), nullable=True),
        sa.Column('chest_cm', sa.Float(), nullable=True),
        sa.Column('hips_cm', sa.Float(), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('photo_path', sa.String(length=500), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_body_entries_user_id', 'body_entries', ['user_id'], unique=False)
    op.create_index('ix_body_entries_entry_date', 'body_entries', ['entry_date'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_body_entries_entry_date', table_name='body_entries')
    op.drop_index('ix_body_entries_user_id', table_name='body_entries')
    op.drop_table('body_entries')

    op.drop_index('ix_workout_template_exercises_template_id', table_name='workout_template_exercises')
    op.drop_table('workout_template_exercises')

    op.drop_index('ix_workout_templates_user_id', table_name='workout_templates')
    op.drop_table('workout_templates')

    op.drop_index('ix_exercise_sets_workout_exercise_id', table_name='exercise_sets')
    op.drop_table('exercise_sets')

    op.drop_index('ix_workout_exercises_exercise_name', table_name='workout_exercises')
    op.drop_index('ix_workout_exercises_workout_id', table_name='workout_exercises')
    op.drop_table('workout_exercises')

    op.drop_index('ix_workouts_user_id', table_name='workouts')
    op.drop_table('workouts')

    op.drop_index(op.f('ix_users_email'), table_name='users')
    op.drop_index(op.f('ix_users_id'), table_name='users')
    op.drop_table('users')
