"""template exercise target weight

Revision ID: 0010_template_exercise_weight
Revises: 0009_account_events_indexes
Create Date: 2026-04-05
"""

import sqlalchemy as sa
from alembic import op

revision = '0010_template_exercise_weight'
down_revision = '0009_account_events_indexes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'workout_template_exercises',
        sa.Column('target_weight', sa.Float(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('workout_template_exercises', 'target_weight')
