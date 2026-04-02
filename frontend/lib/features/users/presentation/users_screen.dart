import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../../core/widgets/user_avatar.dart';
import 'user_public_profile_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<_UserSummary>> _future;
  final TextEditingController _searchController = TextEditingController();
  _UserSort _sort = _UserSort.lastActivity;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_UserSummary>> _load() async {
    final items = await BackendApi.getUsers();
    return items.map(_UserSummary.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  List<_UserSummary> _applyFilters(List<_UserSummary> users) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = users.where((user) {
      return query.isEmpty || user.displayName.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      switch (_sort) {
        case _UserSort.level:
          return b.level.compareTo(a.level);
        case _UserSort.xp:
          return b.totalXp.compareTo(a.totalXp);
        case _UserSort.streak:
          return b.currentStreak.compareTo(a.currentStreak);
        case _UserSort.lastActivity:
          final aDate = a.lastActivityAt ?? DateTime(1970);
          final bDate = b.lastActivityAt ?? DateTime(1970);
          return bDate.compareTo(aDate);
      }
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppBackdrop(
      child: FutureBuilder<List<_UserSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  BackendApi.describeError(
                    snapshot.error!,
                    fallback: 'Не удалось загрузить список пользователей.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final users = _applyFilters(snapshot.data ?? const []);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                DashboardSummaryCard(
                  subtitle: 'Рейтинг и активность',
                  title: 'Пользователи',
                  trailing: StatusBadge(
                    label: '${users.length}',
                    color: scheme.secondary,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 12),
                AppSearchField(
                  controller: _searchController,
                  hintText: 'Поиск пользователя',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_UserSort>(
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: 'Сортировка'),
                  items: const [
                    DropdownMenuItem(
                      value: _UserSort.lastActivity,
                      child: Text('По последней активности'),
                    ),
                    DropdownMenuItem(
                      value: _UserSort.level,
                      child: Text('По уровню'),
                    ),
                    DropdownMenuItem(
                      value: _UserSort.xp,
                      child: Text('По XP'),
                    ),
                    DropdownMenuItem(
                      value: _UserSort.streak,
                      child: Text('По стрику'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _sort = value);
                  },
                ),
                const SizedBox(height: 12),
                ...users.map(
                  (user) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DashboardCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserPublicProfileScreen(
                            userId: user.id,
                            displayName: user.displayName,
                            avatarUrl: user.avatarUrl,
                          ),
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        leading: UserAvatar(
                          avatarUrl: user.avatarUrl,
                          fallbackText: _initial(user.displayName),
                        ),
                        title: Text(
                          user.displayName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _UserMetaPill(
                                label: 'Ур.',
                                value: '${user.level}',
                              ),
                              _UserMetaPill(
                                label: 'XP',
                                value: '${user.totalXp}',
                              ),
                              _UserMetaPill(
                                label: 'Стрик',
                                value: '🔥 ${user.currentStreak}',
                              ),
                              if (user.lastActivityAt != null)
                                _UserMetaPill(
                                  label: 'Активность',
                                  value:
                                      formatShortDateTime(user.lastActivityAt!),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserMetaPill extends StatelessWidget {
  const _UserMetaPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

String _initial(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'A' : trimmed[0].toUpperCase();
}

enum _UserSort {
  lastActivity,
  level,
  xp,
  streak,
}

class _UserSummary {
  const _UserSummary({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.level,
    required this.totalXp,
    required this.currentStreak,
    required this.lastActivityAt,
  });

  final int id;
  final String displayName;
  final String? avatarUrl;
  final int level;
  final int totalXp;
  final int currentStreak;
  final DateTime? lastActivityAt;

  factory _UserSummary.fromJson(Map<String, dynamic> json) {
    return _UserSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      displayName: (json['displayName'] ?? 'Атлет').toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      level: (json['level'] as num?)?.toInt() ?? 1,
      totalXp: (json['totalXp'] as num?)?.toInt() ?? 0,
      currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
      lastActivityAt: json['lastActivityAt'] == null
          ? null
          : DateTime.parse(json['lastActivityAt'].toString()).toLocal(),
    );
  }
}
