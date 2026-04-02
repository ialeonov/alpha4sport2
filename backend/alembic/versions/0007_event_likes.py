"""event likes

Revision ID: 0007_event_likes
Revises: 0006_user_display_name
Create Date: 2026-03-25
"""

import sqlalchemy as sa
from alembic import op

revision = '0007_event_likes'
down_revision = '0006_user_display_name'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'event_likes',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('event_id', sa.Integer(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['event_id'], ['account_events.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'event_id', name='uq_event_likes_user_event'),
    )
    op.create_index('ix_event_likes_user_id', 'event_likes', ['user_id'], unique=False)
    op.create_index('ix_event_likes_event_id', 'event_likes', ['event_id'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_event_likes_event_id', table_name='event_likes')
    op.drop_index('ix_event_likes_user_id', table_name='event_likes')
    op.drop_table('event_likes')
