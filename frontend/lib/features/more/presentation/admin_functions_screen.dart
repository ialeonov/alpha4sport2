import 'package:flutter/material.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/athletic_ui.dart';
import '../../coach/presentation/coach_owner_history_screen.dart';

class AdminFunctionsScreen extends StatelessWidget {
  const AdminFunctionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Админ функции'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'История AI-коуча'),
              Tab(text: 'Сообщения'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CoachOwnerHistoryScreen(showAppBar: false),
            _AnnouncementAdminTab(),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementAdminTab extends StatefulWidget {
  const _AnnouncementAdminTab();

  @override
  State<_AnnouncementAdminTab> createState() => _AnnouncementAdminTabState();
}

class _AnnouncementAdminTabState extends State<_AnnouncementAdminTab> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();

  Map<String, dynamic>? _currentAnnouncement;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAnnouncement();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _loadAnnouncement() async {
    setState(() => _isLoading = true);
    try {
      final announcement = await BackendApi.getAdminCurrentAnnouncement();
      if (!mounted) return;
      setState(() {
        _currentAnnouncement = announcement;
        if (announcement != null) {
          _titleController.text = (announcement['title'] ?? '').toString();
          _bodyController.text = (announcement['body'] ?? '').toString();
        } else {
          _titleController.clear();
          _bodyController.clear();
        }
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        BackendApi.describeError(
          error,
          fallback: 'Не удалось загрузить текущее сообщение.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _publish() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.length < 3 || body.length < 3) {
      _showMessage('Заполните заголовок и текст сообщения.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final announcement = await BackendApi.publishAnnouncement(
        title: title,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _currentAnnouncement = announcement;
      });
      _showMessage(
        'Сообщение опубликовано. Пользователи увидят его при открытии приложения.',
      );
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        BackendApi.describeError(
          error,
          fallback: 'Не удалось опубликовать сообщение.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _clearAnnouncement() async {
    setState(() => _isSaving = true);
    try {
      await BackendApi.clearAnnouncement();
      if (!mounted) return;
      setState(() {
        _currentAnnouncement = null;
      });
      _showMessage('Активное сообщение отключено.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        BackendApi.describeError(
          error,
          fallback: 'Не удалось отключить сообщение.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppBackdrop(
      child: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadAnnouncement,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    DashboardSummaryCard(
                      title: _currentAnnouncement == null
                          ? 'Сообщение сейчас выключено'
                          : 'Активное сообщение включено',
                      subtitle: _currentAnnouncement == null
                          ? 'Создайте объявление, и оно будет показано всем пользователям при открытии приложения.'
                          : 'Сейчас пользователям показывается последнее опубликованное сообщение.',
                    ),
                    const SizedBox(height: 16),
                    DashboardCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Публикация сообщения',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Заголовок',
                              hintText: 'Например: Технические работы',
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _bodyController,
                            minLines: 5,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              labelText: 'Текст сообщения',
                              alignLabelWithHint: true,
                              hintText:
                                  'Напишите текст, который увидят все пользователи.',
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isSaving ? null : _publish,
                                  icon: const Icon(Icons.campaign_rounded),
                                  label: Text(
                                    _currentAnnouncement == null
                                        ? 'Опубликовать'
                                        : 'Опубликовать заново',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed:
                                    _isSaving || _currentAnnouncement == null
                                        ? null
                                        : _clearAnnouncement,
                                icon: const Icon(Icons.visibility_off_rounded),
                                label: const Text('Отключить'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_currentAnnouncement != null) ...[
                      const SizedBox(height: 16),
                      DashboardCard(
                        leftAccentColor: scheme.secondary,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Предпросмотр активного сообщения',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              (_currentAnnouncement!['title'] ?? '').toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              (_currentAnnouncement!['body'] ?? '').toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
