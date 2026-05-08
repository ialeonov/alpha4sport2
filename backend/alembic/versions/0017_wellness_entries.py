"""add wellness entries

Revision ID: 0017_wellness_entries
Revises: 0016_merge_back_extensors_core
Create Date: 2026-04-29
"""

from alembic import op
import sqlalchemy as sa


revision = '0017_wellness_entries'
down_revision = '0016_merge_back_extensors_core'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'wellness_entries',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('entry_date', sa.Date(), nullable=False),
        sa.Column('sleep', sa.Integer(), nullable=False),
        sa.Column('energy', sa.Integer(), nullable=False),
        sa.Column('stress', sa.Integer(), nullable=False),
        sa.Column('mood', sa.Integer(), nullable=False),
        sa.Column('comment', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'entry_date', name='uq_wellness_entries_user_date'),
    )
    op.create_index(op.f('ix_wellness_entries_entry_date'), 'wellness_entries', ['entry_date'], unique=False)
    op.create_index(op.f('ix_wellness_entries_user_id'), 'wellness_entries', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_wellness_entries_user_id'), table_name='wellness_entries')
    op.drop_index(op.f('ix_wellness_entries_entry_date'), table_name='wellness_entries')
    op.drop_table('wellness_entries')
