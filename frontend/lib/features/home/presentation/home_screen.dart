import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/backend_api.dart';
import '../../progression/application/progression_controller.dart';
import '../../progression/presentation/progression_compact_badge.dart';
import '../../social/presentation/social_hub_screen.dart';
import '../../calendar/presentation/calendar_screen.dart';
import '../../more/presentation/more_screen.dart';
import '../../progress/presentation/progress_screen.dart';
import '../../today/presentation/today_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(ProgressionController.instance.refresh);
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayScreen(),
      CalendarScreen(),
      ProgressScreen(),
      MoreScreen(
        onLogout: _logout,
        onOpenSocialHub: _openSocialHub,
      ),
    ];

    const tabs = [
      (Icons.today_rounded, 'Сегодня'),
      (Icons.calendar_month, 'Календарь'),
      (Icons.insights, 'Прогресс'),
      (Icons.menu_rounded, 'Инструменты'),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: Colors.transparent,
        title: Align(
          alignment: Alignment.centerLeft,
          child: ProgressionCompactBadge(
            onTap: () => _openSocialHub(),
          ),
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
