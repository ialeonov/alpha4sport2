import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../calendar/presentation/calendar_screen.dart';
import '../../more/presentation/profile_screen.dart';
import '../../progress/presentation/progress_screen.dart';
import '../../progression/application/progression_controller.dart';
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
  final _progressKey = GlobalKey<ProgressScreenState>();

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
      ProgressScreen(key: _progressKey),
      ProfileScreen(onLogout: _logout),
    ];

    const tabs = [
      (Icons.today_rounded, 'Сегодня'),
      (Icons.calendar_month, 'Журнал'),
      (Icons.insights_rounded, 'Прогресс'),
      (Icons.person_rounded, 'Профиль'),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: OfflineBanner(
          child: IndexedStack(
            index: _index,
            children: pages,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          if (index == 1 && _index != 1) {
            _calendarKey.currentState?.refresh();
          }
          if (index == 2 && _index != 2) {
            _progressKey.currentState?.refresh();
          }
          if (index == 3 && _index != 3) {
            ProgressionController.instance.refresh();
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
