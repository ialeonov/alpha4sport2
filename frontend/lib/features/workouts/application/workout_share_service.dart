// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/storage/local_cache.dart';
import '../../heatmap/data/muscle_heatmap_asset_loader.dart';
import '../../heatmap/domain/muscle_heatmap_models.dart';
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../../heatmap/presentation/body_svg_colorizer.dart';
import '../presentation/workout_share_card.dart';

class WorkoutShareService {
  const WorkoutShareService._();

  // ── Public entry point ───────────────────────────────────────────────

  static Future<void> share({
    required BuildContext context,
    required Map<String, dynamic> workout,
    required List<Map<String, dynamic>> exerciseCatalog,
    List<String> records = const [],
  }) async {
    // Load everything in parallel
    final results = await Future.wait([
      const MuscleHeatmapAssetLoader().load(),
      _loadUserInfo(),
    ]);

    final assetData = results[0] as MuscleHeatmapAssetData;
    final userInfo = results[1] as ShareUserInfo?;

    final calc = const MuscleLoadCalculator();
    final rawLoads = calc.calculateForWorkout(
      workout: workout,
      exerciseCatalog: exerciseCatalog,
    );
    final normalizedLoads = calc.normalizer.normalize(rawLoads);
    final coloredSvg = _buildColoredSvg(assetData, normalizedLoads);

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        workout: workout,
        coloredSvg: coloredSvg,
        userInfo: userInfo,
        records: records,
      ),
    );
  }

  // ── User info loader ─────────────────────────────────────────────────

  static Future<ShareUserInfo?> _loadUserInfo() async {
    try {
      final futures = await Future.wait([
        BackendApi.getCurrentUser(),
        _loadTotalWorkoutCount(),
        BackendApi.getProgressionProfile().catchError((_) => <String, dynamic>{}),
      ]);
      final user = futures[0] as Map<String, dynamic>;
      final count = futures[1] as int?;
      final progressionRaw = futures[2] as Map<String, dynamic>;

      final progressionProfile =
          (progressionRaw['profile'] as Map?)?.cast<String, dynamic>();
      final title = progressionProfile?['title'] as String?;

      final rawAvatarUrl =
          (user['avatar_url'] ?? '').toString().trim();
      final resolvedUrl = rawAvatarUrl.isEmpty
          ? null
          : rawAvatarUrl.startsWith('http')
              ? rawAvatarUrl
              : rawAvatarUrl.startsWith('/')
                  ? '${BackendApi.configuredAssetBaseUrl}$rawAvatarUrl'
                  : '${BackendApi.configuredAssetBaseUrl}/uploads/$rawAvatarUrl';

      return ShareUserInfo(
        displayName:
            (user['display_name'] ?? '').toString().trim().isEmpty
                ? null
                : (user['display_name'] as String).trim(),
        resolvedAvatarUrl: resolvedUrl,
        totalWorkouts: count,
        title: title,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _loadTotalWorkoutCount() async {
    try {
      final cached = LocalCache.get<List>(CacheKeys.workoutsCache);
      if (cached != null) return cached.length;
      final workouts = await BackendApi.getWorkouts();
      return workouts.length;
    } catch (_) {
      return null;
    }
  }

  // ── SVG helpers ──────────────────────────────────────────────────────

  static String _buildColoredSvg(
    MuscleHeatmapAssetData assetData,
    Map<String, double> normalizedLoads,
  ) =>
      const BodySvgColorizer().colorizeFromLoads(
        assetData: assetData,
        normalizedLoads: normalizedLoads,
      );

  // ── PNG capture ──────────────────────────────────────────────────────

  static Future<Uint8List?> captureCard(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    // Allow SVG + network avatar to finish painting
    await Future.delayed(const Duration(milliseconds: 500));

    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  // ── Browser download ─────────────────────────────────────────────────

  static void downloadPng(Uint8List bytes, String filename) {
    final blob = html.Blob([bytes], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

// ── Bottom sheet ─────────────────────────────────────────────────────────────

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.workout,
    required this.coloredSvg,
    required this.userInfo,
    required this.records,
  });

  final Map<String, dynamic> workout;
  final String coloredSvg;
  final ShareUserInfo? userInfo;
  final List<String> records;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _repaintKey = GlobalKey();
  bool _capturing = false;

  Future<void> _download() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final bytes = await WorkoutShareService.captureCard(_repaintKey);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Не удалось создать изображение. Попробуйте ещё раз.')),
        );
        return;
      }
      final name = (widget.workout['name'] ?? 'workout').toString();
      final slug = name
          .toLowerCase()
          .replaceAll(RegExp(r'[^а-яёa-z0-9]', caseSensitive: false), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      WorkoutShareService.downloadPng(bytes, 'workout_$slug.png');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при создании изображения.')),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    final maxPreviewH = screenHeight * 0.70;
    final scale =
        (maxPreviewH / WorkoutShareCard.cardHeight).clamp(0.25, 1.0);
    final previewW = WorkoutShareCard.cardWidth * scale;
    final previewH = WorkoutShareCard.cardHeight * scale;

    return Container(
      height: screenHeight * 0.92,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 8, 0),
            child: Row(
              children: [
                Text(
                  'Карточка тренировки',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Scrollable card preview
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: previewW,
                  height: previewH,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(
                      key: _repaintKey,
                      child: WorkoutShareCard(
                        workout: widget.workout,
                        coloredSvgSource: widget.coloredSvg,
                        userInfo: widget.userInfo,
                        records: widget.records,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Download button — always visible
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPad + 20),
            child: FilledButton.icon(
              onPressed: _capturing ? null : _download,
              icon: _capturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_capturing ? 'Создаём...' : 'Скачать PNG'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
