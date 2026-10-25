import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _tabular = [FontFeature.tabularFigures()];

String formatRestSeconds(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// Таймер отдыха между подходами. Один на экран тренировки: запускается
/// кнопкой в шапке или автоматически после записи подхода.
class RestTimerController extends ChangeNotifier {
  static const presets = [60, 90, 120, 180];

  /// Последняя выбранная длительность — общая для всех тренировок сессии.
  static int lastSeconds = 90;

  Timer? _ticker;
  DateTime? _endsAt;
  int _remaining = 0;

  /// Вызывается, когда отдых закончился (не при ручной остановке).
  VoidCallback? onFinished;

  bool get running => _endsAt != null;
  int get remaining => _remaining;

  void start([int? seconds]) {
    final duration = seconds ?? lastSeconds;
    lastSeconds = duration;
    _ticker?.cancel();
    _endsAt = DateTime.now().add(Duration(seconds: duration));
    _remaining = duration;
    // Считаем от времени окончания, а не по тикам: таймер не «плывёт»,
    // даже если приложение было в фоне.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    notifyListeners();
  }

  void addSeconds(int seconds) {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    _endsAt = endsAt.add(Duration(seconds: seconds));
    _tick();
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    if (_endsAt == null) return;
    _endsAt = null;
    notifyListeners();
  }

  void _tick() {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    final left = endsAt.difference(DateTime.now()).inMilliseconds;
    if (left <= 0) {
      stop();
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      onFinished?.call();
      return;
    }
    final seconds = (left / 1000).ceil();
    if (seconds != _remaining) {
      _remaining = seconds;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Полоса отдыха на всю ширину над экраном тренировки — видна только пока
/// идёт отсчёт.
class RestTimerBar extends StatelessWidget {
  const RestTimerBar({super.key, required this.controller});

  final RestTimerController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: !controller.running
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                color: scheme.primary,
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ОТДЫХ',
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            formatRestSeconds(controller.remaining),
                            style: TextStyle(
                              fontFamily: 'Bebas Neue Cyrillic',
                              fontSize: 38,
                              height: 1,
                              color: scheme.onPrimary,
                              fontFeatures: _tabular,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _BarButton(
                      label: '+30 с',
                      onPressed: () => controller.addSeconds(30),
                      filled: false,
                    ),
                    const SizedBox(width: 8),
                    _BarButton(
                      label: 'Дальше',
                      onPressed: controller.stop,
                      filled: true,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.onPressed,
    required this.filled,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: filled
              ? scheme.onPrimary
              : scheme.onPrimary.withValues(alpha: 0.12),
          foregroundColor: filled ? scheme.primary : scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Кнопка в шапке: выбор длительности и ручной запуск.
class RestTimerButton extends StatelessWidget {
  const RestTimerButton({super.key, required this.controller});

  final RestTimerController controller;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(box.size.bottomLeft(Offset.zero), ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<int>(
      context: context,
      position: position,
      items: [
        for (final seconds in RestTimerController.presets)
          PopupMenuItem(
            value: seconds,
            child: Text(
              'Отдых ${formatRestSeconds(seconds)}',
              style: seconds == RestTimerController.lastSeconds
                  ? const TextStyle(fontWeight: FontWeight.w800)
                  : null,
            ),
          ),
        if (controller.running)
          const PopupMenuItem(value: -1, child: Text('Остановить')),
      ],
    );
    if (choice == null) return;
    choice == -1 ? controller.stop() : controller.start(choice);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Таймер отдыха',
      icon: const Icon(Icons.timer_outlined),
      onPressed: () => _openMenu(context),
    );
  }
}
