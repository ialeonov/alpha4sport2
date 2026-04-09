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
  final List<_ChatMessage> _messages = const [
    _ChatMessage(
      role: 'assistant',
      text:
          'Я уже вижу твою статистику по тренировкам. Можешь попросить меня разобрать прогресс, нагрузку или восстановление.',
      includeInRequest: false,
    ),
  ].toList();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingHistory = true;
  bool _isSending = false;

  static const _starterPrompts = [
    'Разбери мои последние тренировки',
    'Спланируй тренировку на сегодня',
    'Что делать на следующей неделе?',
    'Где у меня сейчас идет прогресс?',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await BackendApi.getCoachHistory();
      if (!mounted) return;
      if (history.isNotEmpty) {
        setState(() {
          _messages
            ..clear()
            ..addAll(
              history.map(
                (item) => _ChatMessage(
                  role: (item['role'] as String?) ?? 'assistant',
                  text: (item['content'] as String?) ?? '',
                ),
              ),
            );
        });
      }
    } catch (_) {
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
      final response = await BackendApi.chatWithCoach(
        messages: _messages
            .where((message) => !message.isError && message.includeInRequest)
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            role: 'assistant',
            text: BackendApi.describeError(
              error,
              fallback: 'AI-коуч сейчас недоступен. Попробуй чуть позже.',
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI-коуч')),
      body: AppBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
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
                                onPressed: _isSending
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.2),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Загружаю последние сообщения...'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ..._messages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ChatBubble(message: message),
                      ),
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
                                  'AI-коуч анализирует статистику и готовит ответ...'),
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
                isUser ? 'Ты' : 'AI-коуч',
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

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
    this.includeInRequest = true,
  });

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
