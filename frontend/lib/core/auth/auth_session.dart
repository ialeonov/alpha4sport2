import 'package:flutter/foundation.dart';

import '../storage/local_cache.dart';

class AuthSession extends ChangeNotifier {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;

  void restoreFromCache() {
    final token = LocalCache.get<String>(CacheKeys.token);
    _isAuthenticated = token != null && token.isNotEmpty;
  }

  void markAuthenticated() {
    _setAuthenticated(true);
  }

  Future<void> logout() async {
    await LocalCache.clearSessionData();
    _setAuthenticated(false);
  }

  Future<void> expireSession() async {
    await LocalCache.clearSessionData();
    _setAuthenticated(false);
  }

  void _setAuthenticated(bool value) {
    if (_isAuthenticated == value) {
      return;
    }
    _isAuthenticated = value;
    notifyListeners();
  }
}
