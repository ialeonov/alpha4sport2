from datetime import date, datetime

from pydantic import BaseModel, Field


class UserProgressionIdentity(BaseModel):
    displayName: str
    email: str
    avatarText: str
    avatarUrl: str | None = None


class UserProgressionProfile(BaseModel):
    totalXp: int
    level: int
    levelStartXp: int
    nextLevelXp: int
    xpInLevel: int
    xpRemainingToNextLevel: int
    title: str
    currentStreak: int
    bestStreak: int
    totalCompletedWorkouts: int
    totalPrCount: int
    idealWeeksCount: int
    idealMonthsCount: int
    totalLikesReceived: int = 0


class WeekProgressSummary(BaseModel):
    weekKey: str
    startDate: str
    endDate: str
    workoutCount: int
    status: str
    isIdeal: bool
    isFrozen: bool
    streakEligible: bool


class MonthProgressSummary(BaseModel):
    monthKey: str
    year: int
    month: int
    idealWeeksCount: int
    weeksConsidered: int
    isIdeal: bool
    status: str


class ProgressAchievementOut(BaseModel):
    code: str
    title: str
    achievedAt: datetime
    metadata: dict | None = None


class ProgressRecordOut(BaseModel):
    exerciseName: str
    recordType: str
    recordLabel: str
    value: float
    achievedAt: datetime


class ExerciseRecordOut(BaseModel):
    exerciseName: str
    bestWeight: float
    best1rm: float
    bestVolume: float
    updatedAt: datetime


class ProgressRewardOut(BaseModel):
    eventKey: str
    eventType: str
    xpAwarded: int
    createdAt: datetime
    metadata: dict | None = None


class SickLeaveOut(BaseModel):
    id: int
    startDate: date
    endDate: date
    reason: str
    status: str
    createdAt: datetime


class SickLeaveSectionOut(BaseModel):
    active: SickLeaveOut | None = None
    remainingEpisodesThisMonth: int
    allowedEpisodesPerMonth: int
    maxDaysPerEpisode: int
    history: list[SickLeaveOut]


class ProgressionProfileResponse(BaseModel):
    user: UserProgressionIdentity
    profile: UserProgressionProfile
    currentWeek: WeekProgressSummary
    currentMonth: MonthProgressSummary
    recentAchievements: list[ProgressAchievementOut]
    recentRecords: list[ProgressRecordOut]
    allExerciseRecords: list[ExerciseRecordOut]
    recentRewards: list[ProgressRewardOut]
    sickLeave: SickLeaveSectionOut


class SickLeaveCreate(BaseModel):
    startDate: date
    endDate: date
    reason: str = Field(min_length=1, max_length=32)
