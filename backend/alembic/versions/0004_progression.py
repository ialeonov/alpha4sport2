"""progression and gamification

Revision ID: 0004_progression
Revises: 0003_catalog_slug_and_secondary_table
Create Date: 2026-03-20
"""

from alembic import op
import sqlalchemy as sa


revision = '0004_progression'
down_revision = '0003_catalog_slug_secondary'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'user_progressions',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('total_xp', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('current_streak', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('best_streak', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_completed_workouts', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_pr_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('ideal_weeks_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('ideal_months_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_calculated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id'),
    )

    op.create_table(
        'progress_achievements',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('code', sa.String(length=80), nullable=False),
        sa.Column('achieved_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('metadata_json', sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'code', name='uq_progress_achievement_user_code'),
    )
    op.create_index('ix_progress_achievements_user_id', 'progress_achievements', ['user_id'], unique=False)

    op.create_table(
        'progress_reward_events',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('event_key', sa.String(length=160), nullable=False),
        sa.Column('event_type', sa.String(length=80), nullable=False),
        sa.Column('xp_awarded', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('metadata_json', sa.JSON(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'event_key', name='uq_progress_reward_event_user_key'),
    )
    op.create_index('ix_progress_reward_events_user_id', 'progress_reward_events', ['user_id'], unique=False)

    op.create_table(
        'progress_exercise_records',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('exercise_key', sa.String(length=160), nullable=False),
        sa.Column('exercise_name', sa.String(length=120), nullable=False),
        sa.Column('catalog_exercise_id', sa.Integer(), nullable=True),
        sa.Column('best_weight', sa.Float(), nullable=False, server_default='0'),
        sa.Column('best_1rm', sa.Float(), nullable=False, server_default='0'),
        sa.Column('best_volume', sa.Float(), nullable=False, server_default='0'),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['catalog_exercise_id'], ['exercise_catalog.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'exercise_key', name='uq_progress_record_user_exercise'),
    )
    op.create_index('ix_progress_exercise_records_user_id', 'progress_exercise_records', ['user_id'], unique=False)
    op.create_index(
        'ix_progress_exercise_records_catalog_exercise_id',
        'progress_exercise_records',
        ['catalog_exercise_id'],
        unique=False,
    )

    op.create_table(
        'progress_record_events',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('workout_id', sa.Integer(), nullable=False),
        sa.Column('exercise_key', sa.String(length=160), nullable=False),
        sa.Column('exercise_name', sa.String(length=120), nullable=False),
        sa.Column('record_type', sa.String(length=40), nullable=False),
        sa.Column('value', sa.Float(), nullable=False),
        sa.Column('achieved_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['workout_id'], ['workouts.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'user_id',
            'workout_id',
            'exercise_key',
            'record_type',
            name='uq_progress_record_event_identity',
        ),
    )
    op.create_index('ix_progress_record_events_user_id', 'progress_record_events', ['user_id'], unique=False)
    op.create_index('ix_progress_record_events_workout_id', 'progress_record_events', ['workout_id'], unique=False)

    op.create_table(
        'sick_leaves',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('start_date', sa.Date(), nullable=False),
        sa.Column('end_date', sa.Date(), nullable=False),
        sa.Column('reason', sa.String(length=32), nullable=False),
        sa.Column('status', sa.String(length=16), nullable=False, server_default='active'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_sick_leaves_user_id', 'sick_leaves', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_sick_leaves_user_id', table_name='sick_leaves')
    op.drop_table('sick_leaves')

    op.drop_index('ix_progress_record_events_workout_id', table_name='progress_record_events')
    op.drop_index('ix_progress_record_events_user_id', table_name='progress_record_events')
    op.drop_table('progress_record_events')

    op.drop_index(
        'ix_progress_exercise_records_catalog_exercise_id',
        table_name='progress_exercise_records',
    )
    op.drop_index('ix_progress_exercise_records_user_id', table_name='progress_exercise_records')
    op.drop_table('progress_exercise_records')

    op.drop_index('ix_progress_reward_events_user_id', table_name='progress_reward_events')
    op.drop_table('progress_reward_events')

    op.drop_index('ix_progress_achievements_user_id', table_name='progress_achievements')
    op.drop_table('progress_achievements')

    op.drop_table('user_progressions')
