import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/brand_logo.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  static const _logoSvgAsset = 'assets/branding/logo-full.svg';
  static const _logoAspectRatio = 1066.67 / 1058.59;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveStartupRoute();
    });
  }

  Future<void> _resolveStartupRoute() async {
    var hasValidSession = false;
    try {
      hasValidSession = await BackendApi.validateSession();
    } catch (_) {
      hasValidSession = false;
    }
    if (!mounted) {
      return;
    }
    context.go(hasValidSession ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackdrop(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: AspectRatio(
                  aspectRatio: _logoAspectRatio,
                  child: const BrandLogo(
                    assetName: _logoSvgAsset,
                    semanticsLabel: 'Путь Силы',
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
