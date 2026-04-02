import 'package:flutter/material.dart';

import '../../body/presentation/body_screen.dart';
import '../../heatmap/presentation/weekly_muscle_heatmap_tab.dart';
import '../../templates/presentation/templates_screen.dart';

class PersonalScreen extends StatelessWidget {
  const PersonalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                indicator: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                labelColor: scheme.onSecondaryContainer,
                unselectedLabelColor: scheme.onSurfaceVariant,
                labelStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                unselectedLabelStyle:
                    Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                tabs: const [
                  Tab(
                    height: 46,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Templates'),
                    ),
                  ),
                  Tab(
                    height: 46,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Text('Body'),
                    ),
                  ),
                  Tab(
                    height: 46,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Text('Heatmap'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                TemplatesScreen(),
                BodyScreen(),
                WeeklyMuscleHeatmapTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
