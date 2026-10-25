"""extend user_profiles with birth_year, height_cm, preferred_days, coach_notes

Revision ID: 0018_user_profile_extended
Revises: 0017_wellness_entries
Create Date: 2026-05-13
"""

from alembic import op
import sqlalchemy as sa


revision = '0018_user_profile_extended'
down_revision = '0017_wellness_entries'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('user_profiles', sa.Column('birth_year', sa.Integer(), nullable=True))
    op.add_column('user_profiles', sa.Column('height_cm', sa.Integer(), nullable=True))
    op.add_column('user_profiles', sa.Column('preferred_days', sa.String(40), nullable=True))
    op.add_column('user_profiles', sa.Column('coach_notes', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('user_profiles', 'coach_notes')
    op.drop_column('user_profiles', 'preferred_days')
    op.drop_column('user_profiles', 'height_cm')
    op.drop_column('user_profiles', 'birth_year')
