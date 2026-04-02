import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../../core/widgets/user_avatar.dart';

class AccountEventsScreen extends StatefulWidget {
  const AccountEventsScreen({super.key});

  @override
  State<AccountEventsScreen> createState() => _AccountEventsScreenState();
}

class _AccountEventsScreenState extends State<AccountEventsScreen> {
  late Future<List<_AccountEventItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_AccountEventItem>> _load() async {
    final items = await BackendApi.getAccountEvents(limit: 20);
    return items.map(_AccountEventItem.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _toggleLike(_AccountEventItem event) async {
    HapticFeedback.selectionClick();
    try {
      final result = await BackendApi.toggleEventLike(event.id);
      final liked = result['liked'] as bool? ?? false;
      final count = (result['likesCount'] as num?)?.toInt() ?? 0;
      setState(() {
        event.likesCount = count;
        event.isLikedByMe = liked;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppBackdrop(
      child: FutureBuilder<List<_AccountEventItem>>(
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
                    fallback: 'Не удалось загрузить ленту событий.',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final events = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                const DashboardSummaryCard(
                  subtitle: 'Лента сообщества',
                  title: 'События',
                ),
                const SizedBox(height: 12),
                ...events.map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DashboardCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserAvatar(
                            avatarUrl: event.avatarUrl,
                            fallbackText: _initial(event.displayName),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.displayName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  event.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(height: 1.35),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    StatusBadge(
                                      label: formatShortDateTime(event.createdAt),
                                      color: scheme.onSurfaceVariant,
                                      compact: true,
                                    ),
                                    const Spacer(),
                                    _LikeButton(
                                      event: event,
                                      onTap: () => _toggleLike(event),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
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

class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.event, required this.onTap});

  final _AccountEventItem event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liked = event.isLikedByMe;
    final color = liked ? scheme.error : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                key: ValueKey(liked),
                size: 18,
                color: color,
              ),
            ),
            if (event.likesCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                '${event.likesCount}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
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

class _AccountEventItem {
  _AccountEventItem({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.description,
    required this.createdAt,
    required this.likesCount,
    required this.isLikedByMe,
  });

  final int id;
  final String displayName;
  final String? avatarUrl;
  final String description;
  final DateTime createdAt;
  int likesCount;
  bool isLikedByMe;

  factory _AccountEventItem.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map).cast<String, dynamic>();
    return _AccountEventItem(
      id: (json['id'] as num).toInt(),
      displayName: (user['displayName'] ?? 'Атлет').toString(),
      avatarUrl: user['avatarUrl']?.toString(),
      description: (json['description'] ?? '').toString(),
      createdAt: DateTime.parse((json['createdAt'] ?? '').toString()).toLocal(),
      likesCount: (json['likesCount'] as num?)?.toInt() ?? 0,
      isLikedByMe: json['isLikedByMe'] == true,
    );
  }
}
