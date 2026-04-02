import 'package:flutter/material.dart';

const _brandOrange = Color(0xFFC96F44);
const _brandOrangeLight = Color(0xFFD88858);
const _brandStroke = Color(0xFF2A2421);

class BrandIcon extends StatelessWidget {
  const BrandIcon({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandIconPainter(),
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: Theme.of(context).colorScheme.onSurface,
        );
    final resolvedStyle =
        defaultStyle?.merge(style) ?? style ?? const TextStyle();

    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        style: resolvedStyle,
        children: const [
          TextSpan(text: 'Alpha'),
          TextSpan(
            text: '4',
            style: TextStyle(
              color: _brandOrange,
              fontWeight: FontWeight.w900,
            ),
          ),
          TextSpan(text: 'Sport'),
        ],
      ),
    );
  }
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.iconSize = 64,
    this.spacing = 14,
    this.textStyle,
    this.textAlign = TextAlign.start,
  });

  final double iconSize;
  final double spacing;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandIcon(size: iconSize),
        SizedBox(width: spacing),
        Flexible(
          child: BrandWordmark(
            style: textStyle,
            textAlign: textAlign,
          ),
        ),
      ],
    );
  }
}

class _BrandIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_brandOrangeLight, _brandOrange],
      ).createShader(Offset.zero & size);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = _brandStroke
      ..strokeWidth = w * 0.035
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final handleOuter = Path()
      ..moveTo(w * 0.34, h * 0.08)
      ..quadraticBezierTo(w * 0.5, h * 0.01, w * 0.66, h * 0.08)
      ..lineTo(w * 0.73, h * 0.2)
      ..quadraticBezierTo(w * 0.63, h * 0.24, w * 0.58, h * 0.34)
      ..lineTo(w * 0.42, h * 0.34)
      ..quadraticBezierTo(w * 0.37, h * 0.24, w * 0.27, h * 0.2)
      ..close();

    final bodyPath = Path()
      ..moveTo(w * 0.22, h * 0.42)
      ..quadraticBezierTo(w * 0.12, h * 0.55, w * 0.16, h * 0.76)
      ..quadraticBezierTo(w * 0.28, h * 0.95, w * 0.5, h * 0.96)
      ..quadraticBezierTo(w * 0.72, h * 0.95, w * 0.84, h * 0.76)
      ..quadraticBezierTo(w * 0.88, h * 0.55, w * 0.78, h * 0.42)
      ..quadraticBezierTo(w * 0.66, h * 0.3, w * 0.5, h * 0.3)
      ..quadraticBezierTo(w * 0.34, h * 0.3, w * 0.22, h * 0.42)
      ..close();

    final leftWing = Path()
      ..moveTo(w * 0.08, h * 0.61)
      ..quadraticBezierTo(w * 0.12, h * 0.7, w * 0.2, h * 0.73)
      ..lineTo(w * 0.33, h * 0.61)
      ..lineTo(w * 0.47, h * 0.48)
      ..lineTo(w * 0.5, h * 0.57)
      ..lineTo(w * 0.37, h * 0.73)
      ..quadraticBezierTo(w * 0.22, h * 0.84, w * 0.11, h * 0.79)
      ..close();

    final rightWing = Path()
      ..moveTo(w * 0.92, h * 0.61)
      ..quadraticBezierTo(w * 0.88, h * 0.7, w * 0.8, h * 0.73)
      ..lineTo(w * 0.67, h * 0.61)
      ..lineTo(w * 0.53, h * 0.48)
      ..lineTo(w * 0.5, h * 0.57)
      ..lineTo(w * 0.63, h * 0.73)
      ..quadraticBezierTo(w * 0.78, h * 0.84, w * 0.89, h * 0.79)
      ..close();

    final centerLines = <Path>[
      Path()
        ..moveTo(w * 0.5, h * 0.31)
        ..lineTo(w * 0.5, h * 0.84),
      Path()
        ..moveTo(w * 0.2, h * 0.73)
        ..lineTo(w * 0.38, h * 0.61)
        ..lineTo(w * 0.5, h * 0.72),
      Path()
        ..moveTo(w * 0.8, h * 0.73)
        ..lineTo(w * 0.62, h * 0.61)
        ..lineTo(w * 0.5, h * 0.72),
      Path()
        ..moveTo(w * 0.29, h * 0.54)
        ..lineTo(w * 0.41, h * 0.46)
        ..lineTo(w * 0.5, h * 0.54),
      Path()
        ..moveTo(w * 0.71, h * 0.54)
        ..lineTo(w * 0.59, h * 0.46)
        ..lineTo(w * 0.5, h * 0.54),
    ];

    for (final path in [bodyPath, handleOuter, leftWing, rightWing]) {
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = _brandStroke
      ..strokeWidth = w * 0.03
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final line in centerLines) {
      canvas.drawPath(line, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
