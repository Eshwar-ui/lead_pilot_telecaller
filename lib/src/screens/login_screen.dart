import 'dart:ui';

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

/// Email + password sign-in. Telecallers are invited by a founder (via the
/// web portal's team management) with a one-time temp password — there is no
/// self-signup here. Phone/OTP login (matching the original design mockups)
/// is a deliberate later step; this ships first because it needs no new
/// backend work — `POST /api/auth/login` already exists and is what the
/// founder web app uses too.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

/// What kind of failure `_error` is describing — drives which icon/color the
/// error banner uses, so "you typed the wrong password" reads nothing like
/// "our server is down" at a glance.
enum _ErrorKind { validation, credentials, network, timeout, server }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String _email = '';
  String _password = '';
  bool _loading = false;
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
      await ref.read(sessionProvider.notifier).setSession(
        token: map['access_token'] as String,
        user: map['user'] as Map<String, dynamic>,
      );
      // Mirror of the invalidation on logout (see profile_screen.dart): the
      // *previous* logout already invalidated these while the token was
      // null, so their rebuild fetched with no auth and fell back to
      // mock/empty state. Without invalidating again now that a real token
      // exists, that stale state would sit there un-refreshed until the app
      // is restarted — the "stale data after re-login" bug.
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
        context.go('/change-password-required', extra: {'currentPassword': _password});
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

  /// Distinct copy per failure mode — wrong password reads nothing like a
  /// dead backend, and a slow server reads nothing like no network at all.
  String _messageFor(ApiException e) {
    if (e.isUnauthorized) return 'Incorrect email or password.';
    if (e.isTimeout) {
      return "The server is taking too long to respond. Please try again.";
    }
    if (e.isServerError) {
      return "Something went wrong on our end. Please try again in a moment.";
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
    final topInset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.springWood,
        body: SafeArea(
          top: false,
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(topInset: topInset),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xxl,
                    AppSpacing.xl,
                    AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Welcome back', style: AppText.display24),
                          const AppGap.xs(),
                          Text(
                            'Sign in to see your assigned leads',
                            style: AppText.body14.copyWith(color: AppColors.schooner),
                          ),
                          const AppGap.xl(),
                          FormShell(
                            label: 'Email',
                            required: true,
                            child: LpTextField(
                              value: _email,
                              onChanged: (v) => setState(() => _email = v),
                              focused: true,
                              enabled: !_loading,
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                          const AppGap.md(),
                          FormShell(
                            label: 'Password',
                            required: true,
                            child: LpTextField(
                              value: _password,
                              onChanged: (v) => setState(() => _password = v),
                              obscureText: true,
                              enabled: !_loading,
                            ),
                          ),
                          if (_error != null) ...[
                            const AppGap.md(),
                            _ErrorBanner(kind: _errorKind, message: _error!),
                          ],
                          const AppGap.xl(),
                          PrimaryButton(
                            label: 'Sign In',
                            onTap: _submit,
                            loading: _loading,
                          ),
                          const AppGap.lg(),
                          Text(
                            'New to LeadPilot? Ask your founder or manager to invite you —\n'
                            'telecallers are added from the web portal, not self-signup.',
                            textAlign: TextAlign.center,
                            style: AppText.caption11.copyWith(color: AppColors.schooner),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-bleed blue header — the app's whole "brand moment" now that there's
/// no boxed logo mark; the color and the wordmark carry it instead.
class _Hero extends StatelessWidget {
  const _Hero({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(AppSpacing.xl, topInset + AppSpacing.xxl, AppSpacing.xl, AppSpacing.xxl + AppSpacing.md),
        decoration: const BoxDecoration(color: AppColors.blueRibbon),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LeadPilot',
                  style: AppText.display24.copyWith(
                    color: AppColors.white,
                    fontSize: 32,
                    letterSpacing: -0.6,
                  ),
                ),
                const AppGap.xs(),
                Text(
                  'AI call intelligence for your sales team',
                  style: AppText.body14.copyWith(
                    color: AppColors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Distinct visual per failure mode (item 3 — previously a single plain-text
/// line for every error, with no way to tell "wrong password" apart from
/// "server is down" at a glance).
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
            child: Text(
              message,
              style: AppText.body14.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
