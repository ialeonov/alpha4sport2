import 'package:flutter/widgets.dart';

import 'brand_logo_native.dart' if (dart.library.html) 'brand_logo_web.dart'
    as impl;

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.assetName,
    this.semanticsLabel,
  });

  final String assetName;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return impl.BrandLogoView(
      assetName: assetName,
      semanticsLabel: semanticsLabel,
    );
  }
}
