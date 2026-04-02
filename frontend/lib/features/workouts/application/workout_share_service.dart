// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../heatmap/data/muscle_heatmap_asset_loader.dart';
import '../../heatmap/domain/muscle_heatmap_color_resolver.dart';
import '../../heatmap/domain/muscle_heatmap_models.dart';
import '../../heatmap/domain/muscle_load_calculator.dart';
import '../../heatmap/presentation/body_svg_colorizer.dart';
import '../presentation/workout_share_card.dart';

/// Builds the heatmap SVG + top muscle labels for a given workout,
/// then shows a preview dialog and lets the user download a 1080×1920 PNG.
///
/// Usage:
/// ```dart
/// await WorkoutShareService.share(
///   context: context,
///   workout: workout,
///   exerciseCatalog: catalog,
/// );
/// ```
class WorkoutShareService {
  const WorkoutShareService._();

  // ── Public entry point ───────────────────────────────────────────────

  static Future<void> share({
    required BuildContext context,
    required Map<String, dynamic> workout,
    required List<Map<String, dynamic>> exerciseCatalog,
    List<String> records = const [],
  }) async {
    // 1. Load heatmap assets (cached after first call)
    final assetData = await const MuscleHeatmapAssetLoader().load();

    // 2. Compute muscle loads
    final calc = const MuscleLoadCalculator();
    final rawLoads = calc.calculateForWorkout(
      workout: workout,
      exerciseCatalog: exerciseCatalog,
    );
    final normalizedLoads = calc.normalizer.normalize(rawLoads);

    // 3. Build colored SVG string synchronously
    final coloredSvg = _buildColoredSvg(assetData, normalizedLoads);

    // 4. Get top muscle labels
    final topMuscles = calc.buildTopMuscles(
      rawLoads: rawLoads,
      normalizedLoads: normalizedLoads,
      labels: assetData.zoneLabels,
      limit: 3,
    );
    final topLabels = topMuscles.map((m) => m.label).toList();

    // 5. Show the share dialog
    if (!context.mounted) return;
    await _showShareDialog(
      context: context,
      workout: workout,
      coloredSvg: coloredSvg,
      topMuscleLabels: topLabels,
      records: records,
    );
  }

  // ── Share dialog ─────────────────────────────────────────────────────

  static Future<void> _showShareDialog({
    required BuildContext context,
    required Map<String, dynamic> workout,
    required String coloredSvg,
    required List<String> topMuscleLabels,
    required List<String> records,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        workout: workout,
        coloredSvg: coloredSvg,
        topMuscleLabels: topMuscleLabels,
        records: records,
      ),
    );
  }

  // ── SVG helpers ──────────────────────────────────────────────────────

  static String _buildColoredSvg(
    MuscleHeatmapAssetData assetData,
    Map<String, double> normalizedLoads,
  ) {
    const resolver = MuscleHeatmapColorResolver();
    final idToColor = <String, String>{
      for (final id in assetData.allMappableSvgIds) id: assetData.defaultFill,
    };
    normalizedLoads.forEach((muscle, load) {
      final svgIds = assetData.muscleToSvgIds[muscle] ?? const [];
      final color = resolver.resolveHex(load);
      for (final id in svgIds) {
        idToColor[id] = color;
      }
    });
    return const BodySvgColorizer().colorize(
      svgSource: assetData.svgSource,
      svgIdToColor: idToColor,
      fallbackFill: assetData.defaultFill,
    );
  }

  // ── PNG capture ──────────────────────────────────────────────────────

  /// Captures the widget identified by [key] as a 1080×1920 PNG.
  static Future<Uint8List?> captureCard(GlobalKey key) async {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    // Wait two frames so flutter_svg has finished painting.
    await Future.delayed(const Duration(milliseconds: 300));

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

// ── Bottom sheet widget ──────────────────────────────────────────────────────

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.workout,
    required this.coloredSvg,
    required this.topMuscleLabels,
    required this.records,
  });

  final Map<String, dynamic> workout;
  final String coloredSvg;
  final List<String> topMuscleLabels;
  final List<String> records;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _repaintKey = GlobalKey();
  bool _capturing = false;

  // ── Download ─────────────────────────────────────────────────────────

  Future<void> _download() async {
    if (_capturing) return;
    setState(() => _capturing = true);

    try {
      final bytes = await WorkoutShareService.captureCard(_repaintKey);
      if (bytes == null) {
        if (!mounted) return;
        _showError('Не удалось создать изображение. Попробуйте ещё раз.');
        return;
      }
      final name = (widget.workout['name'] ?? 'workout').toString();
      final slug = name
          .toLowerCase()
          .replaceAll(RegExp(r'[^а-яёa-z0-9]', caseSensitive: false), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      WorkoutShareService.downloadPng(bytes, 'workout_$slug.png');
    } catch (e) {
      if (!mounted) return;
      _showError('Ошибка при создании изображения.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    // Reserve space for buttons + safe area; the card preview fills the rest.
    final previewAreaHeight = screenHeight * 0.72;
    // Scale factor to fit 540×960 card into the preview area
    final scale = (previewAreaHeight / WorkoutShareCard.cardHeight)
        .clamp(0.3, 1.0);
    final previewWidth = WorkoutShareCard.cardWidth * scale;
    final previewHeight = WorkoutShareCard.cardHeight * scale;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Text(
                  'Карточка тренировки',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Card preview (off-screen render inside RepaintBoundary, visible via scale)
          Center(
            child: SizedBox(
              width: previewWidth,
              height: previewHeight,
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: WorkoutShareCard(
                    workout: widget.workout,
                    coloredSvgSource: widget.coloredSvg,
                    topMuscleLabels: widget.topMuscleLabels,
                    records: widget.records,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Hint text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Сохраните как PNG и поделитесь в Instagram Stories или Telegram',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          // Download button
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.paddingOf(context).bottom + 20,
            ),
            child: FilledButton.icon(
              onPressed: _capturing ? null : _download,
              icon: _capturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(
                _capturing ? 'Создаём PNG...' : 'Скачать PNG · 1080×1920',
              ),
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
