import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: isDark
          ? child
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      scheme.surfaceBright.withValues(alpha: 0.06),
                      scheme.surface,
                    ),
                    scheme.surface,
                    Color.alphaBlend(
                      scheme.surfaceContainerLowest.withValues(alpha: 0.45),
                      scheme.surface,
                    ),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -90,
                    right: -40,
                    child: _GlowOrb(
                      size: 260,
                      color: scheme.secondary.withValues(alpha: 0.1),
                    ),
                  ),
                  Positioned(
                    top: 70,
                    left: -90,
                    child: _GlowOrb(
                      size: 240,
                      color: scheme.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  Positioned(
                    bottom: -150,
                    left: 10,
                    child: _GlowOrb(
                      size: 300,
                      color: scheme.tertiary.withValues(alpha: 0.04),
                    ),
                  ),
                  child,
                ],
              ),
            ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
