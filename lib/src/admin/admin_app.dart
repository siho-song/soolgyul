import 'dart:async';

import 'package:flutter/material.dart';

import '../design/app_theme.dart';
import '../design/app_tokens.dart';
import '../design/app_typography.dart';
import 'data/admin_editorial_gateway.dart';
import 'admin_editorial_models.dart';
import 'presentation/admin_dashboard_screen.dart';

class AdminApp extends StatelessWidget {
  const AdminApp({required this.gateway, super.key});

  final AdminEditorialGateway gateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '술결 관리자',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AdminAccessGate(gateway: gateway),
    );
  }
}

class AdminAccessGate extends StatefulWidget {
  const AdminAccessGate({required this.gateway, super.key});

  final AdminEditorialGateway gateway;

  @override
  State<AdminAccessGate> createState() => _AdminAccessGateState();
}

class _AdminAccessGateState extends State<AdminAccessGate> {
  StreamSubscription<AdminAuthSession?>? _sessionSubscription;
  AdminAuthSession? _session;
  AdminEditorialBootstrap? _bootstrap;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _session = widget.gateway.currentSession;
    _sessionSubscription = widget.gateway.sessionChanges.listen((session) {
      if (!mounted || session?.userId == _session?.userId) return;
      _session = session;
      unawaited(_load());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_sessionSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _bootstrap = null;
      });
    }
    if (_session == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final bootstrap = await widget.gateway.loadBootstrap();
      if (!mounted) return;
      setState(() {
        _bootstrap = bootstrap;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _AdminLoadingScreen();
    }
    if (_session == null) {
      return AdminLoginScreen(gateway: widget.gateway);
    }
    if (_error != null) {
      return _AdminMessageScreen(
        icon: Icons.cloud_off_outlined,
        title: '관리자 정보를 불러오지 못했어요',
        description: '네트워크와 Supabase 설정을 확인한 뒤 다시 시도해 주세요.',
        primaryLabel: '다시 시도',
        onPrimary: _load,
        onSignOut: widget.gateway.signOut,
      );
    }
    final bootstrap = _bootstrap;
    if (bootstrap == null) {
      return _AdminMessageScreen(
        icon: Icons.lock_outline,
        title: '관리자 권한이 없습니다',
        description: '이 계정에는 술결 관리자 역할이 부여되어 있지 않습니다.',
        primaryLabel: '로그아웃',
        onPrimary: widget.gateway.signOut,
      );
    }
    return AdminDashboardScreen(
      gateway: widget.gateway,
      session: _session!,
      initialBootstrap: bootstrap,
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({required this.gateway, super.key});

  final AdminEditorialGateway gateway;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _loginId = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _loginId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final loginId = _loginId.text.trim();
    final password = _password.text;
    if (loginId.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = '아이디와 비밀번호를 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    String? failure;
    try {
      await widget.gateway.signIn(loginId: loginId, password: password);
    } on AdminEditorialException catch (error) {
      failure = error.message == AdminEditorialException.invalidCredentials
          ? '아이디 또는 비밀번호가 맞지 않습니다.'
          : '로그인하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    } catch (_) {
      failure = '로그인하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _errorMessage = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfacePrimary,
                borderRadius: BorderRadius.circular(AppRadii.largeCard),
                border: Border.all(color: AppColors.borderSubtle),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 32,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 48,
                        color: AppColors.actionPrimary,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        '술결 관리자',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.screenTitle,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '관리자 아이디와 비밀번호로 로그인해 주세요.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body,
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      TextField(
                        key: const ValueKey<String>('admin-login-id'),
                        controller: _loginId,
                        enabled: !_busy,
                        autofocus: true,
                        autocorrect: false,
                        autofillHints: const <String>[AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: '아이디'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        key: const ValueKey<String>('admin-login-password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        autofillHints: const <String>[AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _signIn(),
                        decoration: const InputDecoration(labelText: '비밀번호'),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          key: const ValueKey<String>('admin-login-submit'),
                          onPressed: _busy ? null : _signIn,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textOnPrimary,
                                  ),
                                )
                              : const Text(
                                  '로그인',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                      if (_errorMessage != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          _errorMessage!,
                          key: const ValueKey<String>('admin-login-error'),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
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

class _AdminLoadingScreen extends StatelessWidget {
  const _AdminLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _AdminMessageScreen extends StatelessWidget {
  const _AdminMessageScreen({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.onSignOut,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 52, color: AppColors.actionPrimary),
                const SizedBox(height: AppSpacing.xl),
                Text(title, style: AppTextStyles.sectionTitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: AppSpacing.xxl),
                FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
                if (onSignOut != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(onPressed: onSignOut, child: const Text('로그아웃')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
