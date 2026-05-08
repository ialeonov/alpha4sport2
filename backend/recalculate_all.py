"""Пересчитывает прогрессию и опыт для всех пользователей."""
import sys
from sqlalchemy import select
from app.db.session import SessionLocal
from app.models.user import User
from app.services.progression_service import ProgressionService


def main():
    db = SessionLocal()
    try:
        user_ids = list(db.scalars(select(User.id).order_by(User.id)))
        print(f'Пользователей: {len(user_ids)}')
        for i, user_id in enumerate(user_ids, 1):
            try:
                ProgressionService(db).recalculate_for_user(user_id)
                print(f'[{i}/{len(user_ids)}] user_id={user_id} — OK')
            except Exception as e:
                print(f'[{i}/{len(user_ids)}] user_id={user_id} — ОШИБКА: {e}', file=sys.stderr)
    finally:
        db.close()


if __name__ == '__main__':
    main()
