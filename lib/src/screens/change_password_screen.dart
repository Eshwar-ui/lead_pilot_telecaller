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

/// Two modes:
/// - [forced]=true: reached right after login when the backend flags
///   `must_reset_password` (a fresh invite/reset temp password). No back
///   button, no "current password" field — [knownCurrentPassword] is the temp
///   password the user just typed at login, sent silently.
/// - [forced]=false: reached voluntarily from Profile. Shows a "Current
///   password" field the user must type themselves.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, required this.forced, this.knownCurrentPassword});

  final bool forced;
  final String? knownCurrentPassword;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  String _currentPassword = '';
  String _newPassword = '';
  String _confirmPassword = '';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final currentPassword = widget.forced ? (widget.knownCurrentPassword ?? '') : _currentPassword;
    if (currentPassword.isEmpty || _newPassword.isEmpty) {
      setState(() => _error = 'Fill in all fields');
      return;
    }
    if (_newPassword != _confirmPassword) {
      setState(() => _error = "New password and confirmation don't match");
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      await client.post(
        '/api/auth/change-password',
        body: {'current_password': currentPassword, 'new_password': _newPassword},
      );
      await ref.read(sessionProvider.notifier).clearMustResetPassword();
      if (!mounted) return;
      context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.isUnauthorized
            ? 'Current password is incorrect.'
            : 'Could not change password — ${e.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not change password. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      appBar: widget.forced
          ? null
          : AppBar(
              backgroundColor: AppColors.springWood,
              elevation: 0,
              // Explicit back button so this screen is always dismissable, even
              // if it was reached without a poppable stack (falls back to Home).
              leading: BackButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
              title: Text('Change Password', style: AppText.display20),
            ),
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
                  if (widget.forced) ...[
                    Text('Set a New Password', style: AppText.display24),
                    const AppGap.xs(),
                    Text(
                      'Your account was invited or reset with a temporary password — '
                      'set your own before continuing.',
                      style: AppText.body14.copyWith(color: AppColors.schooner),
                    ),
                    const AppGap.lg(),
                  ],
                  if (!widget.forced) ...[
                    FormShell(
                      label: 'Current Password',
                      required: true,
                      child: LpTextField(
                        value: _currentPassword,
                        onChanged: (v) => setState(() => _currentPassword = v),
                        obscureText: true,
                      ),
                    ),
                    const AppGap.md(),
                  ],
                  FormShell(
                    label: 'New Password',
                    required: true,
                    child: LpTextField(
                      value: _newPassword,
                      onChanged: (v) => setState(() => _newPassword = v),
                      obscureText: true,
                    ),
                  ),
                  const AppGap.md(),
                  FormShell(
                    label: 'Confirm New Password',
                    required: true,
                    child: LpTextField(
                      value: _confirmPassword,
                      onChanged: (v) => setState(() => _confirmPassword = v),
                      obscureText: true,
                    ),
                  ),
                  if (_error != null) ...[
                    const AppGap.sm(),
                    Text(_error!, style: AppText.body14.copyWith(color: AppColors.alizarin)),
                  ],
                  const AppGap.lg(),
                  PrimaryButton(
                    label: _loading ? 'Changing…' : 'Set New Password',
                    onTap: _loading ? null : _submit,
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
