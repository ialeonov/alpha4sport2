"""exercise set type

Revision ID: 0013_exercise_set_type
Revises: 0012_pr_reps
Create Date: 2026-04-14
"""

import sqlalchemy as sa
from alembic import op

revision = '0013_exercise_set_type'
down_revision = '0012_pr_reps'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'exercise_sets',
        sa.Column('set_type', sa.String(length=16), nullable=False, server_default='work'),
    )


def downgrade() -> None:
    op.drop_column('exercise_sets', 'set_type')
