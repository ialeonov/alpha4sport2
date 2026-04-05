"""account events indexes

Revision ID: 0009_account_events_indexes
Revises: 0008_template_sharing
Create Date: 2026-04-05
"""

from alembic import op

revision = '0009_account_events_indexes'
down_revision = '0008_template_sharing'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        'ix_account_events_event_type',
        'account_events',
        ['event_type'],
    )
    op.create_index(
        'ix_account_events_created_at',
        'account_events',
        ['created_at'],
    )


def downgrade() -> None:
    op.drop_index('ix_account_events_created_at', table_name='account_events')
    op.drop_index('ix_account_events_event_type', table_name='account_events')
