"""user profile

Revision ID: 0015_user_profile
Revises: 0014_announcements
Create Date: 2026-04-26
"""

import sqlalchemy as sa
from alembic import op

revision = '0015_user_profile'
down_revision = '0014_announcements'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'user_profiles',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('goal', sa.String(length=50), nullable=True),
        sa.Column('experience', sa.String(length=50), nullable=True),
        sa.Column('gender', sa.String(length=20), nullable=True),
        sa.Column('injuries', sa.Text(), nullable=True),
        sa.Column('days_per_week', sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id'),
    )


def downgrade() -> None:
    op.drop_table('user_profiles')
