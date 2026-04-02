"""account events and avatars

Revision ID: 0005_account_events_and_avatars
Revises: 0004_progression
Create Date: 2026-03-20
"""

from alembic import op
import sqlalchemy as sa


revision = '0005_account_events_and_avatars'
down_revision = '0004_progression'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('avatar_path', sa.String(length=500), nullable=True))

    op.create_table(
        'account_events',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('event_key', sa.String(length=180), nullable=False),
        sa.Column('event_type', sa.String(length=80), nullable=False),
        sa.Column('description', sa.String(length=280), nullable=False),
        sa.Column('metadata_json', sa.JSON(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('event_key', name='uq_account_events_event_key'),
    )
    op.create_index('ix_account_events_user_id', 'account_events', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_account_events_user_id', table_name='account_events')
    op.drop_table('account_events')
    op.drop_column('users', 'avatar_path')
