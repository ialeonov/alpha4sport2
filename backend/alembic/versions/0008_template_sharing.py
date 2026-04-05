"""template sharing

Revision ID: 0008_template_sharing
Revises: 0007_event_likes
Create Date: 2026-04-05
"""

import sqlalchemy as sa
from alembic import op

revision = '0008_template_sharing'
down_revision = '0007_event_likes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'workout_templates',
        sa.Column('share_token', sa.String(64), nullable=True),
    )
    op.create_index(
        'ix_workout_templates_share_token',
        'workout_templates',
        ['share_token'],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index('ix_workout_templates_share_token', table_name='workout_templates')
    op.drop_column('workout_templates', 'share_token')
