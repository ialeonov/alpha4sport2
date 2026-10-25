"""add coach_user_memory table for persistent AI observations about users

Revision ID: 0019_coach_user_memory
Revises: 0018_user_profile_extended
Create Date: 2026-05-13
"""

from alembic import op
import sqlalchemy as sa


revision = '0019_coach_user_memory'
down_revision = '0018_user_profile_extended'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'coach_user_memory',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('key', sa.String(80), nullable=False),
        sa.Column('value', sa.Text(), nullable=False),
        sa.Column('confidence', sa.Float(), nullable=False, server_default='0.8'),
        sa.Column('source', sa.String(40), nullable=False, server_default='chat'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'key', name='uq_coach_user_memory_user_key'),
    )
    op.create_index(op.f('ix_coach_user_memory_user_id'), 'coach_user_memory', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_coach_user_memory_user_id'), table_name='coach_user_memory')
    op.drop_table('coach_user_memory')
