import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/backend_api.dart';
import '../../../core/widgets/app_backdrop.dart';
import '../../../core/widgets/brand_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _logoSvgAsset = 'assets/branding/logo-full.svg';
  static const _logoAspectRatio = 1066.67 / 1058.59;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isRegisterMode = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  String? _validateFields() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty) {
      return 'Введите email.';
    }
    if (!email.contains('@') || !email.contains('.')) {
      return 'Введите корректный email.';
    }
    if (password.isEmpty) {
      return 'Введите пароль.';
    }
    if (_isRegisterMode && password.length < 6) {
      return 'Пароль должен быть не короче 6 символов.';
    }
    return null;
  }

  Future<void> _login() async {
    if (_isLoading) {
      return;
    }

    final error = _validateFields();
    if (error != null) {
      _showErrorText(error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await BackendApi.login(
        baseUrl: BackendApi.configuredBaseUrl,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      context.go('/home');
    } catch (error) {
      _showError(error, fallback: 'Не удалось выполнить вход.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _register() async {
    if (_isLoading) {
      return;
    }

    final error = _validateFields();
    if (error != null) {
      _showErrorText(error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await BackendApi.register(
        baseUrl: BackendApi.configuredBaseUrl,
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) {
        return;
      }
      context.go('/home');
    } catch (error) {
      _showError(error, fallback: 'Не удалось создать аккаунт.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorText(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showError(Object error, {required String fallback}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(BackendApi.describeError(error, fallback: fallback)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 280),
                            child: AspectRatio(
                              aspectRatio: _logoAspectRatio,
                              child: const BrandLogo(
                                assetName: _logoSvgAsset,
                                semanticsLabel: 'Путь Силы',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text(
                            _isRegisterMode
                                ? 'Создайте тренировочный аккаунт'
                                : 'Войдите в тренировочный журнал',
                            key: ValueKey(_isRegisterMode),
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          onSubmitted: (_) =>
                              _passwordFocusNode.requestFocus(),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          onSubmitted: (_) =>
                              _isRegisterMode ? _register() : _login(),
                        ),
                        const SizedBox(height: 20),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: _isRegisterMode
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FilledButton(
                                      onPressed:
                                          _isLoading ? null : _register,
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'Создать аккаунт'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () => setState(() =>
                                              _isRegisterMode = false),
                                      child: const Text(
                                          'Уже есть аккаунт? Войти'),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FilledButton(
                                      onPressed:
                                          _isLoading ? null : _login,
                                      child: _isLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Войти'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () => setState(() =>
                                              _isRegisterMode = true),
                                      child: const Text(
                                          'Нет аккаунта? Создать'),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Developed by Ivan Leonov · ialeonov@gmail.com · 2026',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
