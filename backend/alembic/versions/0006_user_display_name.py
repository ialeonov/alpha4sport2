"""add user display name

Revision ID: 0006_user_display_name
Revises: 0005_account_events_and_avatars
Create Date: 2026-03-21 10:35:00
"""

from alembic import op
import sqlalchemy as sa


revision = "0006_user_display_name"
down_revision = "0005_account_events_and_avatars"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("display_name", sa.String(length=120), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "display_name")
