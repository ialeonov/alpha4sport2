"""pr reps record

Revision ID: 0012_pr_reps
Revises: 0011_coach_chat_messages
Create Date: 2026-04-10
"""

import sqlalchemy as sa
from alembic import op

revision = '0012_pr_reps'
down_revision = '0011_coach_chat_messages'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('progress_exercise_records', sa.Column('best_reps', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('progress_exercise_records', sa.Column('best_reps_weight', sa.Float(), nullable=False, server_default='0'))


def downgrade() -> None:
    op.drop_column('progress_exercise_records', 'best_reps_weight')
    op.drop_column('progress_exercise_records', 'best_reps')
