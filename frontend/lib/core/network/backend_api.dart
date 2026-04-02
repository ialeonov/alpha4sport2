import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import '../storage/local_cache.dart';
import 'backend_api_exception.dart';

class BackendApi {
  static const productionBaseUrl = 'https://fit.ileonov.ru';
  static const developmentBaseUrl = 'http://localhost:8000';

  static String get defaultBaseUrl =>
      kReleaseMode ? productionBaseUrl : developmentBaseUrl;

  static String get configuredBaseUrl {
    final storedBaseUrl = LocalCache.get<String>(CacheKeys.baseUrl);
    if (storedBaseUrl == null || storedBaseUrl.trim().isEmpty) {
      return defaultBaseUrl;
    }
    return _normalizeBaseUrl(storedBaseUrl);
  }

  static String get configuredAssetBaseUrl {
    final baseUrl = configuredBaseUrl;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return baseUrl;
    }

    final buffer = StringBuffer('${uri.scheme}://${uri.host}');
    if (uri.hasPort) {
      buffer.write(':${uri.port}');
    }
    return buffer.toString();
  }

  static Future<void> initializeBaseUrl() async {
    final storedBaseUrl = LocalCache.get<String>(CacheKeys.baseUrl);
    if (storedBaseUrl == null || storedBaseUrl.trim().isEmpty) {
      await LocalCache.put(CacheKeys.baseUrl, defaultBaseUrl);
    }
  }

  static String _normalizeBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static Dio _dio(String baseUrl, {String? token}) {
    return Dio(
      BaseOptions(
        baseUrl: _normalizeBaseUrl(baseUrl),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
      ),
    );
  }

  static Never _throwFriendlyError(
    DioException error, {
    String defaultMessage = 'Не удалось выполнить запрос к серверу.',
    bool handleUnauthorized = true,
  }) {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;
    final responseDetail =
        responseData is Map ? responseData['detail']?.toString() : null;

    if (statusCode == 401 &&
        handleUnauthorized &&
        responseDetail != 'Incorrect email or password') {
      unawaited(AuthSession.instance.expireSession());
      throw const BackendApiException(
          'Сессия истекла. Войдите снова.');
    }

    if (responseDetail != null && responseDetail.isNotEmpty) {
      switch (responseDetail) {
        case 'Workout not found':
          throw const BackendApiException('Тренировка не найдена.');
        case 'Упражнение не найдено':
        case 'Exercise not found':
          throw const BackendApiException('Упражнение не найдено.');
        case 'Template not found':
          throw const BackendApiException('Шаблон не найден.');
        case 'Упражнение уже существует':
        case 'Exercise already exists':
          throw const BackendApiException(
              'Упражнение с таким названием уже существует.');
        case 'Название упражнения обязательно':
        case 'Exercise name is required':
          throw const BackendApiException('Название упражнения обязательно.');
        case 'Body entry not found':
          throw const BackendApiException('Запись параметров тела не найдена.');
        case 'Больничный не найден.':
          throw const BackendApiException('Больничный не найден.');
        case 'В этом месяце уже использован доступный больничный эпизод.':
        case 'Максимальная длительность больничного в MVP — 7 дней.':
        case 'Дата окончания не может быть раньше даты начала.':
        case 'Некорректная причина больничного.':
          throw BackendApiException(responseDetail);
        case 'Incorrect email or password':
          throw const BackendApiException(
              'Неверный email или пароль.');
        default:
          throw BackendApiException(responseDetail);
      }
    }

    if (statusCode == 401) {
      throw const BackendApiException('Неверный email или пароль.');
    }
    if (statusCode == 403) {
      throw const BackendApiException('Доступ запрещён.');
    }
    if (statusCode == 409) {
      throw const BackendApiException(
          'Пользователь с таким email уже существует.');
    }
    if (statusCode == 404) {
      throw const BackendApiException('Адрес сервера или метод API не найден.');
    }
    if (statusCode != null && statusCode >= 500) {
      throw const BackendApiException(
          'Сервер временно недоступен. Попробуйте позже.');
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        throw const BackendApiException('Сервер не ответил вовремя.');
      case DioExceptionType.connectionError:
        throw const BackendApiException(
            'Нет соединения с сервером. Проверьте адрес API.');
      case DioExceptionType.cancel:
        throw const BackendApiException('Запрос был отменён.');
      case DioExceptionType.badCertificate:
        throw const BackendApiException(
            'Не удалось проверить сертификат сервера.');
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        throw BackendApiException(defaultMessage);
    }
  }

  static String describeError(
    Object error, {
    String fallback = 'Что-то пошло не так. Попробуйте ещё раз.',
  }) {
    if (error is BackendApiException) {
      return error.message;
    }
    return fallback;
  }

  static String _requiredToken() {
    final token = LocalCache.get<String>(CacheKeys.token);
    if (token == null || token.isEmpty) {
      throw const BackendApiException('Сессия истекла. Войдите снова.');
    }
    return token;
  }

  static String _requiredBaseUrl() {
    return configuredBaseUrl;
  }

  static Future<bool> validateSession() async {
    final token = LocalCache.get<String>(CacheKeys.token);
    if (token == null || token.isEmpty) {
      await AuthSession.instance.expireSession();
      return false;
    }

    try {
      final dio = _dio(_requiredBaseUrl(), token: token);
      await dio.get('/api/v1/auth/me');
      AuthSession.instance.markAuthenticated();
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await AuthSession.instance.expireSession();
        return false;
      }
      _throwFriendlyError(
        error,
        defaultMessage: 'Не удалось проверить сессию.',
      );
    }
  }

  static Future<String> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    try {
      final normalizedBaseUrl =
          baseUrl.trim().isEmpty ? defaultBaseUrl : _normalizeBaseUrl(baseUrl);
      final dio = _dio(normalizedBaseUrl);
      final response = await dio.post(
        '/api/v1/auth/login',
        data: {'username': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final token = response.data['access_token'] as String;
      await LocalCache.clearSessionData();
      await LocalCache.put(CacheKeys.baseUrl, normalizedBaseUrl);
      await LocalCache.put(CacheKeys.token, token);
      AuthSession.instance.markAuthenticated();
      return token;
    } on DioException catch (error) {
      _throwFriendlyError(error, defaultMessage: 'Не удалось выполнить вход.');
    }
  }

  static Future<void> logout() async {
    await AuthSession.instance.logout();
  }

  static Future<String> register({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    try {
      final normalizedBaseUrl =
          baseUrl.trim().isEmpty ? defaultBaseUrl : _normalizeBaseUrl(baseUrl);
      final dio = _dio(normalizedBaseUrl);
      final response = await dio.post(
        '/api/v1/auth/register',
        data: {'email': email, 'password': password},
      );
      final token = response.data['access_token'] as String;
      await LocalCache.clearSessionData();
      await LocalCache.put(CacheKeys.baseUrl, normalizedBaseUrl);
      await LocalCache.put(CacheKeys.token, token);
      AuthSession.instance.markAuthenticated();
      return token;
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось зарегистрироваться.');
    }
  }

  static Future<List<Map<String, dynamic>>> getWorkouts() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/workouts');
      final data = (response.data as List).cast<Map<String, dynamic>>();
      await LocalCache.put(CacheKeys.workoutsCache, data);
      return data;
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить тренировки.');
    }
  }

  static Future<Map<String, dynamic>> createWorkout({
    required String name,
    required String exerciseName,
    required int sets,
    required int reps,
    required double weight,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final started = (startedAt ?? DateTime.now()).toUtc();
      final finished =
          (finishedAt ?? started.add(const Duration(hours: 1))).toUtc();
      final payload = {
        'name': name,
        'notes': null,
        'started_at': started.toIso8601String(),
        'finished_at': finished.toIso8601String(),
        'exercises': [
          {
            'exercise_name': exerciseName,
            'position': 1,
            'notes': null,
            'sets': List.generate(
              sets,
              (i) => {
                'position': i + 1,
                'reps': reps,
                'weight': weight,
                'rpe': null,
                'notes': null,
              },
            ),
          }
        ],
      };

      final response = await dio.post('/api/v1/workouts', data: payload);
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось сохранить тренировку.');
    }
  }

  static Future<Map<String, dynamic>> createWorkoutDetailed({
    required String name,
    required List<Map<String, dynamic>> exercises,
    required DateTime startedAt,
    DateTime? finishedAt,
    String? notes,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.post(
        '/api/v1/workouts',
        data: {
          'name': name,
          'notes': notes,
          'started_at': startedAt.toUtc().toIso8601String(),
          'finished_at': finishedAt?.toUtc().toIso8601String(),
          'exercises': exercises,
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось сохранить тренировку.');
    }
  }

  static Future<Map<String, dynamic>> updateWorkout({
    required int workoutId,
    required String name,
    required List<Map<String, dynamic>> exercises,
    required DateTime startedAt,
    DateTime? finishedAt,
    String? notes,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.put(
        '/api/v1/workouts/$workoutId',
        data: {
          'name': name,
          'notes': notes,
          'started_at': startedAt.toUtc().toIso8601String(),
          'finished_at': finishedAt?.toUtc().toIso8601String(),
          'exercises': exercises,
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось обновить тренировку.');
    }
  }

  static Future<void> deleteWorkout(int workoutId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      await dio.delete('/api/v1/workouts/$workoutId');
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось удалить тренировку.');
    }
  }

  static Future<List<Map<String, dynamic>>> getTemplates() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/templates');
      final data = (response.data as List).cast<Map<String, dynamic>>();
      await LocalCache.put(CacheKeys.templatesCache, data);
      return data;
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить шаблоны.');
    }
  }

  static Future<Map<String, dynamic>> createTemplate({
    required String name,
    required List<Map<String, dynamic>> exercises,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final payload = {
        'name': name,
        'notes': null,
        'exercises': List.generate(
          exercises.length,
          (i) => {
            'catalog_exercise_id': exercises[i]['id'],
            'exercise_name': (exercises[i]['name'] ?? '').toString(),
            'position': i + 1,
            'target_sets': 3,
            'target_reps': '6-10',
          },
        ),
      };

      final response = await dio.post('/api/v1/templates', data: payload);
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error, defaultMessage: 'Не удалось создать шаблон.');
    }
  }

  static Future<Map<String, dynamic>> updateTemplate({
    required int templateId,
    required String name,
    required List<Map<String, dynamic>> exercises,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final payload = {
        'name': name,
        'notes': null,
        'exercises': List.generate(
          exercises.length,
          (i) => {
            'catalog_exercise_id': exercises[i]['id'],
            'exercise_name': (exercises[i]['name'] ?? '').toString(),
            'position': i + 1,
            'target_sets': 3,
            'target_reps': '6-10',
          },
        ),
      };

      final response =
          await dio.put('/api/v1/templates/$templateId', data: payload);
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error, defaultMessage: 'Не удалось обновить шаблон.');
    }
  }

  static Future<void> deleteTemplate(int templateId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      await dio.delete('/api/v1/templates/$templateId');
    } on DioException catch (error) {
      _throwFriendlyError(error, defaultMessage: 'Не удалось удалить шаблон.');
    }
  }

  static Future<Map<String, dynamic>> startWorkoutFromTemplate(
      int templateId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response =
          await dio.post('/api/v1/workouts/from-template/$templateId');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось начать тренировку из шаблона.');
    }
  }

  static Future<List<Map<String, dynamic>>> getExercises() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/exercises');
      final data = (response.data as List).cast<Map<String, dynamic>>();
      await LocalCache.put(CacheKeys.exerciseCatalogCache, data);
      return data;
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить каталог упражнений.');
    }
  }

  static Future<List<Map<String, dynamic>>> getRecentExercisePerformances(
    String exerciseName, {
    int limit = 5,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final encodedName = Uri.encodeComponent(exerciseName);
      final response = await dio.get(
        '/api/v1/workouts/previous/$encodedName',
        queryParameters: {'limit': limit},
      );
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (error) {
      _throwFriendlyError(
        error,
        defaultMessage: 'Не удалось загрузить недавнюю историю упражнения.',
      );
    }
  }

  static Future<Map<String, dynamic>> createExercise({
    required String name,
    required String primaryMuscle,
    required List<String> secondaryMuscles,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.post(
        '/api/v1/exercises',
        data: {
          'name': name,
          'primary_muscle': primaryMuscle,
          'secondary_muscles': secondaryMuscles,
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось создать упражнение.');
    }
  }

  static Future<Map<String, dynamic>> updateExercise({
    required int exerciseId,
    required String name,
    required String primaryMuscle,
    required List<String> secondaryMuscles,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.put(
        '/api/v1/exercises/$exerciseId',
        data: {
          'name': name,
          'primary_muscle': primaryMuscle,
          'secondary_muscles': secondaryMuscles,
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось обновить упражнение.');
    }
  }

  static Future<void> deleteExercise(int exerciseId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      await dio.delete('/api/v1/exercises/$exerciseId');
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось удалить упражнение.');
    }
  }

  static Future<List<Map<String, dynamic>>> getBodyEntries() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/body');
      final data = (response.data as List).cast<Map<String, dynamic>>();
      await LocalCache.put(CacheKeys.bodyEntriesCache, data);
      return data;
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить параметры тела.');
    }
  }

  static Future<Map<String, dynamic>> createBodyEntry({
    required DateTime entryDate,
    double? weightKg,
    double? waistCm,
    double? chestCm,
    double? hipsCm,
    String? notes,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.post(
        '/api/v1/body',
        data: {
          'entry_date': entryDate.toIso8601String().split('T').first,
          'weight_kg': weightKg,
          'waist_cm': waistCm,
          'chest_cm': chestCm,
          'hips_cm': hipsCm,
          'notes': notes,
          'photo_path': null,
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось сохранить запись параметров тела.');
    }
  }

  static Future<void> deleteBodyEntry(int entryId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      await dio.delete('/api/v1/body/$entryId');
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось удалить запись параметров тела.');
    }
  }

  static Future<List<Map<String, dynamic>>> getBodyweightTrend(
      {int days = 90}) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/progress/bodyweight-trend',
          queryParameters: {'days': days});
      final data = (response.data as List).cast<Map<String, dynamic>>();
      await LocalCache.put(CacheKeys.bodyweightTrendCache, data);
      return data;
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить динамику веса.');
    }
  }

  static Future<List<Map<String, dynamic>>> getWeeklyVolume() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/progress/weekly-volume');
      final data = (response.data as List).cast<Map<String, dynamic>>();
      await LocalCache.put(CacheKeys.weeklyVolumeCache, data);
      return data;
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить недельный объём.');
    }
  }

  static Future<List<Map<String, dynamic>>> getExerciseProgress(
      String exerciseName) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/progress/exercise/$exerciseName');
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить прогресс упражнения.');
    }
  }

  static Future<Map<String, dynamic>> exportJson() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/export/json');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось экспортировать данные.');
    }
  }

  static Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/auth/me');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить профиль пользователя.');
    }
  }

  static Future<Map<String, dynamic>> getProgressionProfile() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/progression/profile');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить профиль прогресса.');
    }
  }

  static Future<Map<String, dynamic>> createSickLeave({
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.post(
        '/api/v1/progression/sick-leaves',
        data: {
          'startDate': startDate.toIso8601String().split('T').first,
          'endDate': endDate.toIso8601String().split('T').first,
          'reason': reason,
        },
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось оформить больничный.');
    }
  }

  static Future<Map<String, dynamic>> cancelSickLeave(int sickLeaveId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response =
          await dio.post('/api/v1/progression/sick-leaves/$sickLeaveId/cancel');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось отменить больничный.');
    }
  }

  static Future<Map<String, dynamic>> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.post(
        '/api/v1/users/me/avatar',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        }),
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить аватар.');
    }
  }

  static Future<Map<String, dynamic>> updateDisplayName({
    required String displayName,
  }) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.patch(
        '/api/v1/users/me',
        data: {'displayName': displayName},
      );
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось обновить имя пользователя.');
    }
  }

  static Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get('/api/v1/users');
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить список пользователей.');
    }
  }

  static Future<Map<String, dynamic>> getUserPublicProfile(int userId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response =
          await dio.get('/api/v1/progression/profile/$userId');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить профиль пользователя.');
    }
  }

  static Future<List<Map<String, dynamic>>> getAccountEvents(
      {int limit = 40}) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.get(
        '/api/v1/account-events',
        queryParameters: {'limit': limit},
      );
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (error) {
      _throwFriendlyError(error,
          defaultMessage: 'Не удалось загрузить ленту событий.');
    }
  }

  static Future<Map<String, dynamic>> toggleEventLike(int eventId) async {
    try {
      final dio = _dio(_requiredBaseUrl(), token: _requiredToken());
      final response = await dio.post('/api/v1/account-events/$eventId/like');
      return (response.data as Map).cast<String, dynamic>();
    } on DioException catch (error) {
      _throwFriendlyError(error, defaultMessage: 'Не удалось поставить лайк.');
    }
  }
}
