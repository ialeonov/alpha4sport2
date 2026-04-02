import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_session.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_notifier.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/startup_screen.dart';
import 'features/home/presentation/home_screen.dart';

class Alpha4SportApp extends StatefulWidget {
  const Alpha4SportApp({super.key});

  @override
  State<Alpha4SportApp> createState() => _Alpha4SportAppState();
}

class _Alpha4SportAppState extends State<Alpha4SportApp> {
  final _themeNotifier = ThemeNotifier.instance;

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _themeNotifier.addListener(_onThemeChanged);
    _router = GoRouter(
      refreshListenable: AuthSession.instance,
      routes: [
        GoRoute(path: '/', builder: (context, state) => const StartupScreen()),
        GoRoute(
            path: '/login', builder: (context, state) => const LoginScreen()),
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      ],
      redirect: (context, state) {
        final loggedIn = AuthSession.instance.isAuthenticated;
        if (!loggedIn && state.matchedLocation == '/home') return '/login';
        if (loggedIn && state.matchedLocation == '/login') return '/home';
        return null;
      },
    );
  }

  @override
  void dispose() {
    _themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Путь Силы',
      locale: const Locale('ru'),
      supportedLocales: const [
        Locale('ru'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _themeNotifier.mode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.theme(),
      routerConfig: _router,
    );
  }
}
