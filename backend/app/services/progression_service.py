from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session, joinedload, selectinload

from app.models.progression import (
    ProgressAchievement,
    ProgressExerciseRecord,
    ProgressRecordEvent,
    ProgressRewardEvent,
    SickLeave,
    UserProgression,
)
from app.models.user import User
from app.models.user_profile import UserProfile
from app.models.workout import ExerciseCatalog, ExerciseSet, Workout, WorkoutExercise
from app.services.account_event_service import (
    AccountEventService,
    avatar_url_for_user,
    display_name_for_user,
)
from app.services import gamification
from app.services.muscle_load import MuscleLoadCalculator
from app.services.progression_math import (
    end_of_week,
    estimate_one_rep_max,
    get_level_by_xp,
    get_level_start_xp,
    get_next_level_xp,
    get_title_by_level,
    month_key,
    month_weeks,
    start_of_week,
    week_key,
)

_SICK_LEAVE_REASONS = {
    'болезнь',
    'травма',
    'восстановление',
    'командировка',
    'другое',
}

_XP_REBALANCE_EFFECTIVE_AT = datetime(2026, 3, 20, 0, 0, 0, tzinfo=timezone.utc)

# С этой даты первое выполнение упражнения — базовая точка, а не рекорд.
# Раньше новое упражнение сразу давало «рекорд веса» и «рекорд объёма» с XP.
# Старые тренировки не пересчитываются, чтобы не отнимать набранный XP.
_PR_BASELINE_EFFECTIVE_AT = datetime(2026, 10, 26, 0, 0, 0, tzinfo=timezone.utc)

_LEGACY_XP = {
    'workout_completed': 20,
    'workout_volume_bonus_10': 5,
    'workout_volume_bonus_15': 10,
    'workout_volume_bonus_20': 15,
    'pr_weight': 15,
    'pr_1rm': 20,
    'pr_reps': 12,
    'pr_volume': 10,
    'good_week': 0,
    'ideal_week': 30,
    'ideal_month': 100,
    'milestone_first_workout': 10,
    'milestone_workouts_10': 30,
    'milestone_workouts_25': 50,
    'milestone_workouts_50': 100,
    'comeback_after_break': 10,
    'return_after_sick_leave': 5,
}

_REBALANCED_XP = {
    'workout_completed': 10,
    'workout_volume_bonus_10': 0,
    'workout_volume_bonus_15': 0,
    'workout_volume_bonus_20': 0,
    'pr_weight': 8,
    'pr_1rm': 10,
    'pr_reps': 7,
    'pr_volume': 6,
    'good_week': 15,
    'ideal_week': 30,
    'ideal_month': 100,
    'milestone_first_workout': 10,
    'milestone_workouts_10': 30,
    'milestone_workouts_25': 50,
    'milestone_workouts_50': 100,
    'comeback_after_break': 10,
    'return_after_sick_leave': 5,
}


@dataclass(frozen=True)
class RewardEventData:
    event_key: str
    event_type: str
    xp_awarded: int
    created_at: datetime
    metadata: dict | None = None


@dataclass(frozen=True)
class AchievementData:
    code: str
    achieved_at: datetime
    metadata: dict | None = None


@dataclass(frozen=True)
class RecordEventData:
    workout_id: int
    exercise_key: str
    exercise_name: str
    record_type: str
    value: float
    achieved_at: datetime
    extra_value: float = 0.0


@dataclass(frozen=True)
class WeeklyWorkoutEventData:
    week_key: str
    count: int
    performed_at: datetime
    workout_name: str = ''


_WEEKLY_ORDINALS = ['первую', 'вторую', 'третью', 'четвёртую', 'пятую', 'шестую', 'седьмую']


@dataclass(frozen=True)
class ExerciseRecordSnapshot:
    exercise_key: str
    catalog_exercise_id: int | None
    exercise_name: str
    best_weight: float
    best_1rm: float
    best_volume: float
    best_reps: int
    best_reps_weight: float
    updated_at: datetime


class ProgressionService:
    def __init__(self, db: Session):
        self.db = db

    def get_profile(self, user_id: int) -> dict:
        return self.recalculate_for_user(user_id)

    def recalculate_for_user(self, user_id: int) -> dict:
        user = self.db.get(User, user_id)
        if not user:
            raise ValueError('Пользователь не найден.')

        workouts = list(
            self.db.scalars(
                select(Workout)
                .where(Workout.user_id == user_id)
                .options(joinedload(Workout.exercises).joinedload(WorkoutExercise.sets))
                .order_by(Workout.started_at.asc(), Workout.id.asc())
            ).unique()
        )
        sick_leaves = list(
            self.db.scalars(
                select(SickLeave)
                .where(SickLeave.user_id == user_id)
                .order_by(SickLeave.start_date.asc(), SickLeave.created_at.asc())
            )
        )
        today = date.today()
        status_changed = False
        for item in sick_leaves:
            if item.status == 'cancelled':
                continue
            next_status = 'completed' if item.end_date < today else 'active'
            if item.status != next_status:
                item.status = next_status
                status_changed = True
        if status_changed:
            self.db.commit()

        catalog = list(
            self.db.scalars(
                select(ExerciseCatalog)
                .where(ExerciseCatalog.user_id == user_id)
                .options(selectinload(ExerciseCatalog.secondary_muscle_links))
            )
        )
        profile = self.db.scalar(select(UserProfile).where(UserProfile.user_id == user_id))
        weekly_target = (profile.days_per_week if profile and profile.days_per_week else 3)

        result = _ProgressionCalculator(
            user=user,
            workouts=workouts,
            sick_leaves=sick_leaves,
            catalog=catalog,
            weekly_target=max(2, min(weekly_target, 6)),
        ).build()

        progression = self.db.get(UserProgression, user_id)
        if progression is None:
            progression = UserProgression(user_id=user_id)
            self.db.add(progression)

        profile = result['response']['profile']
        progression.total_xp = profile['totalXp']
        progression.current_streak = profile['currentStreak']
        progression.best_streak = profile['bestStreak']
        progression.total_completed_workouts = profile['totalCompletedWorkouts']
        progression.total_pr_count = profile['totalPrCount']
        progression.ideal_weeks_count = profile['idealWeeksCount']
        progression.ideal_months_count = profile['idealMonthsCount']
        progression.last_calculated_at = datetime.now(timezone.utc)

        self.db.execute(delete(ProgressRewardEvent).where(ProgressRewardEvent.user_id == user_id))
        self.db.execute(delete(ProgressAchievement).where(ProgressAchievement.user_id == user_id))
        self.db.execute(delete(ProgressExerciseRecord).where(ProgressExerciseRecord.user_id == user_id))
        self.db.execute(delete(ProgressRecordEvent).where(ProgressRecordEvent.user_id == user_id))

        for event in result['reward_events']:
            self.db.add(
                ProgressRewardEvent(
                    user_id=user_id,
                    event_key=event.event_key,
                    event_type=event.event_type,
                    xp_awarded=event.xp_awarded,
                    created_at=event.created_at,
                    metadata_json=event.metadata,
                )
            )

        for achievement in result['achievements']:
            self.db.add(
                ProgressAchievement(
                    user_id=user_id,
                    code=achievement.code,
                    achieved_at=achievement.achieved_at,
                    metadata_json=achievement.metadata,
                )
            )

        for snapshot in result['exercise_records']:
            self.db.add(
                ProgressExerciseRecord(
                    user_id=user_id,
                    exercise_key=snapshot.exercise_key,
                    catalog_exercise_id=snapshot.catalog_exercise_id,
                    exercise_name=snapshot.exercise_name,
                    best_weight=snapshot.best_weight,
                    best_1rm=snapshot.best_1rm,
                    best_volume=snapshot.best_volume,
                    best_reps=snapshot.best_reps,
                    best_reps_weight=snapshot.best_reps_weight,
                    updated_at=snapshot.updated_at,
                )
            )

        for record in result['record_events']:
            self.db.add(
                ProgressRecordEvent(
                    user_id=user_id,
                    workout_id=record.workout_id,
                    exercise_key=record.exercise_key,
                    exercise_name=record.exercise_name,
                    record_type=record.record_type,
                    value=record.value,
                    achieved_at=record.achieved_at,
                )
            )

        self._log_account_events(
            user_id=user_id,
            reward_events=result['reward_events'],
            achievements=result['achievements'],
            record_events=result['record_events'],
            weekly_events=result['weekly_events'],
        )

        self.db.commit()
        return result['response']

    def create_sick_leave(
        self,
        *,
        user_id: int,
        start_date: date,
        end_date: date,
        reason: str,
    ) -> dict:
        normalized_reason = reason.strip().lower()
        if normalized_reason not in _SICK_LEAVE_REASONS:
            raise ValueError('Некорректная причина больничного.')
        if end_date < start_date:
            raise ValueError('Дата окончания не может быть раньше даты начала.')
        if (end_date - start_date).days + 1 > 7:
            raise ValueError('Максимальная длительность больничного в MVP — 7 дней.')

        month_start = start_date.replace(day=1)
        next_month = _next_month(month_start)
        existing_count = self.db.scalar(
            select(func.count())
            .select_from(SickLeave)
            .where(
                SickLeave.user_id == user_id,
                SickLeave.status != 'cancelled',
                SickLeave.start_date >= month_start,
                SickLeave.start_date < next_month,
            )
        )
        if (existing_count or 0) >= 1:
            raise ValueError('В этом месяце уже использован доступный больничный эпизод.')

        self.db.add(
            SickLeave(
                user_id=user_id,
                start_date=start_date,
                end_date=end_date,
                reason=normalized_reason,
                status='active' if end_date >= date.today() else 'completed',
                created_at=datetime.now(timezone.utc),
            )
        )
        self.db.commit()
        sick_leave = self.db.scalar(
            select(SickLeave)
            .where(SickLeave.user_id == user_id)
            .order_by(SickLeave.id.desc())
        )
        if sick_leave:
            AccountEventService(self.db).log_once(
                user_id=user_id,
                event_key=f'sick_leave_started:{sick_leave.id}',
                event_type='sick_leave_started',
                description='Открыл больничный.',
                created_at=sick_leave.created_at,
                metadata={'startDate': sick_leave.start_date.isoformat(), 'endDate': sick_leave.end_date.isoformat()},
            )
            self.db.commit()
        return self.recalculate_for_user(user_id)

    def cancel_sick_leave(self, *, user_id: int, sick_leave_id: int) -> dict:
        sick_leave = self.db.scalar(
            select(SickLeave).where(SickLeave.id == sick_leave_id, SickLeave.user_id == user_id)
        )
        if not sick_leave:
            raise ValueError('Больничный не найден.')
        sick_leave.status = 'cancelled'
        self.db.commit()
        return self.recalculate_for_user(user_id)

    def _log_account_events(
        self,
        *,
        user_id: int,
        reward_events: list[RewardEventData],
        achievements: list[AchievementData],
        record_events: list[RecordEventData],
        weekly_events: list[WeeklyWorkoutEventData],
    ) -> None:
        events = AccountEventService(self.db)

        now = datetime.now(timezone.utc)

        for weekly in weekly_events:
            ordinal = (
                _WEEKLY_ORDINALS[weekly.count - 1]
                if weekly.count <= len(_WEEKLY_ORDINALS)
                else f'{weekly.count}-ю'
            )
            name_part = f' "{weekly.workout_name}"' if weekly.workout_name else ''
            events.log_once(
                user_id=user_id,
                event_key=f'weekly_workout:{user_id}:{weekly.week_key}:{weekly.count}',
                event_type='weekly_workout',
                description=f'Завершил {ordinal} тренировку на неделе{name_part}.',
                created_at=now,
            )

        for achievement in achievements:
            events.log_once(
                user_id=user_id,
                event_key=f'achievement:{achievement.code}',
                event_type='achievement',
                description=f'Получил достижение: {_achievement_title(achievement.code)}.',
                created_at=now,
            )

        for record in record_events:
            if record.record_type in ('pr_volume', 'reps'):
                continue
            if record.record_type == 'reps':
                reps = int(record.value)
                weight_part = f' ({record.extra_value:g} кг)' if record.extra_value > 0 else ''
                value_str = f'{reps} раз{weight_part}'
            else:
                value_str = f'{record.value:g} кг'
            events.log_once(
                user_id=user_id,
                event_key=f'record:{record.workout_id}:{record.exercise_key}:{record.record_type}',
                event_type='record',
                description=f'Поставил новый рекорд: {record.exercise_name} — {_record_label(record.record_type)}: {value_str}.',
                created_at=now,
            )

        if reward_events:
            running_xp = 0
            current_level = 1
            for reward in sorted(reward_events, key=lambda item: item.created_at):
                running_xp += reward.xp_awarded
                next_level = get_level_by_xp(running_xp)
                while current_level < next_level:
                    current_level += 1
                    events.log_once(
                        user_id=user_id,
                        event_key=f'level_up:{current_level}',
                        event_type='level_up',
                        description=f'Достиг уровня {current_level}.',
                        created_at=now,
                    )

                if reward.event_type == 'return_after_sick_leave':
                    events.log_once(
                        user_id=user_id,
                        event_key=reward.event_key,
                        event_type='return_after_sick_leave',
                        description='Вернулся к тренировкам после больничного.',
                        created_at=reward.created_at,
                    )


class _ProgressionCalculator:
    def __init__(
        self,
        *,
        user: User,
        workouts: list[Workout],
        sick_leaves: list[SickLeave],
        catalog: list[ExerciseCatalog] | None = None,
        weekly_target: int = 3,
    ):
        self.user = user
        self.workouts = workouts
        self.sick_leaves = sick_leaves
        self.load_calculator = MuscleLoadCalculator(catalog or [])
        self.weekly_target = weekly_target
        self.total_tonnage = 0.0
        self.valid_workouts: list[Workout] = []
        self.reward_events: dict[str, RewardEventData] = {}
        self.achievements: dict[str, AchievementData] = {}
        self.record_events: list[RecordEventData] = []
        self.weekly_events: list[WeeklyWorkoutEventData] = []
        self.exercise_records: dict[str, ExerciseRecordSnapshot] = {}
        self.total_completed_workouts = 0
        self.total_pr_count = 0
        self._week_counts: dict[str, int] = {}

    def build(self) -> dict:
        today = date.today()
        valid_dates: list[date] = []
        last_valid_day: date | None = None

        for workout in self.workouts:
            if workout.finished_at is None or not self._is_valid_workout(workout):
                continue

            performed_at = workout.finished_at or workout.started_at
            performed_day = performed_at.date()
            valid_dates.append(performed_day)
            self.total_completed_workouts += 1

            wk = week_key(performed_day)
            self._week_counts[wk] = self._week_counts.get(wk, 0) + 1
            self.weekly_events.append(
                WeeklyWorkoutEventData(
                    week_key=wk,
                    count=self._week_counts[wk],
                    performed_at=performed_at,
                    workout_name=workout.name or '',
                )
            )

            self._reward_once(
                event_key=f'workout_completed:{workout.id}',
                event_type='workout_completed',
                xp_awarded=self._xp_for('workout_completed', performed_at),
                created_at=performed_at,
                metadata={'workoutId': workout.id},
            )

            working_sets = self._working_sets_count(workout)
            volume_bonus = self._volume_bonus_xp(working_sets, performed_at)
            if volume_bonus > 0:
                self._reward_once(
                    event_key=f'workout_volume_bonus:{workout.id}',
                    event_type='workout_volume_bonus',
                    xp_awarded=volume_bonus,
                    created_at=performed_at,
                    metadata={'workoutId': workout.id, 'workingSets': working_sets},
                )
            if working_sets >= 20:
                self._achievement_once(code='high_volume_session', achieved_at=performed_at)

            if self.total_completed_workouts == 1:
                self._reward_once(
                    event_key='milestone_first_workout',
                    event_type='milestone_first_workout',
                    xp_awarded=self._xp_for('milestone_first_workout', performed_at),
                    created_at=performed_at,
                )
                self._achievement_once(code='first_workout', achieved_at=performed_at)

            for count, code in _WORKOUT_TIERS:
                if self.total_completed_workouts == count:
                    self._achievement_once(code=code, achieved_at=performed_at)

            if self.total_completed_workouts in (10, 25, 50):
                self._reward_once(
                    event_key=f'milestone_workouts:{self.total_completed_workouts}',
                    event_type='milestone_workouts',
                    xp_awarded=self._xp_for(
                        f'milestone_workouts_{self.total_completed_workouts}',
                        performed_at,
                    ),
                    created_at=performed_at,
                )
                self._achievement_once(
                    code={
                        10: 'ten_workouts',
                        25: 'twenty_five_workouts',
                        50: 'fifty_workouts',
                    }[self.total_completed_workouts],
                    achieved_at=performed_at,
                )

            if last_valid_day is not None:
                gap_days = (performed_day - last_valid_day).days - 1
                if gap_days >= 10 and not self._has_sick_leave_between(
                    last_valid_day + timedelta(days=1),
                    performed_day - timedelta(days=1),
                ):
                    self._reward_once(
                        event_key=f'comeback_after_break:{workout.id}',
                        event_type='comeback_after_break',
                        xp_awarded=self._xp_for('comeback_after_break', performed_at),
                        created_at=performed_at,
                        metadata={'gapDays': gap_days},
                    )
                    self._achievement_once(code='comeback_after_break', achieved_at=performed_at)

            if self._is_return_after_sick_leave(performed_day):
                self._reward_once(
                    event_key=f'return_after_sick_leave:{workout.id}',
                    event_type='return_after_sick_leave',
                    xp_awarded=self._xp_for('return_after_sick_leave', performed_at),
                    created_at=performed_at,
                )
                self._achievement_once(code='return_after_sick_leave', achieved_at=performed_at)

            self.total_pr_count += self._register_prs(workout, performed_at)
            self.valid_workouts.append(workout)
            before_tonnage = self.total_tonnage
            self.total_tonnage += sum(
                float(s.weight or 0) * s.reps
                for e in workout.exercises
                for s in e.sets
                if _is_working_set(s)
            )
            for tons, code in _TONNAGE_TIERS:
                if before_tonnage < tons * 1000 <= self.total_tonnage:
                    self._achievement_once(code=code, achieved_at=performed_at)
            last_valid_day = performed_day

        if self.record_events:
            self._achievement_once(code='first_pr', achieved_at=self.record_events[0].achieved_at)
        if len(self.record_events) >= 5:
            self._achievement_once(code='five_prs', achieved_at=self.record_events[4].achieved_at)
        for count, code in _PR_TIERS:
            if len(self.record_events) >= count:
                self._achievement_once(
                    code=code, achieved_at=self.record_events[count - 1].achieved_at,
                )

        weekly = self._build_weekly_summaries(valid_dates, today)
        self._award_weekly_progress(weekly, today)
        monthly = self._build_monthly_summaries(weekly, today)
        self._award_monthly_progress(monthly, today)

        current_streak, best_streak = self._calculate_streaks(weekly, today)
        self._award_long_term_achievements(weekly, today)
        self._award_strength_clubs()
        current_quests = self._award_weekly_quests(today)
        total_xp = sum(item.xp_awarded for item in self.reward_events.values())
        level = get_level_by_xp(total_xp)
        level_start_xp = get_level_start_xp(level)
        next_level_xp = get_next_level_xp(level)

        current_week = next(
            (item for item in weekly if item['weekKey'] == week_key(today)),
            self._empty_week_summary(start_of_week(today)),
        )
        current_month = next(
            (item for item in monthly if item['monthKey'] == month_key(today)),
            self._empty_month_summary(today),
        )

        response = {
            'user': {
                'displayName': display_name_for_user(self.user),
                'email': self.user.email,
                'avatarText': _avatar_text(self.user.email),
                'avatarUrl': avatar_url_for_user(self.user),
            },
            'profile': {
                'totalXp': total_xp,
                'level': level,
                'levelStartXp': level_start_xp,
                'nextLevelXp': next_level_xp,
                'xpInLevel': total_xp - level_start_xp,
                'xpRemainingToNextLevel': max(0, next_level_xp - total_xp),
                'title': get_title_by_level(level),
                'currentStreak': current_streak,
                'bestStreak': best_streak,
                'totalCompletedWorkouts': self.total_completed_workouts,
                'totalPrCount': self.total_pr_count,
                'idealWeeksCount': sum(1 for item in weekly if item['isIdeal']),
                'idealMonthsCount': sum(1 for item in monthly if item['isIdeal']),
            },
            'weeklyQuests': [quest.to_dict() for quest in current_quests],
            'weeklyQuestBonusXp': gamification.QUEST_ALL_BONUS_XP,
            'muscleLevels': gamification.build_muscle_levels(
                self.valid_workouts, self.load_calculator,
            ),
            'achievementCatalog': self._build_achievement_catalog(
                best_streak=best_streak,
                ideal_weeks=sum(1 for item in weekly if item['isIdeal']),
            ),
            'currentWeek': current_week,
            'currentMonth': current_month,
            'recentAchievements': [
                _serialize_achievement(item)
                for item in sorted(self.achievements.values(), key=lambda value: value.achieved_at, reverse=True)[:5]
            ],
            'recentRecords': [
                _serialize_record(item)
                for item in sorted(self.record_events, key=lambda value: value.achieved_at, reverse=True)[:5]
            ],
            'allExerciseRecords': [
                _serialize_exercise_record(item)
                for item in sorted(
                    self.exercise_records.values(),
                    key=lambda r: r.exercise_name,
                )
            ],
            'recentRewards': [
                _serialize_reward(item)
                for item in sorted(self.reward_events.values(), key=lambda value: value.created_at, reverse=True)[:8]
            ],
            'sickLeave': {
                'active': _serialize_sick_leave(self._active_sick_leave(today)),
                'remainingEpisodesThisMonth': 0 if self._has_sick_leave_in_month(today) else 1,
                'allowedEpisodesPerMonth': 1,
                'maxDaysPerEpisode': 7,
                'history': [
                    _serialize_sick_leave(item)
                    for item in sorted(self.sick_leaves, key=lambda value: value.created_at, reverse=True)[:5]
                ],
            },
        }

        return {
            'response': response,
            'reward_events': list(self.reward_events.values()),
            'achievements': list(self.achievements.values()),
            'record_events': self.record_events,
            'weekly_events': self.weekly_events,
            'exercise_records': list(self.exercise_records.values()),
        }

    def _register_prs(self, workout: Workout, performed_at: datetime) -> int:
        count = 0
        for exercise in workout.exercises:
            valid_sets = [set_item for set_item in exercise.sets if _is_working_set(set_item)]
            if not valid_sets:
                continue

            exercise_key = _exercise_key(exercise)
            previous = self.exercise_records.get(exercise_key)
            aware_performed_at = (
                performed_at if performed_at.tzinfo else performed_at.replace(tzinfo=timezone.utc)
            )
            is_baseline = previous is None and aware_performed_at >= _PR_BASELINE_EFFECTIVE_AT
            previous_weight = previous.best_weight if previous else 0
            previous_1rm = previous.best_1rm if previous else 0
            previous_volume = previous.best_volume if previous else 0
            previous_reps = previous.best_reps if previous else 0

            best_weight = max(float(set_item.weight or 0) for set_item in valid_sets)
            best_1rm = max(
                estimate_one_rep_max(float(set_item.weight or 0), set_item.reps)
                for set_item in valid_sets
            )
            best_volume = sum(float(set_item.weight or 0) * set_item.reps for set_item in valid_sets)

            # Рекорд повторений считается только с рекордным весом
            new_best_weight = max(previous_weight, best_weight)
            sets_at_record_weight = [
                s for s in valid_sets if float(s.weight or 0) == new_best_weight
            ]
            reps_at_record_weight = max((s.reps for s in sets_at_record_weight), default=0)

            if best_weight > previous_weight and not is_baseline:
                count += 1
                self._reward_once(
                    event_key=f'pr_weight:{workout.id}:{exercise_key}',
                    event_type='pr_weight',
                    xp_awarded=self._xp_for('pr_weight', performed_at),
                    created_at=performed_at,
                    metadata={'workoutId': workout.id, 'exerciseName': exercise.exercise_name},
                )
                self.record_events.append(
                    RecordEventData(
                        workout_id=workout.id,
                        exercise_key=exercise_key,
                        exercise_name=exercise.exercise_name,
                        record_type='weight',
                        value=best_weight,
                        achieved_at=performed_at,
                    )
                )

            if best_volume > previous_volume and not is_baseline:
                count += 1
                self._reward_once(
                    event_key=f'pr_volume:{workout.id}:{exercise_key}',
                    event_type='pr_volume',
                    xp_awarded=self._xp_for('pr_volume', performed_at),
                    created_at=performed_at,
                    metadata={'workoutId': workout.id, 'exerciseName': exercise.exercise_name},
                )
                self.record_events.append(
                    RecordEventData(
                        workout_id=workout.id,
                        exercise_key=exercise_key,
                        exercise_name=exercise.exercise_name,
                        record_type='volume',
                        value=best_volume,
                        achieved_at=performed_at,
                    )
                )

            # pr_reps: отслеживаем рекорд повторений с рекордным весом (без XP и ленты)
            if reps_at_record_weight > previous_reps and not is_baseline:
                self.record_events.append(
                    RecordEventData(
                        workout_id=workout.id,
                        exercise_key=exercise_key,
                        exercise_name=exercise.exercise_name,
                        record_type='reps',
                        value=reps_at_record_weight,
                        extra_value=new_best_weight,
                        achieved_at=performed_at,
                    )
                )

            new_best_reps = reps_at_record_weight if best_weight >= previous_weight else previous_reps
            self.exercise_records[exercise_key] = ExerciseRecordSnapshot(
                exercise_key=exercise_key,
                catalog_exercise_id=exercise.catalog_exercise_id,
                exercise_name=exercise.exercise_name,
                best_weight=new_best_weight,
                best_1rm=max(previous_1rm, best_1rm),
                best_volume=max(previous_volume, best_volume),
                best_reps=new_best_reps,
                best_reps_weight=new_best_weight,
                updated_at=performed_at,
            )
        return count

    def _build_weekly_summaries(self, valid_dates: list[date], today: date) -> list[dict]:
        counts: dict[date, int] = {}
        for day in valid_dates:
            week_start = start_of_week(day)
            counts[week_start] = counts.get(week_start, 0) + 1

        if counts:
            first_week = min(counts)
        else:
            first_week = start_of_week(today)
        last_week = start_of_week(today)

        summaries: list[dict] = []
        cursor = first_week
        while cursor <= last_week:
            workout_count = counts.get(cursor, 0)
            frozen = workout_count == 0 and self._is_week_frozen(cursor)
            status = 'ideal' if workout_count >= 3 else 'good' if workout_count == 2 else 'regular'
            summaries.append(
                {
                    'weekKey': week_key(cursor),
                    'startDate': cursor.isoformat(),
                    'endDate': end_of_week(cursor).isoformat(),
                    'workoutCount': workout_count,
                    'status': status,
                    'isIdeal': workout_count >= 3,
                    'isFrozen': frozen,
                    'streakEligible': workout_count >= 2,
                }
            )
            cursor += timedelta(days=7)
        return summaries

    def _award_weekly_progress(self, weekly: list[dict], today: date) -> None:
        current_week_start = start_of_week(today)
        for item in weekly:
            week_start = date.fromisoformat(item['startDate'])
            if week_start == current_week_start:
                achieved_at = datetime.now(timezone.utc)
            else:
                achieved_at = _end_of_day(date.fromisoformat(item['endDate']))
            if item['workoutCount'] == 2:
                good_week_xp = self._xp_for('good_week', achieved_at)
                if good_week_xp > 0:
                    self._reward_once(
                        event_key=f'good_week:{item["weekKey"]}',
                        event_type='good_week',
                        xp_awarded=good_week_xp,
                        created_at=achieved_at,
                        metadata={'weekKey': item['weekKey']},
                    )
                self._achievement_once(code='good_week', achieved_at=achieved_at)
            if item['isIdeal']:
                self._reward_once(
                    event_key=f'ideal_week:{item["weekKey"]}',
                    event_type='ideal_week',
                    xp_awarded=self._xp_for('ideal_week', achieved_at),
                    created_at=achieved_at,
                    metadata={'weekKey': item['weekKey']},
                )
                self._achievement_once(code='ideal_week', achieved_at=achieved_at)

    def _build_monthly_summaries(self, weekly: list[dict], today: date) -> list[dict]:
        summaries_by_key = {item['weekKey']: item for item in weekly}
        if weekly:
            cursor = date.fromisoformat(weekly[0]['startDate']).replace(day=1)
        else:
            cursor = today.replace(day=1)
        last_month = today.replace(day=1)
        result: list[dict] = []

        while cursor <= last_month:
            week_starts = month_weeks(cursor)
            relevant = [
                summaries_by_key.get(week_key(week_start), self._empty_week_summary(week_start))
                for week_start in week_starts
            ]
            ideal_weeks_count = sum(1 for item in relevant if item['isIdeal'])
            is_past_month = cursor < last_month
            is_ideal = bool(relevant) and is_past_month and all(item['isIdeal'] for item in relevant)
            result.append(
                {
                    'monthKey': month_key(cursor),
                    'year': cursor.year,
                    'month': cursor.month,
                    'idealWeeksCount': ideal_weeks_count,
                    'weeksConsidered': len(relevant),
                    'isIdeal': is_ideal,
                    'status': 'идеальный' if is_ideal else 'в процессе' if cursor == last_month else 'обычный',
                }
            )
            cursor = _next_month(cursor)
        return result

    def _award_monthly_progress(self, monthly: list[dict], today: date) -> None:
        current_month_key = month_key(today)
        first_perfect_awarded = False
        for item in monthly:
            if item['monthKey'] == current_month_key or not item['isIdeal']:
                continue
            month_date = date(item['year'], item['month'], 1)
            achieved_at = _end_of_day(_month_end(month_date))
            self._reward_once(
                event_key=f'ideal_month:{item["monthKey"]}',
                event_type='ideal_month',
                xp_awarded=self._xp_for('ideal_month', achieved_at),
                created_at=achieved_at,
                metadata={'monthKey': item['monthKey']},
            )
            if not first_perfect_awarded:
                self._achievement_once(code='first_perfect_month', achieved_at=achieved_at)
                first_perfect_awarded = True

    def _calculate_streaks(self, weekly: list[dict], today: date) -> tuple[int, int]:
        current_week_start = start_of_week(today)
        completed = [
            item for item in weekly if date.fromisoformat(item['startDate']) < current_week_start
        ]
        best = 0
        running = 0
        for item in completed:
            if item['streakEligible']:
                running += 1
                best = max(best, running)
            elif item['isFrozen']:
                continue
            else:
                running = 0

        current = 0
        for item in reversed(weekly):
            is_current_week = date.fromisoformat(item['startDate']) == current_week_start
            if is_current_week and not item['streakEligible']:
                continue
            if item['streakEligible']:
                current += 1
                continue
            if item['isFrozen']:
                continue
            break
        return current, max(best, current)

    def _award_long_term_achievements(self, weekly: list[dict], today: date) -> None:
        """Достижения за серии недель и накопленные идеальные недели."""
        current_week_start = start_of_week(today)
        running = 0
        ideal = 0
        for item in weekly:
            week_start = date.fromisoformat(item['startDate'])
            achieved_at = (
                datetime.now(timezone.utc)
                if week_start == current_week_start
                else _end_of_day(date.fromisoformat(item['endDate']))
            )
            if item['streakEligible']:
                running += 1
            elif not item['isFrozen'] and week_start != current_week_start:
                running = 0
            for weeks, code in _STREAK_ACHIEVEMENTS:
                if running >= weeks:
                    self._achievement_once(code=code, achieved_at=achieved_at)
            if item['isIdeal']:
                ideal += 1
                if ideal >= 10:
                    self._achievement_once(code='ten_ideal_weeks', achieved_at=achieved_at)

    def _award_weekly_quests(self, today: date) -> list:
        """Задания недели: XP за каждое выполненное и бонус за все три.
        Возвращает задания текущей недели для экрана."""
        current: list = []
        for week_start in gamification.quest_weeks(today):
            week_end = week_start + timedelta(days=6)
            records = sum(
                1
                for r in self.record_events
                if r.record_type in ('weight', 'volume')
                and week_start <= r.achieved_at.date() <= week_end
            )
            quests = gamification.build_week_quests(
                week_start=week_start,
                workouts=self.valid_workouts,
                calculator=self.load_calculator,
                record_count=records,
                weekly_target=self.weekly_target,
            )
            moment = gamification.week_end_moment(week_start, today)
            key = week_key(week_start)
            for quest in quests:
                if quest.completed:
                    self._reward_once(
                        event_key=f'quest:{key}:{quest.code}',
                        event_type='weekly_quest',
                        xp_awarded=gamification.QUEST_XP,
                        created_at=moment,
                        metadata={'weekKey': key, 'quest': quest.title},
                    )
            if quests and all(q.completed for q in quests):
                self._reward_once(
                    event_key=f'quest:{key}:all',
                    event_type='weekly_quest_bonus',
                    xp_awarded=gamification.QUEST_ALL_BONUS_XP,
                    created_at=moment,
                    metadata={'weekKey': key},
                )
                self._achievement_once(code='quest_week_all', achieved_at=moment)
            current = quests
        return current

    def _award_strength_clubs(self) -> None:
        """Клубы по основным упражнениям: 100 кг в жиме и т. п. Дата — первый
        рекорд веса, который перешагнул порог."""
        for record in sorted(self.record_events, key=lambda r: r.achieved_at):
            if record.record_type != 'weight':
                continue
            club = gamification.club_for(record.exercise_name)
            if club is None:
                continue
            for threshold in club.thresholds:
                if record.value >= threshold:
                    self._achievement_once(
                        code=gamification.club_code(club, threshold),
                        achieved_at=record.achieved_at,
                    )

    def _club_catalog(self) -> list[dict]:
        """Клубы для каталога: полученные и следующий порог по каждому
        упражнению, которое пользователь делает."""
        best = gamification.best_lift_by_club(self.exercise_records)
        items = []
        for club in gamification.CLUBS:
            if club.key not in best:
                continue
            for threshold in club.thresholds:
                code = gamification.club_code(club, threshold)
                achieved = self.achievements.get(code)
                if achieved is None and best[club.key] < threshold:
                    items.append({
                        'code': code,
                        'title': gamification.club_title(code),
                        'description': f'{club.title}: рабочий вес {threshold} кг',
                        'unlocked': False,
                        'achievedAt': None,
                        'progress': int(best[club.key]),
                        'target': threshold,
                    })
                    break
                if achieved is not None:
                    items.append({
                        'code': code,
                        'title': gamification.club_title(code),
                        'description': f'{club.title}: рабочий вес {threshold} кг',
                        'unlocked': True,
                        'achievedAt': achieved.achieved_at.isoformat(),
                        'progress': threshold,
                        'target': threshold,
                    })
        return items

    def _build_achievement_catalog(self, *, best_streak: int, ideal_weeks: int) -> list[dict]:
        """Все достижения — полученные и будущие — с прогрессом к цели."""
        progress_by_code = {
            'first_workout': (self.total_completed_workouts, 1),
            'ten_workouts': (self.total_completed_workouts, 10),
            'twenty_five_workouts': (self.total_completed_workouts, 25),
            'fifty_workouts': (self.total_completed_workouts, 50),
            'hundred_workouts': (self.total_completed_workouts, 100),
            'first_pr': (len(self.record_events), 1),
            'five_prs': (len(self.record_events), 5),
            'ten_prs': (len(self.record_events), 10),
            'twenty_five_prs': (len(self.record_events), 25),
            'fifty_prs': (len(self.record_events), 50),
            'streak_4_weeks': (best_streak, 4),
            'streak_8_weeks': (best_streak, 8),
            'streak_12_weeks': (best_streak, 12),
            'ten_ideal_weeks': (ideal_weeks, 10),
            'two_fifty_workouts': (self.total_completed_workouts, 250),
            'five_hundred_workouts': (self.total_completed_workouts, 500),
            'hundred_prs': (len(self.record_events), 100),
            'two_fifty_prs': (len(self.record_events), 250),
            'streak_26_weeks': (best_streak, 26),
            'streak_52_weeks': (best_streak, 52),
            'tonnage_100t': (int(self.total_tonnage / 1000), 100),
            'tonnage_500t': (int(self.total_tonnage / 1000), 500),
            'tonnage_1000t': (int(self.total_tonnage / 1000), 1000),
        }
        catalog = []
        for code in _ACHIEVEMENT_ORDER:
            achieved = self.achievements.get(code)
            current, target = progress_by_code.get(code, (1 if achieved else 0, 1))
            catalog.append({
                'code': code,
                'title': _achievement_title(code),
                'description': _ACHIEVEMENT_DESCRIPTIONS.get(code, ''),
                'unlocked': achieved is not None,
                'achievedAt': achieved.achieved_at.isoformat() if achieved else None,
                'progress': min(current, target),
                'target': target,
            })
        return catalog + self._club_catalog()

    def _reward_once(
        self,
        *,
        event_key: str,
        event_type: str,
        xp_awarded: int,
        created_at: datetime,
        metadata: dict | None = None,
    ) -> None:
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        self.reward_events.setdefault(
            event_key,
            RewardEventData(
                event_key=event_key,
                event_type=event_type,
                xp_awarded=xp_awarded,
                created_at=created_at,
                metadata=metadata,
            ),
        )

    def _xp_for(self, code: str, achieved_at: datetime) -> int:
        if achieved_at.tzinfo is None:
            # SQLite (локальная разработка) отдаёт даты без часового пояса.
            achieved_at = achieved_at.replace(tzinfo=timezone.utc)
        table = _REBALANCED_XP if achieved_at >= _XP_REBALANCE_EFFECTIVE_AT else _LEGACY_XP
        return table.get(code, 0)

    def _volume_bonus_xp(self, working_sets: int, achieved_at: datetime) -> int:
        if working_sets >= 20:
            return self._xp_for('workout_volume_bonus_20', achieved_at)
        if working_sets >= 15:
            return self._xp_for('workout_volume_bonus_15', achieved_at)
        if working_sets >= 10:
            return self._xp_for('workout_volume_bonus_10', achieved_at)
        return 0

    def _achievement_once(self, *, code: str, achieved_at: datetime, metadata: dict | None = None) -> None:
        if achieved_at.tzinfo is None:
            achieved_at = achieved_at.replace(tzinfo=timezone.utc)
        self.achievements.setdefault(
            code,
            AchievementData(code=code, achieved_at=achieved_at, metadata=metadata),
        )

    def _is_valid_workout(self, workout: Workout) -> bool:
        working_sets = self._working_sets_count(workout)
        exercises_with_sets = sum(
            1 for exercise in workout.exercises if any(_is_working_set(set_item) for set_item in exercise.sets)
        )
        return working_sets >= 3 or exercises_with_sets >= 2

    def _working_sets_count(self, workout: Workout) -> int:
        return sum(
            1
            for exercise in workout.exercises
            for set_item in exercise.sets
            if _is_working_set(set_item)
        )

    def _has_sick_leave_between(self, start_day: date, end_day: date) -> bool:
        if start_day > end_day:
            return False
        return any(
            leave.status != 'cancelled'
            and leave.start_date <= end_day
            and leave.end_date >= start_day
            for leave in self.sick_leaves
        )

    def _is_return_after_sick_leave(self, performed_day: date) -> bool:
        for leave in self.sick_leaves:
            if leave.status == 'cancelled' or performed_day <= leave.end_date:
                continue
            previous_after_leave = any(
                workout.finished_at is not None
                and self._is_valid_workout(workout)
                and (workout.finished_at or workout.started_at).date() > leave.end_date
                and (workout.finished_at or workout.started_at).date() < performed_day
                for workout in self.workouts
            )
            if not previous_after_leave:
                return True
        return False

    def _is_week_frozen(self, week_start: date) -> bool:
        week_end = end_of_week(week_start)
        return any(
            leave.status != 'cancelled'
            and leave.start_date <= week_start
            and leave.end_date >= week_end
            for leave in self.sick_leaves
        )

    def _active_sick_leave(self, today: date) -> SickLeave | None:
        candidates = [
            item
            for item in self.sick_leaves
            if item.status != 'cancelled' and item.start_date <= today <= item.end_date
        ]
        if not candidates:
            return None
        return max(candidates, key=lambda value: value.created_at)

    def _has_sick_leave_in_month(self, day: date) -> bool:
        month_start = day.replace(day=1)
        next_month = _next_month(month_start)
        return any(
            item.status != 'cancelled'
            and item.start_date >= month_start
            and item.start_date < next_month
            for item in self.sick_leaves
        )

    def _empty_week_summary(self, week_start: date) -> dict:
        return {
            'weekKey': week_key(week_start),
            'startDate': week_start.isoformat(),
            'endDate': end_of_week(week_start).isoformat(),
            'workoutCount': 0,
            'status': 'regular',
            'isIdeal': False,
            'isFrozen': False,
            'streakEligible': False,
        }

    def _empty_month_summary(self, day: date) -> dict:
        return {
            'monthKey': month_key(day),
            'year': day.year,
            'month': day.month,
            'idealWeeksCount': 0,
            'weeksConsidered': len(month_weeks(day)),
            'isIdeal': False,
            'status': 'в процессе',
        }


def _is_working_set(set_item: ExerciseSet) -> bool:
    return (
        getattr(set_item, 'set_type', 'work') != 'warmup'
        and set_item.reps > 0
        and (set_item.weight or 0) > 0
    )


def _exercise_key(exercise: WorkoutExercise) -> str:
    if exercise.catalog_exercise_id is not None:
        return f'catalog:{exercise.catalog_exercise_id}'
    return f'name:{exercise.exercise_name.strip().lower()}'

def _avatar_text(email: str) -> str:
    local_part = email.split('@')[0].strip()
    return (local_part[:1] if local_part else 'А').upper()


def _serialize_achievement(item: AchievementData) -> dict:
    return {
        'code': item.code,
        'title': _achievement_title(item.code),
        'achievedAt': item.achieved_at.isoformat(),
        'metadata': item.metadata,
    }


def _serialize_exercise_record(item: ExerciseRecordSnapshot) -> dict:
    return {
        'exerciseName': item.exercise_name,
        'bestWeight': round(item.best_weight, 2),
        'best1rm': round(item.best_1rm, 2),
        'bestVolume': round(item.best_volume, 2),
        'bestReps': item.best_reps,
        'bestRepsWeight': round(item.best_reps_weight, 2),
        'updatedAt': item.updated_at.isoformat(),
    }


def _serialize_record(item: RecordEventData) -> dict:
    return {
        'exerciseName': item.exercise_name,
        'recordType': item.record_type,
        'recordLabel': _record_label(item.record_type),
        'value': round(item.value, 2),
        'achievedAt': item.achieved_at.isoformat(),
    }


def _serialize_reward(item: RewardEventData) -> dict:
    return {
        'eventKey': item.event_key,
        'eventType': item.event_type,
        'xpAwarded': item.xp_awarded,
        'createdAt': item.created_at.isoformat(),
        'metadata': item.metadata,
    }


def _serialize_sick_leave(item: SickLeave | None) -> dict | None:
    if item is None:
        return None
    return {
        'id': item.id,
        'startDate': item.start_date.isoformat(),
        'endDate': item.end_date.isoformat(),
        'reason': item.reason,
        'status': item.status,
        'createdAt': item.created_at.isoformat(),
    }


_STREAK_ACHIEVEMENTS = (
    (4, 'streak_4_weeks'),
    (8, 'streak_8_weeks'),
    (12, 'streak_12_weeks'),
    (26, 'streak_26_weeks'),
    (52, 'streak_52_weeks'),
)
_WORKOUT_TIERS = ((100, 'hundred_workouts'), (250, 'two_fifty_workouts'), (500, 'five_hundred_workouts'))
_PR_TIERS = (
    (10, 'ten_prs'),
    (25, 'twenty_five_prs'),
    (50, 'fifty_prs'),
    (100, 'hundred_prs'),
    (250, 'two_fifty_prs'),
)
_TONNAGE_TIERS = ((100, 'tonnage_100t'), (500, 'tonnage_500t'), (1000, 'tonnage_1000t'))

_ACHIEVEMENT_ORDER = (
    'first_workout',
    'ten_workouts',
    'twenty_five_workouts',
    'fifty_workouts',
    'hundred_workouts',
    'two_fifty_workouts',
    'five_hundred_workouts',
    'good_week',
    'ideal_week',
    'streak_4_weeks',
    'streak_8_weeks',
    'streak_12_weeks',
    'streak_26_weeks',
    'streak_52_weeks',
    'ten_ideal_weeks',
    'quest_week_all',
    'first_perfect_month',
    'first_pr',
    'five_prs',
    'ten_prs',
    'twenty_five_prs',
    'fifty_prs',
    'hundred_prs',
    'two_fifty_prs',
    'tonnage_100t',
    'tonnage_500t',
    'tonnage_1000t',
    'high_volume_session',
    'comeback_after_break',
    'return_after_sick_leave',
)

_ACHIEVEMENT_DESCRIPTIONS = {
    'first_workout': 'Завершите первую тренировку',
    'ten_workouts': 'Завершите 10 тренировок',
    'twenty_five_workouts': 'Завершите 25 тренировок',
    'fifty_workouts': 'Завершите 50 тренировок',
    'hundred_workouts': 'Завершите 100 тренировок',
    'good_week': '2 тренировки за неделю',
    'ideal_week': '3 тренировки за неделю',
    'streak_4_weeks': '4 недели подряд по 2+ тренировки',
    'streak_8_weeks': '8 недель подряд по 2+ тренировки',
    'streak_12_weeks': '12 недель подряд по 2+ тренировки',
    'ten_ideal_weeks': '10 недель с 3+ тренировками',
    'first_perfect_month': 'Все недели месяца — идеальные',
    'first_pr': 'Побейте первый личный рекорд',
    'five_prs': '5 личных рекордов',
    'ten_prs': '10 личных рекордов',
    'twenty_five_prs': '25 личных рекордов',
    'fifty_prs': '50 личных рекордов',
    'hundred_prs': '100 личных рекордов',
    'two_fifty_prs': '250 личных рекордов',
    'two_fifty_workouts': 'Завершите 250 тренировок',
    'five_hundred_workouts': 'Завершите 500 тренировок',
    'streak_26_weeks': 'Полгода подряд по 2+ тренировки в неделю',
    'streak_52_weeks': 'Год подряд по 2+ тренировки в неделю',
    'tonnage_100t': 'Поднимите 100 тонн за всё время',
    'tonnage_500t': 'Поднимите 500 тонн за всё время',
    'tonnage_1000t': 'Поднимите 1000 тонн за всё время',
    'quest_week_all': 'Выполните все три задания недели',
    'high_volume_session': '20+ рабочих подходов за тренировку',
    'comeback_after_break': 'Вернитесь после паузы в 10+ дней',
    'return_after_sick_leave': 'Первая тренировка после больничного',
}


def _achievement_title(code: str) -> str:
    return {
        'first_workout': 'Первая тренировка',
        'hundred_workouts': '100 тренировок',
        'ten_prs': '10 рекордов',
        'twenty_five_prs': '25 рекордов',
        'fifty_prs': '50 рекордов',
        'streak_4_weeks': 'Серия 4 недели',
        'streak_8_weeks': 'Серия 8 недель',
        'streak_12_weeks': 'Серия 12 недель',
        'ten_ideal_weeks': '10 идеальных недель',
        'two_fifty_workouts': '250 тренировок',
        'five_hundred_workouts': '500 тренировок',
        'hundred_prs': '100 рекордов',
        'two_fifty_prs': '250 рекордов',
        'streak_26_weeks': 'Серия полгода',
        'streak_52_weeks': 'Серия год',
        'tonnage_100t': '100 тонн',
        'tonnage_500t': '500 тонн',
        'tonnage_1000t': '1000 тонн',
        'quest_week_all': 'Неделя заданий',
        'good_week': 'Хорошая неделя',
        'ideal_week': 'Идеальная неделя',
        'first_perfect_month': 'Первый идеальный месяц',
        'ten_workouts': '10 тренировок',
        'twenty_five_workouts': '25 тренировок',
        'fifty_workouts': '50 тренировок',
        'first_pr': 'Первый рекорд',
        'five_prs': '5 рекордов',
        'high_volume_session': '20 рабочих подходов',
        'comeback_after_break': 'Первая тренировка после паузы',
        'return_after_sick_leave': 'Возвращение после больничного',
    }.get(code) or gamification.club_title(code) or code


def _record_label(record_type: str) -> str:
    return {
        'weight': 'Рекорд веса',
        '1rm': 'Рекорд 1ПМ',
        'volume': 'Рекорд объёма',
        'reps': 'Рекорд повторений',
    }.get(record_type, record_type)


def _end_of_day(day: date) -> datetime:
    return datetime(day.year, day.month, day.day, 23, 59, 59, tzinfo=timezone.utc)


def _next_month(day: date) -> date:
    if day.month == 12:
        return date(day.year + 1, 1, 1)
    return date(day.year, day.month + 1, 1)


def _month_end(day: date) -> date:
    return _next_month(day.replace(day=1)) - timedelta(days=1)
