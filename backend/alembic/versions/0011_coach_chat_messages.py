"""coach chat messages

Revision ID: 0011_coach_chat_messages
Revises: 0010_template_exercise_weight
Create Date: 2026-04-09
"""

import sqlalchemy as sa
from alembic import op

revision = '0011_coach_chat_messages'
down_revision = '0010_template_exercise_weight'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'coach_chat_messages',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('role', sa.String(length=20), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_coach_chat_messages_user_id', 'coach_chat_messages', ['user_id'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_coach_chat_messages_user_id', table_name='coach_chat_messages')
    op.drop_table('coach_chat_messages')
