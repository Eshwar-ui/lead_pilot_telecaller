import 'package:flutter/material.dart';

import '../services/app_permissions.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

/// The one place that says what this app asks the phone for, and why.
///
/// Shown at startup while anything is still missing, and reachable any time
/// from Profile. Always dismissable: some of these are OEM settings screens
/// that a given phone may not even have, and an app that cannot be entered
/// until Android grants something Android may never offer is worse than a
/// telecaller working with one feature degraded.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PermissionsScreen()),
    );
  }

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  static const _permissions = AppPermissions();

  Map<AppPermission, bool> _granted = const {};

  /// Ones Android will no longer prompt for. Their button has to send the
  /// telecaller to app settings instead, or "Allow" does nothing at all while
  /// this screen keeps returning every launch.
  Set<AppPermission> _blocked = const {};
  bool _loading = true;
  AppPermission? _busy;
  bool _runningAll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Half of these are granted on a settings page outside the app, which
    // gives no callback — the only reliable moment to re-read them is when
    // the telecaller lands back here.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final result = <AppPermission, bool>{};
    final blocked = <AppPermission>{};
    for (final permission in AppPermission.values) {
      final granted = await _permissions.isGranted(permission);
      result[permission] = granted;
      if (!granted && await _permissions.isPermanentlyDenied(permission)) {
        blocked.add(permission);
      }
    }
    if (!mounted) return;
    setState(() {
      _granted = result;
      _blocked = blocked;
      _loading = false;
    });
  }

  Future<void> _requestOne(AppPermission permission) async {
    setState(() => _busy = permission);
    if (_blocked.contains(permission)) {
      await _permissions.openSettings();
    } else {
      await _permissions.request(permission);
    }
    if (!mounted) return;
    setState(() => _busy = null);
    await _refresh();
  }

  Future<void> _requestAll() async {
    setState(() => _runningAll = true);
    for (final permission in AppPermission.values) {
      if (_granted[permission] == true) continue;
      // Skipped by "Allow all": its prompt no longer appears, so requesting it
      // would be a silent no-op in the middle of the run. Its own row sends
      // the telecaller to settings instead.
      if (_blocked.contains(permission)) continue;
      if (!mounted) return;
      setState(() => _busy = permission);
      await _permissions.request(permission);
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _runningAll = false;
    });
    await _refresh();
  }

  int get _grantedCount => _granted.values.where((v) => v).length;

  @override
  Widget build(BuildContext context) {
    final total = AppPermission.values.length;
    final allGranted = !_loading && _grantedCount == total;

    return Scaffold(
      backgroundColor: AppColors.springWood,
      appBar: AppBar(
        backgroundColor: AppColors.springWood,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Permissions', style: AppText.display16),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allGranted
                        ? 'Everything is set up.'
                        : 'What the app needs, and why',
                    style: AppText.display16,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    allGranted
                        ? 'Your calls will be captured, matched to leads and '
                              'scored automatically.'
                        : 'You can allow these one at a time, and change any '
                              'of them later from your Profile. '
                              '$_grantedCount of $total allowed.',
                    style: AppText.body13.copyWith(color: AppColors.schooner),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: AppPermission.values.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (_, i) {
                        final permission = AppPermission.values[i];
                        return _PermissionRow(
                          permission: permission,
                          granted: _granted[permission] ?? false,
                          blocked: _blocked.contains(permission),
                          busy: _busy == permission,
                          onAllow: _runningAll
                              ? null
                              : () => _requestOne(permission),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                children: [
                  if (!allGranted)
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: _runningAll ? 'Asking…' : 'Allow all',
                        icon: _runningAll ? null : Icons.check_circle_outline,
                        onTap: _runningAll ? null : _requestAll,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: _runningAll
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    child: Text(
                      allGranted ? 'Done' : 'Not now',
                      style: AppText.body13.copyWith(color: AppColors.merlin),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.granted,
    required this.blocked,
    required this.busy,
    required this.onAllow,
  });

  final AppPermission permission;
  final bool granted;

  /// Android will not prompt for this any more — the button opens settings.
  final bool blocked;

  final bool busy;
  final VoidCallback? onAllow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: granted ? AppColors.iceCold : AppColors.westar,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: granted ? AppColors.foam : AppColors.pampas,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              permission.icon,
              size: 18,
              color: granted ? AppColors.greenHaze : AppColors.merlin,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(permission.title, style: AppText.display16.copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  permission.why,
                  style: AppText.body13.copyWith(
                    color: AppColors.schooner,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (granted)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.greenHaze,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Allowed',
                        style: AppText.caption11.copyWith(
                          color: AppColors.greenHaze,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    height: 30,
                    child: OutlinedButton(
                      onPressed: busy ? null : onAllow,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.blueRibbon,
                        side: const BorderSide(color: AppColors.ribbonBorder),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                      ),
                      child: Text(
                        busy
                            ? 'Asking…'
                            : blocked
                            ? 'Open settings'
                            : 'Allow',
                        style: AppText.caption11.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
