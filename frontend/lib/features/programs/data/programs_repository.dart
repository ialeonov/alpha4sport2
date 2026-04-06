import 'dart:convert';

import 'package:flutter/services.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum ProgramLevel { beginner, intermediate, advanced }

// ─── Models ───────────────────────────────────────────────────────────────────

class ProgramExercise {
  const ProgramExercise({
    required this.slug,
    required this.name,
    required this.sets,
    required this.reps,
    this.rpe,
    this.notes,
    this.supersetGroup,
  });

  final String slug;
  final String name;
  final int sets;
  final String reps;
  final int? rpe;
  final String? notes;
  final int? supersetGroup;

  factory ProgramExercise.fromJson(Map<String, dynamic> json) =>
      ProgramExercise(
        slug: (json['exercise_slug'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        sets: (json['sets'] as num?)?.toInt() ?? 3,
        reps: (json['reps'] ?? '8').toString(),
        rpe: (json['rpe'] as num?)?.toInt(),
        notes: json['notes'] as String?,
        supersetGroup: (json['superset_group'] as num?)?.toInt(),
      );
}

class ProgramWorkout {
  const ProgramWorkout({
    required this.day,
    required this.name,
    required this.exercises,
  });

  final int day;
  final String name;
  final List<ProgramExercise> exercises;

  factory ProgramWorkout.fromJson(Map<String, dynamic> json) => ProgramWorkout(
        day: (json['day'] as num?)?.toInt() ?? 1,
        name: (json['name'] ?? '').toString(),
        exercises: ((json['exercises'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(ProgramExercise.fromJson)
            .toList(),
      );
}

class Program {
  const Program({
    required this.id,
    required this.name,
    required this.author,
    required this.level,
    required this.goal,
    required this.gender,
    required this.location,
    required this.daysPerWeek,
    required this.durationWeeks,
    required this.description,
    required this.workouts,
    this.notes,
    this.splitType,
  });

  final String id;
  final String name;
  final String author;
  final ProgramLevel level;
  final String goal;
  final String gender;
  final String location;
  final int daysPerWeek;
  final int durationWeeks;
  final String description;
  final String? notes;
  final String? splitType;
  final List<ProgramWorkout> workouts;

  static ProgramLevel _parseLevel(String value) =>
      switch (value.trim().toLowerCase()) {
        'beginner' || 'начальный' => ProgramLevel.beginner,
        'intermediate' || 'средний' => ProgramLevel.intermediate,
        'advanced' || 'продвинутый' => ProgramLevel.advanced,
        _ => ProgramLevel.beginner,
      };

  factory Program.fromJson(Map<String, dynamic> json) => Program(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        author: (json['author'] ?? '').toString(),
        level: _parseLevel((json['level'] ?? '').toString()),
        goal: (json['goal'] ?? '').toString(),
        gender: (json['gender'] ?? '').toString(),
        location: (json['location'] ?? '').toString(),
        daysPerWeek: (json['days_per_week'] as num?)?.toInt() ?? 3,
        durationWeeks: (json['duration_weeks'] as num?)?.toInt() ?? 8,
        description: (json['description'] ?? '').toString(),
        notes: json['notes'] as String?,
        splitType: json['split_type'] as String?,
        workouts: ((json['workouts'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(ProgramWorkout.fromJson)
            .toList(),
      );
}

// ─── Custom program (from templates) ─────────────────────────────────────────

class CustomProgram {
  const CustomProgram({
    required this.id,
    required this.name,
    required this.days,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<CustomProgramDay> days;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'days': days.map((d) => d.toJson()).toList(),
        'created_at': createdAt,
      };

  factory CustomProgram.fromJson(Map<String, dynamic> json) => CustomProgram(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        createdAt: (json['created_at'] ?? '').toString(),
        days: ((json['days'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(CustomProgramDay.fromJson)
            .toList(),
      );
}

class CustomProgramDay {
  const CustomProgramDay({
    required this.day,
    required this.templateId,
    required this.templateName,
  });

  final int day;
  final int templateId;
  final String templateName;

  Map<String, dynamic> toJson() => {
        'day': day,
        'template_id': templateId,
        'template_name': templateName,
      };

  factory CustomProgramDay.fromJson(Map<String, dynamic> json) =>
      CustomProgramDay(
        day: (json['day'] as num?)?.toInt() ?? 1,
        templateId: (json['template_id'] as num?)?.toInt() ?? 0,
        templateName: (json['template_name'] ?? '').toString(),
      );
}

// ─── Repository ───────────────────────────────────────────────────────────────

class ProgramsRepository {
  static const _indexAsset = 'assets/programs/index.json';

  static Future<List<Program>> loadAll() async {
    final indexJson = await rootBundle.loadString(_indexAsset);
    final index = jsonDecode(indexJson) as Map<String, dynamic>;
    final summaries =
        (index['programs'] as List).cast<Map<String, dynamic>>();

    final programs = await Future.wait(
      summaries.map((s) => _loadOne((s['id'] as String?)?.trim() ?? '')),
    );
    return programs;
  }

  static Future<Program> _loadOne(String id) async {
    final raw = await rootBundle.loadString('assets/programs/$id.json');
    return Program.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

// ─── Share codes ─────────────────────────────────────────────────────────────
// Pre-generated random codes — stable across all devices/users (no server needed).
// Programs are static assets identical for every user, so the mapping is fixed.

const Map<String, String> programShareCodes = {
  'program_001': 'K7mxQp2N',
  'program_002': 'Rj8wLn4V',
  'program_003': 'Tz3vBs6Y',
  'program_004': 'Xf5nKq9A',
  'program_005': 'Hp2cMw7E',
  'program_006': 'Dk4gRt1C',
  'program_007': 'Nm6jFx8P',
  'program_008': 'Bv9kWs3L',
  'program_009': 'Qy7mTn2R',
  'program_010': 'Cs1pJv6G',
  'program_011': 'Wl4hZb8U',
  'program_012': 'Ux3rYq5O',
};

// Reverse lookup: share code → program id
final Map<String, String> programIdByShareCode = {
  for (final e in programShareCodes.entries) e.value: e.key,
};

// ─── Display helpers ──────────────────────────────────────────────────────────

String programLevelLabel(ProgramLevel level) => switch (level) {
      ProgramLevel.beginner => 'Новичок',
      ProgramLevel.intermediate => 'Средний',
      ProgramLevel.advanced => 'Продвинутый',
    };

String programGoalLabel(String goal) => switch (goal.toLowerCase()) {
      'strength_mass' || 'масса_и_сила' => 'Сила и масса',
      'strength' || 'сила' => 'Сила',
      'масса' || 'mass' => 'Масса',
      'fat_loss' || 'рельеф' => 'Рельеф',
      'body_shaping' || 'форма' => 'Форма тела',
      _ => goal,
    };

String programGenderLabel(String gender) => switch (gender.toLowerCase()) {
      'male' || 'м' => 'М',
      'female' || 'ж' => 'Ж',
      'any' || 'м_ж' || 'all' => 'М/Ж',
      _ => gender,
    };
