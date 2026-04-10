import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';

class AiCoachScreen extends StatefulWidget {
  const AiCoachScreen({super.key});

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  static const _maxMessagesForRequest = 12;
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingHistory = true;
  bool _isSending = false;
  bool _showJumpUp = false;
  bool _showJumpDown = false;

  static const _starterPrompts = [
    'Разбери мои последние тренировки',
    'Какие мышцы я давно не тренировал?',
    'Спланируй тренировку на сегодня',
    'Как распределена нагрузка по мышцам?',
  ];

  static const _introMessage = _ChatMessage(
    role: 'assistant',
    text:
        'Я уже вижу твою статистику по тренировкам. Можешь попросить меня разобрать прогресс, нагрузку или восстановление.',
    includeInRequest: false,
  );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScrollChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    await _syncHistory(showLoading: true);
  }

  Future<void> _syncHistory({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() => _isLoadingHistory = true);
    }
    try {
      final history = await BackendApi.getCoachHistory();
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(
            history.map(
              (item) => _ChatMessage(
                id: item['id'] as int?,
                role: (item['role'] as String?) ?? 'assistant',
                text: (item['content'] as String?) ?? '',
              ),
            ),
          );
        if (_messages.isEmpty) {
          _messages.add(_introMessage);
        }
      });
    } catch (_) {
      if (!mounted) return;
      if (_messages.isEmpty) {
        setState(() => _messages.add(_introMessage));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _isSending || _isLoadingHistory) {
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _isSending = true;
      if (preset == null) {
        _controller.clear();
      }
    });
    _scrollToBottom();

    try {
      final requestMessages = _messages
          .where((message) => !message.isError && message.includeInRequest)
          .toList();
      final response = await BackendApi.chatWithCoach(
        messages: requestMessages
            .skip(
              requestMessages.length > _maxMessagesForRequest
                  ? requestMessages.length - _maxMessagesForRequest
                  : 0,
            )
            .map(
              (message) => {
                'role': message.role,
                'content': message.text,
              },
            )
            .toList(),
      );
      final reply = (response['reply'] as String?)?.trim();
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            text: (reply == null || reply.isEmpty)
                ? 'Не удалось получить содержательный ответ. Попробуй уточнить запрос.'
                : reply,
          ),
        );
      });
      await _syncHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            text: BackendApi.describeError(
              error,
              fallback: 'AI - коуч сейчас недоступен. Попробуй чуть позже.',
            ),
            isError: true,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  bool get _hasHistory => _messages.any((m) => m.id != null);

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить историю?'),
        content: const Text('Все сообщения будут удалены безвозвратно.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await BackendApi.clearCoachHistory();
      if (!mounted) return;
      setState(() {
        _messages.clear();
        _messages.add(_introMessage);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История очищена.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            BackendApi.describeError(
              error,
              fallback: 'Не удалось очистить историю.',
            ),
          ),
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 160,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _handleScrollChanged() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final showUp = position.pixels > 220;
    final showDown = position.maxScrollExtent - position.pixels > 220;
    if (showUp != _showJumpUp || showDown != _showJumpDown) {
      setState(() {
        _showJumpUp = showUp;
        _showJumpDown = showDown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI - коуч'),
        actions: [
          if (_hasHistory)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Очистить историю',
              onPressed: _isSending ? null : _clearHistory,
            ),
        ],
      ),
      body: AppBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      children: [
                        DashboardSummaryCard(
                          title: 'Тренер, который отвечает по твоим данным',
                          subtitle: 'Контекст берется из последних тренировок',
                          bottom: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _starterPrompts
                                .map(
                                  (prompt) => ActionChip(
                                    label: Text(prompt),
                                    onPressed: _isSending || _isLoadingHistory
                                        ? null
                                        : () => _sendMessage(prompt),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const DashboardSectionLabel('Чат'),
                        const SizedBox(height: 10),
                        if (_isLoadingHistory)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: DashboardCard(
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.2),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child:
                                        Text('Загружаю последние сообщения...'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ..._messages.asMap().entries.map(
                          (entry) {
                            final idx = entry.key;
                            final message = entry.value;

                            // Find the paired message to delete together
                            _ChatMessage? partner;
                            if (message.role == 'user' &&
                                idx + 1 < _messages.length) {
                              final next = _messages[idx + 1];
                              if (next.role == 'assistant' && next.id != null) {
                                partner = next;
                              }
                            } else if (message.role == 'assistant' && idx > 0) {
                              final prev = _messages[idx - 1];
                              if (prev.role == 'user' && prev.id != null) {
                                partner = prev;
                              }
                            }

                            return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Dismissible(
                              key: ValueKey(
                                message.id ??
                                    '${message.role}:${message.text.hashCode}',
                              ),
                              direction: message.id == null
                                  ? DismissDirection.none
                                  : DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                final messageId = message.id;
                                if (messageId == null) return false;
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(partner != null
                                        ? 'Удалить сообщение и ответ?'
                                        : 'Удалить сообщение?'),
                                    content: Text(partner != null
                                        ? 'Вопрос и ответ коуча будут удалены безвозвратно.'
                                        : 'Сообщение будет удалено безвозвратно.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text('Отмена'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(ctx).colorScheme.error,
                                        ),
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        child: const Text('Удалить'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return false;
                                try {
                                  await Future.wait([
                                    BackendApi.deleteCoachMessage(messageId),
                                    if (partner?.id != null)
                                      BackendApi.deleteCoachMessage(
                                          partner!.id!),
                                  ]);
                                  return true;
                                } catch (error) {
                                  if (!mounted) return false;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        BackendApi.describeError(
                                          error,
                                          fallback:
                                              'Не удалось удалить сообщение.',
                                        ),
                                      ),
                                    ),
                                  );
                                  return false;
                                }
                              },
                              onDismissed: (_) {
                                setState(() {
                                  _messages.removeWhere((item) =>
                                      item.id == message.id ||
                                      item.id == partner?.id);
                                  if (_messages.isEmpty) {
                                    _messages.add(_introMessage);
                                  }
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Сообщение удалено.')),
                                );
                              },
                              background: Builder(
                                builder: (ctx) {
                                  final s = Theme.of(ctx).colorScheme;
                                  return Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    decoration: BoxDecoration(
                                      color: s.errorContainer,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Удалить',
                                          style: TextStyle(
                                            color: s.onErrorContainer,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.delete_outline,
                                            color: s.onErrorContainer),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              child: _ChatBubble(message: message),
                            ),
                          );
                          },
                        ),
                        if (_isSending)
                          DashboardCard(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: scheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'AI - коуч анализирует статистику и готовит ответ...',
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_showJumpUp)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ScrollActionButton(
                                icon: Icons.keyboard_double_arrow_up_rounded,
                                tooltip: 'Наверх',
                                onTap: _scrollToTop,
                              ),
                            ),
                          if (_showJumpDown)
                            _ScrollActionButton(
                              icon: Icons.keyboard_double_arrow_down_rounded,
                              tooltip: 'Вниз',
                              onTap: _scrollToBottom,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _CoachComposer(
                controller: _controller,
                isSending: _isSending || _isLoadingHistory,
                onSend: () => _sendMessage(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachComposer extends StatelessWidget {
  const _CoachComposer({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: DashboardCard(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: isSending ? null : onSend,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  minimumSize: const Size(52, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    final accent = message.isError
        ? scheme.error
        : (isUser ? scheme.primary : scheme.secondary);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DashboardCard(
          leftAccentColor: accent,
          color: isUser
              ? scheme.primaryContainer.withValues(alpha: 0.62)
              : scheme.surfaceContainerLow.withValues(alpha: 0.96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUser ? 'Ты' : 'AI - коуч',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
              ),
              const SizedBox(height: 8),
              if (isUser || message.isError)
                SelectableText(
                  message.text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.5),
                )
              else
                MarkdownBody(
                  data: _normalizeMarkdown(message.text),
                  selectable: true,
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.5),
                    pPadding: const EdgeInsets.only(bottom: 10),
                    listBullet: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.5),
                    listBulletPadding: const EdgeInsets.only(right: 8),
                    strong: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollActionButton extends StatelessWidget {
  const _ScrollActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        elevation: 3,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    this.id,
    required this.role,
    required this.text,
    this.isError = false,
    this.includeInRequest = true,
  });

  final int? id;
  final String role;
  final String text;
  final bool isError;
  final bool includeInRequest;
}

String _normalizeMarkdown(String value) {
  final normalized = value.replaceAll('\r\n', '\n').trim();
  return normalized.replaceAllMapped(
    RegExp(r'(?<!\n)\n(?!\n)'),
    (_) => '\n\n',
  );
}
