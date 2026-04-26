import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../calendar/presentation/calendar_screen.dart';
import '../../more/presentation/more_screen.dart';
import '../../progress/presentation/progress_screen.dart';
import '../../progression/application/progression_controller.dart';
import '../../progression/presentation/progression_compact_badge.dart';
import '../../social/presentation/social_hub_screen.dart';
import '../../today/presentation/today_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _announcementChecked = false;
  final _calendarKey = GlobalKey<CalendarScreenState>();

  @override
  void initState() {
    super.initState();
    Future.microtask(ProgressionController.instance.refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showStartupAnnouncementIfNeeded();
    });
  }

  Future<void> _logout() async {
    await BackendApi.logout();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _openSocialHub() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SocialHubScreen()),
    );
    if (mounted) {
      await ProgressionController.instance.refresh();
    }
  }

  Future<void> _showStartupAnnouncementIfNeeded() async {
    if (_announcementChecked) {
      return;
    }
    _announcementChecked = true;

    try {
      final announcement = await BackendApi.getActiveAnnouncement();
      if (!mounted || announcement == null) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text((announcement['title'] ?? 'Информация').toString()),
          content: SingleChildScrollView(
            child: Text((announcement['body'] ?? '').toString()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Announcement loading should never block the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayScreen(),
      CalendarScreen(key: _calendarKey),
      ProgressScreen(),
      MoreScreen(
        onLogout: _logout,
        onOpenSocialHub: _openSocialHub,
      ),
    ];

    const tabs = [
      (Icons.today_rounded, 'Сегодня'),
      (Icons.calendar_month, 'Журнал'),
      (Icons.bar_chart_rounded, 'Прогресс'),
      (Icons.menu_rounded, 'Меню'),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            ProgressionCompactBadge(
              onTap: () => _openSocialHub(),
            ),
            const Spacer(),
            const _HomeWeeklyStats(),
          ],
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          if (index == 1 && _index != 1) {
            _calendarKey.currentState?.refresh();
          }
          setState(() => _index = index);
        },
        destinations: tabs
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.$1),
                label: item.$2,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _HomeWeeklyStats extends StatelessWidget {
  const _HomeWeeklyStats();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProgressionController.instance,
      builder: (context, _) {
        final rawWorkouts = LocalCache.get<List>(CacheKeys.workoutsCache);
        final workouts = rawWorkouts
                ?.cast<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            const <Map<String, dynamic>>[];

        final now = DateTime.now();
        final weekStart = DateUtils.dateOnly(
          now.subtract(Duration(days: now.weekday - 1)),
        );
        final weekEnd = weekStart.add(const Duration(days: 7));

        int weekCount = 0;
        double tonnage = 0;
        for (final workout in workouts) {
          final startedAt =
              DateTime.tryParse((workout['started_at'] ?? '').toString())
                  ?.toLocal();
          if (startedAt == null ||
              startedAt.isBefore(weekStart) ||
              !startedAt.isBefore(weekEnd)) {
            continue;
          }
          weekCount++;
          for (final raw
              in (workout['exercises'] as List?)?.cast<dynamic>() ??
                  const <dynamic>[]) {
            final ex = (raw as Map).cast<String, dynamic>();
            for (final rawSet
                in (ex['sets'] as List?)?.cast<dynamic>() ??
                    const <dynamic>[]) {
              final s = (rawSet as Map).cast<String, dynamic>();
              if ((s['set_type'] ?? '') == 'warmup') continue;
              final weight = (s['weight'] as num?)?.toDouble() ?? 0;
              final reps = (s['reps'] as num?)?.toInt() ?? 0;
              tonnage += weight * reps;
            }
          }
        }

        if (weekCount == 0 && tonnage == 0) return const SizedBox.shrink();

        final tonnageLabel = tonnage >= 1000
            ? '${(tonnage / 1000).toStringAsFixed(1)}т'
            : '${tonnage.round()}кг';

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatPill(value: '$weekCount', label: 'трен/нед'),
            const SizedBox(width: 6),
            _StatPill(value: tonnageLabel, label: 'тоннаж'),
          ],
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chromeOn =
        Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chromeOn.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: chromeOn.withValues(alpha: 0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                  height: 1,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 9,
                  height: 1,
                ),
          ),
        ],
      ),
    );
  }
}
