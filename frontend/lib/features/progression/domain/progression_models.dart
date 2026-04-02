class ProgressionProfileData {
  const ProgressionProfileData({
    required this.displayName,
    required this.email,
    required this.avatarText,
    required this.avatarUrl,
    required this.totalXp,
    required this.level,
    required this.levelStartXp,
    required this.nextLevelXp,
    required this.xpInLevel,
    required this.xpRemainingToNextLevel,
    required this.title,
    required this.currentStreak,
    required this.bestStreak,
    required this.totalCompletedWorkouts,
    required this.totalPrCount,
    required this.idealWeeksCount,
    required this.idealMonthsCount,
    required this.totalLikesReceived,
    required this.currentWeek,
    required this.currentMonth,
    required this.recentAchievements,
    required this.recentRecords,
    required this.allExerciseRecords,
    required this.recentRewards,
    required this.sickLeave,
  });

  final String displayName;
  final String email;
  final String avatarText;
  final String? avatarUrl;
  final int totalXp;
  final int level;
  final int levelStartXp;
  final int nextLevelXp;
  final int xpInLevel;
  final int xpRemainingToNextLevel;
  final String title;
  final int currentStreak;
  final int bestStreak;
  final int totalCompletedWorkouts;
  final int totalPrCount;
  final int idealWeeksCount;
  final int idealMonthsCount;
  final int totalLikesReceived;
  final WeekProgressData currentWeek;
  final MonthProgressData currentMonth;
  final List<AchievementData> recentAchievements;
  final List<RecordData> recentRecords;
  final List<ExerciseRecordData> allExerciseRecords;
  final List<RewardData> recentRewards;
  final SickLeaveSectionData sickLeave;

  int get xpToDisplay => nextLevelXp - levelStartXp;
  double get levelProgress =>
      xpToDisplay <= 0 ? 0 : (xpInLevel / xpToDisplay).clamp(0, 1);

  factory ProgressionProfileData.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map).cast<String, dynamic>();
    final profile = (json['profile'] as Map).cast<String, dynamic>();
    return ProgressionProfileData(
      displayName: (user['displayName'] ?? 'Атлет').toString(),
      email: (user['email'] ?? '').toString(),
      avatarText: (user['avatarText'] ?? 'A').toString(),
      avatarUrl: user['avatarUrl']?.toString(),
      totalXp: (profile['totalXp'] as num?)?.toInt() ?? 0,
      level: (profile['level'] as num?)?.toInt() ?? 1,
      levelStartXp: (profile['levelStartXp'] as num?)?.toInt() ?? 0,
      nextLevelXp: (profile['nextLevelXp'] as num?)?.toInt() ?? 100,
      xpInLevel: (profile['xpInLevel'] as num?)?.toInt() ?? 0,
      xpRemainingToNextLevel:
          (profile['xpRemainingToNextLevel'] as num?)?.toInt() ?? 0,
      title: (profile['title'] ?? 'Новичок').toString(),
      currentStreak: (profile['currentStreak'] as num?)?.toInt() ?? 0,
      bestStreak: (profile['bestStreak'] as num?)?.toInt() ?? 0,
      totalCompletedWorkouts:
          (profile['totalCompletedWorkouts'] as num?)?.toInt() ?? 0,
      totalPrCount: (profile['totalPrCount'] as num?)?.toInt() ?? 0,
      idealWeeksCount: (profile['idealWeeksCount'] as num?)?.toInt() ?? 0,
      idealMonthsCount: (profile['idealMonthsCount'] as num?)?.toInt() ?? 0,
      totalLikesReceived: (profile['totalLikesReceived'] as num?)?.toInt() ?? 0,
      currentWeek: WeekProgressData.fromJson(
        (json['currentWeek'] as Map).cast<String, dynamic>(),
      ),
      currentMonth: MonthProgressData.fromJson(
        (json['currentMonth'] as Map).cast<String, dynamic>(),
      ),
      recentAchievements: ((json['recentAchievements'] as List?) ?? const [])
          .cast<Map>()
          .map((item) => AchievementData.fromJson(item.cast<String, dynamic>()))
          .toList(),
      recentRecords: ((json['recentRecords'] as List?) ?? const [])
          .cast<Map>()
          .map((item) => RecordData.fromJson(item.cast<String, dynamic>()))
          .toList(),
      allExerciseRecords: ((json['allExerciseRecords'] as List?) ?? const [])
          .cast<Map>()
          .map((item) => ExerciseRecordData.fromJson(item.cast<String, dynamic>()))
          .toList(),
      recentRewards: ((json['recentRewards'] as List?) ?? const [])
          .cast<Map>()
          .map((item) => RewardData.fromJson(item.cast<String, dynamic>()))
          .toList(),
      sickLeave: SickLeaveSectionData.fromJson(
        (json['sickLeave'] as Map).cast<String, dynamic>(),
      ),
    );
  }
}

class WeekProgressData {
  const WeekProgressData({
    required this.weekKey,
    required this.startDate,
    required this.endDate,
    required this.workoutCount,
    required this.status,
    required this.isIdeal,
    required this.isFrozen,
    required this.streakEligible,
  });

  final String weekKey;
  final DateTime startDate;
  final DateTime endDate;
  final int workoutCount;
  final String status;
  final bool isIdeal;
  final bool isFrozen;
  final bool streakEligible;

  factory WeekProgressData.fromJson(Map<String, dynamic> json) {
    return WeekProgressData(
      weekKey: (json['weekKey'] ?? '').toString(),
      startDate: DateTime.parse((json['startDate'] ?? '').toString()).toLocal(),
      endDate: DateTime.parse((json['endDate'] ?? '').toString()).toLocal(),
      workoutCount: (json['workoutCount'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? 'regular').toString(),
      isIdeal: json['isIdeal'] == true,
      isFrozen: json['isFrozen'] == true,
      streakEligible: json['streakEligible'] == true,
    );
  }
}

class MonthProgressData {
  const MonthProgressData({
    required this.monthKey,
    required this.year,
    required this.month,
    required this.idealWeeksCount,
    required this.weeksConsidered,
    required this.isIdeal,
    required this.status,
  });

  final String monthKey;
  final int year;
  final int month;
  final int idealWeeksCount;
  final int weeksConsidered;
  final bool isIdeal;
  final String status;

  factory MonthProgressData.fromJson(Map<String, dynamic> json) {
    return MonthProgressData(
      monthKey: (json['monthKey'] ?? '').toString(),
      year: (json['year'] as num?)?.toInt() ?? DateTime.now().year,
      month: (json['month'] as num?)?.toInt() ?? DateTime.now().month,
      idealWeeksCount: (json['idealWeeksCount'] as num?)?.toInt() ?? 0,
      weeksConsidered: (json['weeksConsidered'] as num?)?.toInt() ?? 0,
      isIdeal: json['isIdeal'] == true,
      status: (json['status'] ?? '').toString(),
    );
  }
}

class AchievementData {
  const AchievementData({
    required this.code,
    required this.title,
    required this.achievedAt,
  });

  final String code;
  final String title;
  final DateTime achievedAt;

  factory AchievementData.fromJson(Map<String, dynamic> json) {
    return AchievementData(
      code: (json['code'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      achievedAt: DateTime.parse((json['achievedAt'] ?? '').toString()).toLocal(),
    );
  }
}

class RecordData {
  const RecordData({
    required this.exerciseName,
    required this.recordType,
    required this.recordLabel,
    required this.value,
    required this.achievedAt,
  });

  final String exerciseName;
  final String recordType;
  final String recordLabel;
  final double value;
  final DateTime achievedAt;

  factory RecordData.fromJson(Map<String, dynamic> json) {
    return RecordData(
      exerciseName: (json['exerciseName'] ?? '').toString(),
      recordType: (json['recordType'] ?? '').toString(),
      recordLabel: (json['recordLabel'] ?? '').toString(),
      value: (json['value'] as num?)?.toDouble() ?? 0,
      achievedAt: DateTime.parse((json['achievedAt'] ?? '').toString()).toLocal(),
    );
  }
}

class ExerciseRecordData {
  const ExerciseRecordData({
    required this.exerciseName,
    required this.bestWeight,
    required this.best1rm,
    required this.bestVolume,
    required this.updatedAt,
  });

  final String exerciseName;
  final double bestWeight;
  final double best1rm;
  final double bestVolume;
  final DateTime updatedAt;

  factory ExerciseRecordData.fromJson(Map<String, dynamic> json) {
    return ExerciseRecordData(
      exerciseName: (json['exerciseName'] ?? '').toString(),
      bestWeight: (json['bestWeight'] as num?)?.toDouble() ?? 0,
      best1rm: (json['best1rm'] as num?)?.toDouble() ?? 0,
      bestVolume: (json['bestVolume'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.parse((json['updatedAt'] ?? '').toString()).toLocal(),
    );
  }
}

class RewardData {
  const RewardData({
    required this.eventKey,
    required this.eventType,
    required this.xpAwarded,
    required this.createdAt,
  });

  final String eventKey;
  final String eventType;
  final int xpAwarded;
  final DateTime createdAt;

  factory RewardData.fromJson(Map<String, dynamic> json) {
    return RewardData(
      eventKey: (json['eventKey'] ?? '').toString(),
      eventType: (json['eventType'] ?? '').toString(),
      xpAwarded: (json['xpAwarded'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse((json['createdAt'] ?? '').toString()).toLocal(),
    );
  }
}

class SickLeaveSectionData {
  const SickLeaveSectionData({
    required this.active,
    required this.remainingEpisodesThisMonth,
    required this.allowedEpisodesPerMonth,
    required this.maxDaysPerEpisode,
    required this.history,
  });

  final SickLeaveData? active;
  final int remainingEpisodesThisMonth;
  final int allowedEpisodesPerMonth;
  final int maxDaysPerEpisode;
  final List<SickLeaveData> history;

  factory SickLeaveSectionData.fromJson(Map<String, dynamic> json) {
    final activeJson = json['active'];
    return SickLeaveSectionData(
      active: activeJson is Map
          ? SickLeaveData.fromJson(activeJson.cast<String, dynamic>())
          : null,
      remainingEpisodesThisMonth:
          (json['remainingEpisodesThisMonth'] as num?)?.toInt() ?? 0,
      allowedEpisodesPerMonth:
          (json['allowedEpisodesPerMonth'] as num?)?.toInt() ?? 1,
      maxDaysPerEpisode: (json['maxDaysPerEpisode'] as num?)?.toInt() ?? 7,
      history: ((json['history'] as List?) ?? const [])
          .cast<Map>()
          .map((item) => SickLeaveData.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class SickLeaveData {
  const SickLeaveData({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;
  final DateTime createdAt;

  factory SickLeaveData.fromJson(Map<String, dynamic> json) {
    return SickLeaveData(
      id: (json['id'] as num?)?.toInt() ?? 0,
      startDate: DateTime.parse((json['startDate'] ?? '').toString()).toLocal(),
      endDate: DateTime.parse((json['endDate'] ?? '').toString()).toLocal(),
      reason: (json['reason'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt: DateTime.parse((json['createdAt'] ?? '').toString()).toLocal(),
    );
  }
}
