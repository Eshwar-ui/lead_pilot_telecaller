import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing, AppRadius;

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // ── User card ─────────────────────────────────────────────────
            _UserCard(),

            const SizedBox(height: AppSpacing.md),

            // ── Monthly stats ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('THIS MONTH', style: AppText.label11),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: const [
                      Expanded(
                        child: MetricTile(label: 'Calls Made', value: '142', mono: true),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: MetricTile(
                          label: 'Qualified',
                          value: '6',
                          valueColor: AppColors.governorBay,
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: const [
                      Expanded(
                        child: MetricTile(
                          label: 'Avg Score',
                          value: '86',
                          valueColor: AppColors.salem,
                          mono: true,
                        ),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: MetricTile(
                          label: 'Conv Rate',
                          value: '18%',
                          valueColor: AppColors.electricViolet,
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Preferences ───────────────────────────────────────────────
            _SettingsSection(
              title: 'PREFERENCES',
              children: [
                _LanguageRow(),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsRow(
                  icon: Icons.notifications_outlined,
                  label: 'Notifications',
                  trailing: _GreenBadge('On'),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Compliance ────────────────────────────────────────────────
            _SettingsSection(
              title: 'COMPLIANCE',
              children: [
                _SettingsRow(
                  icon: Icons.verified_outlined,
                  label: 'Privacy Policy Compliant',
                  trailing: _GreenBadge('Enabled'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsRow(
                  icon: Icons.storage_outlined,
                  label: 'Data Retention',
                  trailing: Text('—', style: AppText.caption11),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsRow(
                  icon: Icons.mic_outlined,
                  label: 'Call Recordings',
                  trailing: Text(
                    '90 days',
                    style: AppText.body13.copyWith(color: AppColors.schooner),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── About ─────────────────────────────────────────────────────
            _SettingsSection(
              title: 'ABOUT',
              children: [
                _SettingsRow(
                  icon: Icons.info_outline,
                  label: 'App Version',
                  trailing: Text(
                    '2.6.1 (build 4421)',
                    style: AppText.mono(size: 11, color: AppColors.tide),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsRow(
                  icon: Icons.lock_outline,
                  label: 'Privacy Policy',
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsRow(
                  icon: Icons.article_outlined,
                  label: 'Terms of Service',
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsRow(
                  icon: Icons.logout,
                  label: 'Log out',
                  iconColor: AppColors.alizarin,
                  labelColor: AppColors.alizarin,
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User card ────────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.westar),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.blueRibbon,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                'RV',
                style: AppText.display16.copyWith(
                  color: AppColors.white,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ravi Verma', style: AppText.display16),
                Text(
                  'Senior Telecaller',
                  style: AppText.body13.copyWith(color: AppColors.schooner),
                ),
                Text(
                  'Skyline Developers',
                  style: AppText.caption11.copyWith(color: AppColors.tide),
                ),
              ],
            ),
          ),
          LpIconButton(icon: Icons.edit_outlined, onTap: () {}),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.label11),
          const SizedBox(height: AppSpacing.xs),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.westar),
              boxShadow: AppShadows.card,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.iconColor = AppColors.schooner,
    this.labelColor = AppColors.zeus,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppText.body14.copyWith(color: labelColor),
              ),
            ),
            ?trailing,
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 16, color: AppColors.tide),
          ],
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  static const _scripts = ['తె', 'हि', 'N', 'த', 'ಕ'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.language_outlined, size: 18, color: AppColors.schooner),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text('Language', style: AppText.body14.copyWith(color: AppColors.zeus)),
          ),
          for (var i = 0; i < _scripts.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: i == 0 ? AppColors.ribbonSurface : AppColors.pampas,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: i == 0 ? AppColors.blueRibbon : AppColors.westar,
                    width: i == 0 ? 1.5 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    _scripts[i],
                    style: AppText.body13.copyWith(
                      fontSize: 12,
                      color: i == 0 ? AppColors.blueRibbon : AppColors.merlin,
                      fontWeight:
                          i == 0 ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GreenBadge extends StatelessWidget {
  const _GreenBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.foam,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.iceCold),
      ),
      child: Text(
        label,
        style: AppText.caption11.copyWith(
          color: AppColors.salem,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
}
