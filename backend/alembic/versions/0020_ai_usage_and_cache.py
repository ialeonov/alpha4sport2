"""add ai_usage_events and ai_response_cache tables

Revision ID: 0020_ai_usage_and_cache
Revises: 0019_coach_user_memory
Create Date: 2026-10-25
"""

from alembic import op
import sqlalchemy as sa


revision = '0020_ai_usage_and_cache'
down_revision = '0019_coach_user_memory'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'ai_usage_events',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=True),
        sa.Column('feature', sa.String(40), nullable=False),
        sa.Column('model', sa.String(120), nullable=False, server_default=''),
        sa.Column('prompt_tokens', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('completion_tokens', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('estimated', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('cache_hit', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_ai_usage_events_user_id'), 'ai_usage_events', ['user_id'], unique=False)
    op.create_index(op.f('ix_ai_usage_events_created_at'), 'ai_usage_events', ['created_at'], unique=False)

    op.create_table(
        'ai_response_cache',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('feature', sa.String(40), nullable=False),
        sa.Column('cache_key', sa.String(64), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'feature', 'cache_key', name='uq_ai_response_cache_key'),
    )
    op.create_index(op.f('ix_ai_response_cache_user_id'), 'ai_response_cache', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_ai_response_cache_user_id'), table_name='ai_response_cache')
    op.drop_table('ai_response_cache')
    op.drop_index(op.f('ix_ai_usage_events_created_at'), table_name='ai_usage_events')
    op.drop_index(op.f('ix_ai_usage_events_user_id'), table_name='ai_usage_events')
    op.drop_table('ai_usage_events')
