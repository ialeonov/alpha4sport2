import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BrandLogoView extends StatelessWidget {
  const BrandLogoView({
    super.key,
    required this.assetName,
    this.semanticsLabel,
  });

  final String assetName;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetName,
      fit: BoxFit.contain,
      semanticsLabel: semanticsLabel,
    );
  }
}
