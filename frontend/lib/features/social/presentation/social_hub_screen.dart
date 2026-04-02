import 'package:flutter/material.dart';

import '../../events/presentation/account_events_screen.dart';
import '../../progression/presentation/progression_profile_screen.dart';
import '../../users/presentation/users_screen.dart';

class SocialHubScreen extends StatelessWidget {
  const SocialHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Сообщество'),
          backgroundColor: Colors.transparent,
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [
              Tab(text: 'Профиль'),
              Tab(text: 'Пользователи'),
              Tab(text: 'События'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ProgressionProfileContent(),
            UsersScreen(),
            AccountEventsScreen(),
          ],
        ),
      ),
    );
  }
}
