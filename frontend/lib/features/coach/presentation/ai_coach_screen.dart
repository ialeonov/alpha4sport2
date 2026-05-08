import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/network/backend_api_exception.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../wellness/data/wellness_repository.dart';

class AiCoachScreen extends StatefulWidget {
  const AiCoachScreen({super.key, this.initialMessage});

  final String? initialMessage;

  @override
  State<AiCoachScreen> createState() => _AiCoachScreenState();
}

class _AiCoachScreenState extends State<AiCoachScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI-коуч')),
      body: AiCoachChat(initialMessage: widget.initialMessage),
    );
  }
}

class AiCoachChat extends StatefulWidget {
  const AiCoachChat({
    super.key,
    this.initialMessage,
    this.wrapInBackdrop = true,
  });

  final String? initialMessage;
  final bool wrapInBackdrop;

  @override
  State<AiCoachChat> createState() => _AiCoachChatState();
}

class _AiCoachChatState extends State<AiCoachChat>
    with AutomaticKeepAliveClientMixin {
  static const _maxMessagesForRequest = 12;
  final List<_ChatMessage> _messages = [_introMessage];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _showPrompts = false;
  bool _showJumpUp = false;
  bool _showJumpDown = false;
  int _sendingMessageIndex = 0;
  Timer? _sendingMessageTimer;
  String _streamingText = '';
  StreamSubscription<String>? _streamSubscription;

  static const _sendingMessages = [
    'Анализирую тренировки...',
    'Смотрю историю нагрузок...',
    'Готовлю рекомендации...',
    'Обрабатываю данные...',
    'Почти готово...',
  ];

  static const _starterPrompts = [
    'Разбери последнюю тренировку',
    'Как мой прогресс?',
    'Составь план тренировки на сегодня',
    'Какие мышцы давно не работали?',
    'Как пробить застой?',
    'Добавить вес или повторения?',
  ];

  static const _introMessage = _ChatMessage(
    role: 'assistant',
    text:
        'Привет! Я твой AI-коуч. Спроси меня о тренировках или нажми 💡 для подсказок.',
    includeInRequest: false,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollChanged);
    _loadHistory();
    final initialMessage = widget.initialMessage?.trim();
    if (initialMessage != null && initialMessage.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sendMessage(initialMessage);
        }
      });
    }
  }

  @override
  void dispose() {
    _sendingMessageTimer?.cancel();
    _streamSubscription?.cancel();
    _scrollController.removeListener(_handleScrollChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    await _syncHistory();
  }

  List<Map<String, dynamic>> _collectRecentWellnessEntries() {
    final result = <Map<String, dynamic>>[];
    final today = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: i));
      final entry = WellnessRepository.loadForDate(date);
      if (entry != null) {
        final map = <String, dynamic>{
          'date':
              DateUtils.dateOnly(entry.date).toIso8601String().substring(0, 10),
          'sleep': entry.sleep,
          'energy': entry.energy,
          'stress': entry.stress,
          'mood': entry.mood,
        };
        if (entry.comment != null) map['comment'] = entry.comment;
        result.add(map);
      }
    }
    return result;
  }

  Future<void> _syncHistory({
    bool force = false,
  }) async {
    try {
      final history = await BackendApi.getCoachHistory();
      if (!mounted) return;
      if (!force &&
          _messages
              .any((message) => message.id == null && message.role == 'user')) {
        return;
      }
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
        _scrollToBottom();
      }
    }
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _isSending) {
      return;
    }

    final clarification = _exerciseClarificationFor(text);
    if (clarification != null) {
      setState(() {
        if (_messages.length == 1 &&
            !_messages.first.includeInRequest &&
            _messages.first.id == null) {
          _messages.clear();
        }
        _messages.add(_ChatMessage(role: 'user', text: text));
        _messages.add(_ChatMessage(role: 'assistant', text: clarification));
        _showPrompts = false;
        if (preset == null) {
          _controller.clear();
        }
      });
      _scrollToBottom();
      return;
    }

    setState(() {
      if (_messages.length == 1 &&
          !_messages.first.includeInRequest &&
          _messages.first.id == null) {
        _messages.clear();
      }
      _messages.add(_ChatMessage(role: 'user', text: text));
      _isSending = true;
      _streamingText = '';
      _showPrompts = false;
      _sendingMessageIndex = 0;
      if (preset == null) {
        _controller.clear();
      }
    });
    _sendingMessageTimer?.cancel();
    _sendingMessageTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (mounted) {
          setState(() {
            _sendingMessageIndex =
                (_sendingMessageIndex + 1) % _sendingMessages.length;
          });
        }
      },
    );
    _scrollToBottom();

    final requestMessages = _messages
        .where((message) => !message.isError && message.includeInRequest)
        .toList();
    final apiMessages = requestMessages
        .skip(
          requestMessages.length > _maxMessagesForRequest
              ? requestMessages.length - _maxMessagesForRequest
              : 0,
        )
        .map((message) => {'role': message.role, 'content': message.text})
        .toList();
    final wellness = _collectRecentWellnessEntries();

    String accumulated = '';
    bool hadError = false;

    final stream = BackendApi.chatWithCoachStream(
      messages: apiMessages,
      wellnessEntries: wellness,
    );

    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (chunk) {
        if (!mounted) return;
        accumulated += chunk;
        setState(() => _streamingText = accumulated);
        _scrollToBottom();
      },
      onError: (error) {
        if (!mounted) return;
        hadError = true;
        final errorText = error is BackendApiException
            ? error.message
            : 'Временные проблемы со связью. Попробуй чуть позже.';
        setState(() {
          _messages.add(
            _ChatMessage(
              role: 'assistant',
              text: errorText,
              isError: true,
            ),
          );
          _isSending = false;
          _streamingText = '';
        });
        _sendingMessageTimer?.cancel();
        _sendingMessageTimer = null;
        _scrollToBottom();
      },
      onDone: () {
        if (!mounted || hadError) return;
        final reply = accumulated.trim();
        setState(() {
          _messages.add(
            _ChatMessage(
              role: 'assistant',
              text: reply.isEmpty
                  ? 'Не удалось получить содержательный ответ. Попробуй уточнить запрос.'
                  : reply,
            ),
          );
          _isSending = false;
          _streamingText = '';
        });
        _sendingMessageTimer?.cancel();
        _sendingMessageTimer = null;
        _scrollToBottom();
        _syncHistory(force: true);
      },
    );
  }

  String? _exerciseClarificationFor(String text) {
    return switch (text) {
      'Как пробить застой?' =>
        'Про какое упражнение говорим? Напиши название, и я разберу, что лучше поменять.',
      'Добавить вес или повторения?' =>
        'Для какого упражнения решить: добавить вес или повторения?',
      _ => null,
    };
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
        _showPrompts = false;
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

  void _togglePrompts() {
    FocusScope.of(context).unfocus();
    setState(() => _showPrompts = !_showPrompts);
  }

  void _hidePrompts() {
    if (_showPrompts) {
      setState(() => _showPrompts = false);
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
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final content = SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hidePrompts,
              child: Stack(
                children: [
                  ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    children: [
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
                            padding: const EdgeInsets.only(bottom: 8),
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
                                  if (!context.mounted) return false;
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
                              child: _ChatBubble(
                                message: message,
                                onEdit: message.role == 'user'
                                    ? () {
                                        _controller.text = message.text;
                                        _controller.selection =
                                            TextSelection.collapsed(
                                          offset: message.text.length,
                                        );
                                      }
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                      if (_isSending && _streamingText.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: DashboardCard(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.55),
                            child: Row(
                              children: [
                                const _TypingIndicator(),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: Text(
                                      _sendingMessages[_sendingMessageIndex],
                                      key: ValueKey(_sendingMessageIndex),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (_isSending && _streamingText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ChatBubble(
                            message: _ChatMessage(
                              role: 'assistant',
                              text: _streamingText,
                            ),
                            isStreaming: true,
                          ),
                        ),
                    ],
                  ),
                  if (_hasHistory)
                    Positioned(
                      top: 6,
                      right: 12,
                      child: IconButton(
                        icon: const Icon(Icons.delete_sweep_rounded),
                        tooltip: 'Очистить историю',
                        onPressed: _isSending ? null : _clearHistory,
                      ),
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
          ),
          _CoachComposer(
            controller: _controller,
            prompts: _starterPrompts,
            showPrompts: _showPrompts,
            isSending: _isSending,
            onPromptToggle: _togglePrompts,
            onPromptSelected: _sendMessage,
            onSend: () => _sendMessage(),
          ),
        ],
      ),
    );
    if (!widget.wrapInBackdrop) {
      return content;
    }
    return AppBackdrop(child: content);
  }
}

class _CoachComposer extends StatefulWidget {
  const _CoachComposer({
    required this.controller,
    required this.prompts,
    required this.showPrompts,
    required this.isSending,
    required this.onPromptToggle,
    required this.onPromptSelected,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<String> prompts;
  final bool showPrompts;
  final bool isSending;
  final VoidCallback onPromptToggle;
  final ValueChanged<String> onPromptSelected;
  final VoidCallback onSend;

  @override
  State<_CoachComposer> createState() => _CoachComposerState();
}

class _CoachComposerState extends State<_CoachComposer>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: widget.showPrompts
                  ? _PromptPanel(
                      prompts: widget.prompts,
                      onSelected:
                          widget.isSending ? null : widget.onPromptSelected,
                    )
                  : const SizedBox(width: double.infinity),
            ),
            DashboardCard(
              borderRadius: 24,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Подсказки',
                    onPressed: widget.isSending ? null : widget.onPromptToggle,
                    icon: Icon(
                      widget.showPrompts
                          ? Icons.lightbulb_rounded
                          : Icons.lightbulb_outline_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => widget.onSend(),
                      decoration: const InputDecoration(
                        hintText: 'Спроси коуча...',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: widget.isSending ? null : widget.onSend,
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
          ],
        ),
      ),
    );
  }
}

class _PromptPanel extends StatelessWidget {
  const _PromptPanel({
    required this.prompts,
    required this.onSelected,
  });

  final List<String> prompts;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DashboardCard(
        borderRadius: 22,
        padding: const EdgeInsets.all(10),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.70),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              children: prompts
                  .map(
                    (prompt) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: onSelected == null
                            ? null
                            : () => onSelected!(prompt),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 42),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color:
                                  scheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            prompt,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.18,
                                ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    this.onEdit,
    this.isStreaming = false,
  });

  final _ChatMessage message;
  final VoidCallback? onEdit;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == 'user';
    final accent = message.isError
        ? scheme.error
        : (isUser ? scheme.primary : scheme.secondary);
    final bodyStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45);

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
              Row(
                children: [
                  Text(
                    isUser ? 'Ты' : 'AI-коуч',
                    style:
                        Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                  ),
                  const Spacer(),
                  if (!isStreaming) ...[
                    _BubbleAction(
                      icon: Icons.copy_rounded,
                      tooltip: 'Копировать',
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: message.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Скопировано'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                    if (onEdit != null) ...[
                      const SizedBox(width: 2),
                      _BubbleAction(
                        icon: Icons.edit_rounded,
                        tooltip: 'Редактировать',
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                        onTap: onEdit!,
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 4),
              if (isUser || message.isError)
                SelectableText(
                  message.text,
                  style: bodyStyle,
                )
              else
                MarkdownBody(
                  data: _normalizeMarkdown(message.text),
                  selectable: !isStreaming,
                  styleSheet: MarkdownStyleSheet.fromTheme(
                          Theme.of(context))
                      .copyWith(
                    p: bodyStyle,
                    pPadding: const EdgeInsets.only(bottom: 8),
                    listBullet: bodyStyle,
                    listBulletPadding: const EdgeInsets.only(right: 6),
                    strong: bodyStyle?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleAction extends StatelessWidget {
  const _BubbleAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 15, color: color),
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 32,
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final t = (_controller.value - i / 3) % 1.0;
              final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.2, 1.0);
              return Transform.translate(
                offset: Offset(0, -3 * (t < 0.5 ? t * 2 : (1 - t) * 2)),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          );
        },
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
