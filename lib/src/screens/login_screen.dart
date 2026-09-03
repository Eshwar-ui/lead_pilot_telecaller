import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppSpacing, AppRadius;

import '../core/api/api_exception.dart';
import '../services/local_call_store.dart';
import '../services/session_store.dart';
import '../services/user_profile_store.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

/// Email + password sign-in for telecallers invited by a founder.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _ErrorKind { validation, credentials, network, timeout, server }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String _email = '';
  String _password = '';
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  _ErrorKind _errorKind = _ErrorKind.validation;

  Future<void> _submit() async {
    if (_email.trim().isEmpty || _password.isEmpty) {
      setState(() {
        _error = 'Enter your email and password';
        _errorKind = _ErrorKind.validation;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final res = await client.post(
        '/api/auth/login',
        body: {'email': _email.trim(), 'password': _password},
      );
      final map = res as Map<String, dynamic>;
      await ref
          .read(sessionProvider.notifier)
          .setSession(
            token: map['access_token'] as String,
            user: map['user'] as Map<String, dynamic>,
          );
      ref.invalidate(userProfileProvider);
      ref.invalidate(orgProfileProvider);
      ref.invalidate(leadsProvider);
      ref.invalidate(leadsUsingFallbackProvider);
      ref.invalidate(followUpsProvider);
      ref.invalidate(localCallsProvider);
      ref.invalidate(leadStageProvider);
      ref.invalidate(checklistExtrasProvider);
      ref.invalidate(callNotesProvider);
      ref.invalidate(selectedLeadIdProvider);
      ref.invalidate(telecallerScoreProvider);
      ref.invalidate(attendanceProvider);
      if (!mounted) return;
      final user = map['user'] as Map<String, dynamic>;
      if (user['must_reset_password'] == true) {
        context.go(
          '/change-password-required',
          extra: {'currentPassword': _password},
        );
      } else {
        context.go('/home');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageFor(e);
        _errorKind = _kindFor(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not sign in. Check your connection and try again.';
        _errorKind = _ErrorKind.network;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _messageFor(ApiException e) {
    if (e.isUnauthorized) return 'Incorrect email or password.';
    if (e.isTimeout) {
      return 'The server is taking too long to respond. Please try again.';
    }
    if (e.isServerError) {
      return 'Something went wrong on our end. Please try again in a moment.';
    }
    if (e.isNetworkError) {
      return "Can't reach the server. Check your internet connection and try again.";
    }
    return 'Could not sign in — ${e.message}';
  }

  _ErrorKind _kindFor(ApiException e) {
    if (e.isUnauthorized) return _ErrorKind.credentials;
    if (e.isTimeout) return _ErrorKind.timeout;
    if (e.isServerError) return _ErrorKind.server;
    return _ErrorKind.network;
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final reachable = ref.watch(serverReachableProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.zeus,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const Positioned.fill(child: _LoginBackdrop()),
            SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.only(bottom: padding.bottom + 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Semantics(
                                label: 'Asan Innovators logo',
                                image: true,
                                child: Image.asset(
                                  'assets/images/asan_logo.png',
                                  width: 116,
                                  height: 72,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Telecaller workspace',
                                style: AppText.display16.copyWith(
                                  color: Colors.white,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 34),
                          Text(
                            'Make every\nconversation count.',
                            style: AppText.display24.copyWith(
                              color: Colors.white,
                              fontSize: 34,
                              height: 1.06,
                              letterSpacing: -1.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text(
                              'Your next best lead, the right context, and the follow-up that keeps momentum moving.',
                              style: AppText.body14.copyWith(
                                color: Colors.white.withValues(alpha: 0.68),
                                height: 1.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const _SignalChip(),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      padding: EdgeInsets.fromLTRB(
                        24,
                        28,
                        24,
                        28 + padding.bottom,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.springWood,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 28,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: !reachable
                          ? NoServerConnectionScreen(
                              title: "Can't reach the server",
                              message:
                                  'Check your internet connection, or the '
                                  'server may be temporarily down.',
                              retryLabel: 'Try Again',
                              onRetry: () => ref
                                  .read(serverReachableProvider.notifier)
                                  .retryNow(),
                              wrapWithScaffold: false,
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Welcome back',
                                  style: AppText.display24.copyWith(
                                    fontSize: 24,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Sign in to see your assigned leads.',
                                  style: AppText.body14.copyWith(
                                    color: AppColors.schooner,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                FormShell(
                                  label: 'Email',
                                  required: true,
                                  child: LpTextField(
                                    value: _email,
                                    onChanged: (v) =>
                                        setState(() => _email = v),
                                    focused: true,
                                    enabled: !_loading,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FormShell(
                                  label: 'Password',
                                  required: true,
                                  child: LpTextField(
                                    value: _password,
                                    onChanged: (v) =>
                                        setState(() => _password = v),
                                    obscureText: _obscurePassword,
                                    enabled: !_loading,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                        color: AppColors.schooner,
                                      ),
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  _ErrorBanner(
                                    kind: _errorKind,
                                    message: _error!,
                                  ),
                                ],
                                const SizedBox(height: 28),
                                PrimaryButton(
                                  label: 'Sign in to Asan Telecaller',
                                  icon: Icons.arrow_forward_rounded,
                                  onTap: _submit,
                                  loading: _loading,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'New here? Ask your founder or manager to invite you.\n'
                                  'Telecallers are added from the web portal.',
                                  textAlign: TextAlign.center,
                                  style: AppText.caption11.copyWith(
                                    color: AppColors.schooner,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF65D6A3),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Asan sales team workspace',
            style: AppText.caption11.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.zeus, Color(0xFF101F4A), Color(0xFF163B85)],
          stops: [0, 0.58, 1],
        ),
      ),
      child: CustomPaint(painter: _BackdropPainter()),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final accentPaint = Paint()
      ..color = AppColors.blueRibbon.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var x = -size.height; x < size.width; x += 44) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        linePaint,
      );
    }

    final orb = Offset(size.width * 0.93, size.height * 0.16);
    canvas.drawCircle(orb, 108, accentPaint);
    canvas.drawCircle(orb, 78, accentPaint);

    final lowerRule = Path()
      ..moveTo(size.width * 0.58, size.height * 0.60)
      ..lineTo(size.width + 20, size.height * 0.60);
    canvas.drawPath(lowerRule, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) => false;
}

// ── Error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.kind, required this.message});

  final _ErrorKind kind;
  final String message;

  @override
  Widget build(BuildContext context) {
    final (icon, fg, bg, border) = switch (kind) {
      _ErrorKind.credentials => (
        Icons.lock_outline,
        AppColors.alizarin,
        AppColors.redSurface,
        AppColors.redBorder,
      ),
      _ErrorKind.server => (
        Icons.dns_outlined,
        AppColors.warningText,
        AppColors.warningSurface,
        AppColors.warningBorder,
      ),
      _ErrorKind.timeout => (
        Icons.hourglass_empty,
        AppColors.warningText,
        AppColors.warningSurface,
        AppColors.warningBorder,
      ),
      _ErrorKind.network => (
        Icons.cloud_off_outlined,
        AppColors.warningText,
        AppColors.warningSurface,
        AppColors.warningBorder,
      ),
      _ErrorKind.validation => (
        Icons.error_outline,
        AppColors.alizarin,
        AppColors.redSurface,
        AppColors.redBorder,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const AppGap.xs(axis: Axis.horizontal),
          Expanded(
            child: Text(message, style: AppText.body14.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}
