import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';

class CoachOwnerHistoryScreen extends StatefulWidget {
  const CoachOwnerHistoryScreen({
    super.key,
    this.showAppBar = true,
  });

  final bool showAppBar;

  @override
  State<CoachOwnerHistoryScreen> createState() =>
      _CoachOwnerHistoryScreenState();
}

enum _RoleFilter {
  all('Все'),
  user('Пользователи'),
  assistant('AI-коуч');

  const _RoleFilter(this.label);
  final String label;
}

class _CoachOwnerHistoryScreenState extends State<CoachOwnerHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _messages = const [];
  final Set<String> _expandedUsers = <String>{};
  String _query = '';
  bool _isLoading = true;
  _RoleFilter _roleFilter = _RoleFilter.all;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final data = await BackendApi.getOwnerCoachHistory();
      if (!mounted) return;
      final groups = _buildUserGroups(data);
      setState(() {
        _messages = data;
        _expandedUsers.removeWhere(
          (key) => !groups.any((group) => group.userKey == key),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              error,
              fallback: 'Не удалось загрузить owner-only историю AI-коуча.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredMessages {
    final query = _query.trim().toLowerCase();
    return _messages.where((item) {
      final role = (item['role'] ?? '').toString();
      if (_roleFilter == _RoleFilter.user && role != 'user') {
        return false;
      }
      if (_roleFilter == _RoleFilter.assistant && role != 'assistant') {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }

      final email = (item['user_email'] ?? '').toString().toLowerCase();
      final name = (item['user_display_name'] ?? '').toString().toLowerCase();
      final content = (item['content'] ?? '').toString().toLowerCase();
      return email.contains(query) ||
          name.contains(query) ||
          content.contains(query);
    }).toList();
  }

  List<_UserGroup> get _groupedMessages => _buildUserGroups(_filteredMessages);

  void _toggleUserGroup(String userKey, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedUsers.add(userKey);
      } else {
        _expandedUsers.remove(userKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedMessages;
    final totalUsers = _buildUserGroups(_messages).length;
    final totalUserMessages =
        _messages.where((item) => item['role'] == 'user').length;
    final totalAssistantMessages =
        _messages.where((item) => item['role'] == 'assistant').length;

    final body = AppBackdrop(
      child: SafeArea(
        top: widget.showAppBar,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadHistory,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: _CompactToolbar(
                          searchController: _searchController,
                          query: _query,
                          roleFilter: _roleFilter,
                          totalUsers: totalUsers,
                          totalUserMessages: totalUserMessages,
                          totalAssistantMessages: totalAssistantMessages,
                          onQueryChanged: (value) =>
                              setState(() => _query = value),
                          onRoleChanged: (value) {
                            if (value == null) return;
                            setState(() => _roleFilter = value);
                          },
                        ),
                      ),
                    ),
                    if (groups.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child:
                              Text('Сообщений по текущему фильтру пока нет.'),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverList.separated(
                          itemCount: groups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            final isExpanded =
                                _expandedUsers.contains(group.userKey);

                            return DashboardCard(
                              padding: EdgeInsets.zero,
                              child: _UserHistoryGroupCard(
                                group: group,
                                isExpanded: isExpanded,
                                onToggle: () => _toggleUserGroup(
                                  group.userKey,
                                  !isExpanded,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('История AI-коуча'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadHistory,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: body,
    );
  }
}

class _CompactToolbar extends StatelessWidget {
  const _CompactToolbar({
    required this.searchController,
    required this.query,
    required this.roleFilter,
    required this.totalUsers,
    required this.totalUserMessages,
    required this.totalAssistantMessages,
    required this.onQueryChanged,
    required this.onRoleChanged,
  });

  final TextEditingController searchController;
  final String query;
  final _RoleFilter roleFilter;
  final int totalUsers;
  final int totalUserMessages;
  final int totalAssistantMessages;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_RoleFilter?> onRoleChanged;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatChip(text: 'Юзеры: $totalUsers'),
              _StatChip(text: 'Вопросы: $totalUserMessages'),
              _StatChip(text: 'Ответы: $totalAssistantMessages'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    hintText: 'Поиск',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchController.clear();
                              onQueryChanged('');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButtonHideUnderline(
                child: DropdownButton<_RoleFilter>(
                  value: roleFilter,
                  onChanged: onRoleChanged,
                  items: _RoleFilter.values
                      .map(
                        (filter) => DropdownMenuItem<_RoleFilter>(
                          value: filter,
                          child: Text(filter.label),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserHistoryGroupCard extends StatelessWidget {
  const _UserHistoryGroupCard({
    required this.group,
    required this.isExpanded,
    required this.onToggle,
  });

  final _UserGroup group;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.displayName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(group.email),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _MiniChip(
                                text: 'Сообщений: ${group.messages.length}',
                              ),
                              const SizedBox(width: 8),
                              _MiniChip(
                                text: 'Вопросов: ${group.userMessageCount}',
                              ),
                              const SizedBox(width: 8),
                              _MiniChip(
                                text: 'Ответов: ${group.assistantMessageCount}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: scheme.primary,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      children: group.messages
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: _OwnerHistoryMessageCard(item: item),
                            ),
                          )
                          .toList(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _OwnerHistoryMessageCard extends StatelessWidget {
  const _OwnerHistoryMessageCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = (item['role'] as String?) == 'user';
    final accent = isUser ? scheme.primary : scheme.secondary;
    final createdAt = _formatTimestamp((item['created_at'] ?? '').toString());

    return DashboardCard(
      leftAccentColor: accent,
      color: isUser
          ? scheme.primaryContainer.withValues(alpha: 0.48)
          : scheme.surfaceContainerLow.withValues(alpha: 0.96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${isUser ? 'Пользователь' : 'AI-коуч'} • $createdAt',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          if (isUser)
            SelectableText(
              (item['content'] ?? '').toString(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.45,
                  ),
            )
          else
            MarkdownBody(
              data: _normalizeOwnerMarkdown(
                (item['content'] ?? '').toString(),
              ),
              selectable: true,
              shrinkWrap: true,
              fitContent: true,
              styleSheet:
                  MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.45,
                    ),
                pPadding: const EdgeInsets.only(bottom: 8),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _UserGroup {
  const _UserGroup({
    required this.userKey,
    required this.email,
    required this.displayName,
    required this.messages,
  });

  final String userKey;
  final String email;
  final String displayName;
  final List<Map<String, dynamic>> messages;

  int get userMessageCount =>
      messages.where((item) => item['role'] == 'user').length;

  int get assistantMessageCount =>
      messages.where((item) => item['role'] == 'assistant').length;
}

List<_UserGroup> _buildUserGroups(List<Map<String, dynamic>> messages) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  final emails = <String, String>{};
  final names = <String, String>{};

  for (final item in messages) {
    final email = (item['user_email'] ?? '').toString();
    final name = (item['user_display_name'] ?? 'Атлет').toString();
    final userId = (item['user_id'] ?? '').toString();
    final key = '$userId|$email';
    grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
    emails[key] = email;
    names[key] = name;
  }

  final groups = grouped.entries
      .map(
        (entry) => _UserGroup(
          userKey: entry.key,
          email: emails[entry.key] ?? '',
          displayName: names[entry.key] ?? 'Атлет',
          messages: entry.value,
        ),
      )
      .toList();

  groups.sort((a, b) {
    final aDate = a.messages.isNotEmpty
        ? (a.messages.first['created_at'] ?? '').toString()
        : '';
    final bDate = b.messages.isNotEmpty
        ? (b.messages.first['created_at'] ?? '').toString()
        : '';
    return bDate.compareTo(aDate);
  });

  return groups;
}

String _normalizeOwnerMarkdown(String value) {
  final normalized = value.replaceAll('\r\n', '\n').trim();
  return normalized.replaceAllMapped(
    RegExp(r'(?<!\n)\n(?!\n)'),
    (_) => '\n\n',
  );
}

String _formatTimestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }
  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month.${local.year} $hour:$minute';
}
