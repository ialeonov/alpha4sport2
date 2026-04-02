import 'package:flutter/foundation.dart';

import '../../../core/network/backend_api.dart';
import '../domain/progression_models.dart';

class ProgressionController extends ChangeNotifier {
  ProgressionController._();

  static final ProgressionController instance = ProgressionController._();

  ProgressionProfileData? _profile;
  bool _loading = false;
  String? _error;

  ProgressionProfileData? get profile => _profile;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (_loading) {
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await BackendApi.getProgressionProfile();
      _profile = ProgressionProfileData.fromJson(data);
    } catch (error) {
      _error = BackendApi.describeError(
        error,
        fallback: 'Не удалось загрузить профиль прогресса.',
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> createSickLeave({
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await BackendApi.createSickLeave(
        startDate: startDate,
        endDate: endDate,
        reason: reason,
      );
      _profile = ProgressionProfileData.fromJson(data);
    } catch (error) {
      _error = BackendApi.describeError(
        error,
        fallback: 'Не удалось оформить больничный.',
      );
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> cancelSickLeave(int sickLeaveId) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await BackendApi.cancelSickLeave(sickLeaveId);
      _profile = ProgressionProfileData.fromJson(data);
    } catch (error) {
      _error = BackendApi.describeError(
        error,
        fallback: 'Не удалось отменить больничный.',
      );
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> uploadAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await BackendApi.uploadAvatar(bytes: bytes, fileName: fileName);
      final data = await BackendApi.getProgressionProfile();
      _profile = ProgressionProfileData.fromJson(data);
    } catch (error) {
      _error = BackendApi.describeError(
        error,
        fallback: 'Не удалось загрузить аватар.',
      );
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> updateDisplayName(String displayName) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await BackendApi.updateDisplayName(displayName: displayName);
      final data = await BackendApi.getProgressionProfile();
      _profile = ProgressionProfileData.fromJson(data);
    } catch (error) {
      _error = BackendApi.describeError(
        error,
        fallback: 'Не удалось обновить имя пользователя.',
      );
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
