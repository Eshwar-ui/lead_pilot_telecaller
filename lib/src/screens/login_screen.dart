import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../core/api/api_exception.dart';
import '../services/session_store.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
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

class _LoginScreenState extends ConsumerState<LoginScreen> {
  String _email = '';
  String _password = '';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_email.trim().isEmpty || _password.isEmpty) {
      setState(() => _error = 'Enter your email and password');
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
      if (!mounted) return;
      context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isUnauthorized
            ? 'Incorrect email or password.'
            : 'Could not sign in — ${e.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not sign in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.blueRibbon,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'LP',
                      style: AppText.display20.copyWith(color: AppColors.white),
                    ),
                  ),
                  const AppGap.md(),
                  Text('LeadPilot', style: AppText.display24),
                  const AppGap.xs(),
                  Text(
                    'Sign in to see your assigned leads',
                    style: AppText.body14.copyWith(color: AppColors.schooner),
                  ),
                  const AppGap.lg(),
                  FormShell(
                    label: 'Email',
                    required: true,
                    child: LpTextField(
                      value: _email,
                      onChanged: (v) => setState(() => _email = v),
                      focused: true,
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
                    ),
                  ),
                  if (_error != null) ...[
                    const AppGap.sm(),
                    Text(_error!, style: AppText.body14.copyWith(color: AppColors.alizarin)),
                  ],
                  const AppGap.lg(),
                  PrimaryButton(
                    label: _loading ? 'Signing in…' : 'Sign In',
                    onTap: _loading ? null : _submit,
                  ),
                  const AppGap.md(),
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
      ),
    );
  }
}
