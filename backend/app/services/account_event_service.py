from __future__ import annotations

from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.account_event import AccountEvent
from app.models.event_like import EventLike
from app.models.progression import UserProgression
from app.models.user import User
from app.models.workout import Workout
from app.services.progression_math import get_level_by_xp


def display_name_for_user(user: User) -> str:
    custom_name = (user.display_name or '').strip()
    if custom_name:
        return custom_name
    local_part = user.email.split('@')[0].replace('.', ' ').replace('_', ' ').strip()
    if not local_part:
        return 'Атлет'
    return ' '.join(part.capitalize() for part in local_part.split())


def avatar_url_for_user(user: User) -> str | None:
    if not user.avatar_path:
        return None
    normalized = user.avatar_path.replace('\\', '/').lstrip('/')
    return f'/uploads/{normalized}'


class AccountEventService:
    def __init__(self, db: Session):
        self.db = db

    # Event types that are hidden from the social feed
    _HIDDEN_FROM_FEED = frozenset({'avatar_updated', 'pr_volume', 'workout_volume_bonus', 'workout_completed'})

    @staticmethod
    def _is_feed_event(column) -> object:
        return column.not_in(AccountEventService._HIDDEN_FROM_FEED)

    def log_once(
        self,
        *,
        user_id: int,
        event_key: str,
        event_type: str,
        description: str,
        created_at: datetime,
        metadata: dict | None = None,
    ) -> None:
        existing = self.db.scalar(select(AccountEvent).where(AccountEvent.event_key == event_key))
        if existing:
            return
        self.db.add(
            AccountEvent(
                user_id=user_id,
                event_key=event_key,
                event_type=event_type,
                description=description,
                created_at=created_at,
                metadata_json=metadata,
            )
        )

    def list_users(self) -> list[dict]:
        users = list(self.db.scalars(select(User).order_by(User.created_at.desc())))
        progressions = {
            item.user_id: item
            for item in self.db.scalars(select(UserProgression))
        }
        last_activity = {
            row.user_id: row.last_activity
            for row in self.db.execute(
                select(
                    AccountEvent.user_id,
                    func.max(AccountEvent.created_at).label('last_activity'),
                )
                .where(self._is_feed_event(AccountEvent.event_type))
                .group_by(AccountEvent.user_id)
            )
        }

        result = []
        for user in users:
            progression = progressions.get(user.id)
            total_xp = progression.total_xp if progression else 0
            result.append(
                {
                    'id': user.id,
                    'displayName': display_name_for_user(user),
                    'avatarUrl': avatar_url_for_user(user),
                    'level': get_level_by_xp(total_xp),
                    'totalXp': total_xp,
                    'currentStreak': progression.current_streak if progression else 0,
                    'lastActivityAt': last_activity.get(user.id),
                }
            )
        return result

    @staticmethod
    def _workout_id_from_key(event: AccountEvent) -> int | None:
        """Extract workout_id from event_key for workout-linked events.

        Handles formats:
          workout_completed:{workout_id}
          workout_volume_bonus:{workout_id}
          record:{workout_id}:{exercise_key}:{type}   (pr_weight / pr_volume)
        """
        key = event.event_key
        if key.startswith('record:'):
            parts = key.split(':')
            if len(parts) >= 2:
                try:
                    return int(parts[1])
                except ValueError:
                    pass
        elif event.event_type in {'workout_completed', 'workout_volume_bonus'}:
            parts = key.split(':')
            if len(parts) >= 2:
                try:
                    return int(parts[1])
                except ValueError:
                    pass
        return None

    def toggle_like(self, *, user_id: int, event_id: int) -> dict:
        existing = self.db.scalar(
            select(EventLike).where(
                EventLike.user_id == user_id,
                EventLike.event_id == event_id,
            )
        )
        if existing:
            self.db.delete(existing)
        else:
            self.db.add(EventLike(user_id=user_id, event_id=event_id))
        self.db.commit()
        likes_count = self.db.scalar(
            select(func.count()).select_from(EventLike).where(EventLike.event_id == event_id)
        ) or 0
        return {'liked': existing is None, 'likesCount': likes_count}

    def list_events(self, limit: int = 40, current_user_id: int | None = None) -> list[dict]:
        events = list(
            self.db.scalars(
                select(AccountEvent)
                .where(self._is_feed_event(AccountEvent.event_type))
                .where(~AccountEvent.event_key.like('%:pr_volume'))
                .where(~AccountEvent.event_key.like('%:volume'))
                .order_by(AccountEvent.created_at.desc(), AccountEvent.id.desc())
                .limit(limit)
            )
        )

        # Collect workout IDs referenced by events and check which still exist
        referenced_workout_ids = {
            wid
            for event in events
            if (wid := self._workout_id_from_key(event)) is not None
        }
        existing_workout_ids: set[int] = set()
        if referenced_workout_ids:
            existing_workout_ids = set(
                self.db.scalars(
                    select(Workout.id).where(Workout.id.in_(referenced_workout_ids))
                )
            )

        user_ids = {event.user_id for event in events}
        users = {
            user.id: user
            for user in self.db.scalars(select(User).where(User.id.in_(user_ids)))
        }

        event_ids = [e.id for e in events]
        like_counts: dict[int, int] = {}
        my_likes: set[int] = set()
        if event_ids:
            for row in self.db.execute(
                select(EventLike.event_id, func.count().label('cnt'))
                .where(EventLike.event_id.in_(event_ids))
                .group_by(EventLike.event_id)
            ):
                like_counts[row.event_id] = row.cnt
            if current_user_id is not None:
                my_likes = set(
                    self.db.scalars(
                        select(EventLike.event_id).where(
                            EventLike.user_id == current_user_id,
                            EventLike.event_id.in_(event_ids),
                        )
                    )
                )

        result = []
        for event in events:
            user = users.get(event.user_id)
            if user is None:
                continue
            wid = self._workout_id_from_key(event)
            if wid is not None and wid not in existing_workout_ids:
                continue
            result.append({
                'id': event.id,
                'eventType': event.event_type,
                'description': event.description,
                'createdAt': event.created_at,
                'likesCount': like_counts.get(event.id, 0),
                'isLikedByMe': event.id in my_likes,
                'user': {
                    'id': user.id,
                    'displayName': display_name_for_user(user),
                    'avatarUrl': avatar_url_for_user(user),
                },
            })
        return result
