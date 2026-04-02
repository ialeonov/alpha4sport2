from dataclasses import dataclass
from datetime import date, timedelta


level_thresholds = [
    0,
    150,
    400,
    800,
    1300,
    1900,
    2600,
    3400,
    4300,
    5300,
]

level_titles = {
    1: 'Новичок',
    2: 'Идущий',
    3: 'Практик',
    4: 'Атлет',
    5: 'Закалённый',
    6: 'Силовик',
    7: 'Ветеран зала',
    8: 'Железный человек',
    9: 'Архитектор силы',
}


def get_level_by_xp(total_xp: int) -> int:
    if total_xp < 0:
        return 1
    for index, threshold in enumerate(level_thresholds, start=1):
        if total_xp < threshold:
            return max(1, index - 1)
    level = len(level_thresholds)
    next_threshold = level_thresholds[-1]
    gap = 1100
    while total_xp >= next_threshold:
        level += 1
        next_threshold += gap
        gap += 100
    return level - 1


def get_level_start_xp(level: int) -> int:
    if level <= 1:
        return 0
    if level <= len(level_thresholds):
        return level_thresholds[level - 1]
    return _extended_level_bounds(level)[0]


def get_next_level_xp(level: int) -> int:
    if level < len(level_thresholds):
        return level_thresholds[level]
    return _extended_level_bounds(level)[1]


def _extended_level_bounds(level: int) -> tuple[int, int]:
    start_xp = level_thresholds[-1]
    next_xp = start_xp + 1100
    current_level = 10
    while current_level < level:
        start_xp = next_xp
        gap = 1100 + (current_level - 9) * 100
        next_xp = start_xp + gap
        current_level += 1
    return start_xp, next_xp


def get_xp_progress_in_level(total_xp: int) -> int:
    level = get_level_by_xp(total_xp)
    return total_xp - get_level_start_xp(level)


def get_xp_remaining_to_next_level(total_xp: int) -> int:
    level = get_level_by_xp(total_xp)
    return max(0, get_next_level_xp(level) - total_xp)


def get_title_by_level(level: int) -> str:
    return level_titles.get(level, 'Мастер дисциплины')


def estimate_one_rep_max(weight: float, reps: int) -> float:
    if weight <= 0 or reps <= 0:
        return 0
    return weight * (1 + reps / 30)


def start_of_week(day: date) -> date:
    return day - timedelta(days=day.weekday())


def end_of_week(day: date) -> date:
    return start_of_week(day) + timedelta(days=6)


def week_key(day: date) -> str:
    iso_year, iso_week, _ = day.isocalendar()
    return f'{iso_year}-W{iso_week:02d}'


def month_key(day: date) -> str:
    return f'{day.year}-{day.month:02d}'


def month_weeks(month_day: date) -> list[date]:
    first_day = month_day.replace(day=1)
    week_start = start_of_week(first_day)
    starts: list[date] = []
    while week_start.month == first_day.month or (week_start + timedelta(days=3)).month == first_day.month:
        if week_start.month == first_day.month:
            starts.append(week_start)
        week_start += timedelta(days=7)
    return starts


@dataclass(frozen=True)
class WeekWindow:
    start: date
    end: date


def build_week_window(day: date) -> WeekWindow:
    return WeekWindow(start=start_of_week(day), end=end_of_week(day))
