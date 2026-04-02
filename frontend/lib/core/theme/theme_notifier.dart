import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../storage/local_cache.dart';

class ThemeNotifier extends ChangeNotifier {
  static final instance = ThemeNotifier._();

  static const _cacheKey = 'app_theme_mode';

  late ThemeMode _mode;

  ThemeNotifier._() {
    final saved = LocalCache.get<String>(_cacheKey);
    if (saved == 'light') {
      _mode = ThemeMode.light;
    } else if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      final brightness =
          SchedulerBinding.instance.platformDispatcher.platformBrightness;
      _mode = brightness == Brightness.light ? ThemeMode.light : ThemeMode.dark;
    }
  }

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> toggleTheme() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await LocalCache.put(_cacheKey, _mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
}
