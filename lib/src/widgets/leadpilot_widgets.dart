import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppRadius, AppSpacing;

import '../models/lead.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

class LpScreen extends StatelessWidget {
  const LpScreen({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
    this.bottom,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;
  final Widget? bottom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          children: [
            LpTopBar(
              title: title,
              subtitle: subtitle,
              trailing: trailing,
              onBack: onBack,
            ),
            Expanded(child: child),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

class LpTopBar extends StatelessWidget {
  const LpTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 75,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.westar)),
      ),
      child: Row(
        children: [
          LpIconButton(
            icon: Icons.arrow_back,
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const AppGap(10, axis: Axis.horizontal),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.display16,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle case final subtitle?)
                  Text(
                    subtitle,
                    style: AppText.caption11.copyWith(
                      color: AppColors.schooner,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Shared header for the four bottom-tab screens (Inbox, Calls, Follow-ups,
/// Profile) so they all share one consistent "app bar". A white bar with a
/// bottom border, a big title, an optional subtitle, and trailing actions.
class LpTabHeader extends StatelessWidget {
  const LpTabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.westar)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.display24.copyWith(fontSize: 24)),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 2),
                  subtitleWidget!,
                ] else if (subtitle case final s?) ...[
                  const SizedBox(height: 2),
                  Text(
                    s,
                    style: AppText.body13.copyWith(color: AppColors.schooner),
                  ),
                ],
              ],
            ),
          ),
          for (final action in actions) ...[
            const SizedBox(width: 10),
            action,
          ],
        ],
      ),
    );
  }
}

class LpIconButton extends StatelessWidget {
  const LpIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.background = AppColors.pampas,
    this.foreground = AppColors.merlin,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: MinTouchTarget(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(size / 2),
            border: Border.all(color: AppColors.westar),
          ),
          child: Icon(icon, size: size * 0.45, color: foreground),
        ),
      ),
    );
  }
}

class LpCard extends StatelessWidget {
  const LpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.color = AppColors.white,
    this.borderColor = AppColors.westar,
    this.radius = AppRadius.lg,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}

class LpPill extends StatelessWidget {
  const LpPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: foreground),
            const AppGap(4, axis: Axis.horizontal),
          ],
          Text(
            label.toUpperCase(),
            style: AppText.label11.copyWith(
              color: foreground,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class LpMiniPill extends StatelessWidget {
  const LpMiniPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon!, size: 10, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: AppText.label11.copyWith(
              color: foreground,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class LeadSummaryCard extends StatelessWidget {
  const LeadSummaryCard({super.key, required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      padding: const EdgeInsets.all(19),
      child: Row(
        children: [
          ScoreRing(score: lead.score),
          const AppGap.md(axis: Axis.horizontal),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lead.name, style: AppText.display20),
                const AppGap.xxs(),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_outlined,
                      size: 12,
                      color: AppColors.schooner,
                    ),
                    const AppGap(6, axis: Axis.horizontal),
                    Text(lead.phone, style: AppText.mono(size: 13)),
                  ],
                ),
                const AppGap.xs(),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    LpPill(
                      label: lead.source.displayName,
                      foreground: AppColors.governorBay,
                      background: AppColors.zircon,
                      border: AppColors.periwinkle,
                    ),
                    LpPill(
                      label: lead.intent,
                      icon: Icons.bolt,
                      foreground: AppColors.greenHaze,
                      background: AppColors.foam,
                      border: AppColors.iceCold,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, this.size = 80});

  final int score;
  final double size;

  Color get _ringColor {
    if (score >= 80) return AppColors.salem;
    if (score >= 60) return AppColors.tahitiGold;
    return AppColors.alizarin;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = score <= 0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScoreRingPainter(
          isNew ? 0.0 : score / 100,
          isNew ? AppColors.tide : _ringColor,
        ),
        child: Center(
          child: Text(
            isNew ? 'New' : '$score',
            style: AppText.mono(
              size: isNew ? size * 0.22 : size * 0.28,
              weight: FontWeight.w700,
              color: isNew ? AppColors.tide : AppColors.zeus,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  _ScoreRingPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.07;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.pampas;
    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2,
      false,
      base,
    );
    canvas.drawArc(
      rect.deflate(stroke),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor = AppColors.zeus,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.label11.copyWith(fontSize: 10),
          ),
          const AppGap.xxs(),
          Text(
            value,
            style: mono
                ? AppText.mono(
                    size: 18,
                    weight: FontWeight.w700,
                    color: valueColor,
                  )
                : AppText.body13.copyWith(
                    fontWeight: FontWeight.w700,
                    color: valueColor,
                  ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class SectionPanel extends StatelessWidget {
  const SectionPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.color = AppColors.white,
    this.borderColor = AppColors.westar,
    this.titleColor = AppColors.schooner,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color color;
  final Color borderColor;
  final Color titleColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      color: color,
      borderColor: borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: titleColor),
              const AppGap(6, axis: Axis.horizontal),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: AppText.label11.copyWith(color: titleColor),
                ),
              ),
              ?trailing,
            ],
          ),
          const AppGap.xs(),
          child,
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.color = AppColors.blueRibbon,
    this.expanded = true,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final bool expanded;

  /// Shows a spinner in place of the label/icon and disables taps — for an
  /// in-flight submit, so the button itself communicates "working" instead of
  /// relying on the caller to swap in different label text.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final button = TapScale(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: (onTap == null && !loading)
              ? null
              : (color == AppColors.blueRibbon
                  ? AppShadows.blueAction
                  : AppShadows.card),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.white),
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: AppColors.white),
                    const AppGap.xs(axis: Axis.horizontal),
                  ],
                  if (label.isNotEmpty)
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body14.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.westar),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppColors.merlin),
              if (label.isNotEmpty) const AppGap.xs(axis: Axis.horizontal),
            ],
            if (label.isNotEmpty)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body14.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.children, this.caption});

  final List<Widget> children;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.westar)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: children),
          if (caption != null) ...[
            const AppGap.xs(),
            Text(
              caption!,
              style: AppText.caption11,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class FormShell extends StatelessWidget {
  const FormShell({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.optionalText,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? optionalText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: AppText.body14.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.merlin,
            ),
            children: [
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: AppColors.alizarin),
                ),
              if (optionalText != null)
                TextSpan(
                  text: ' $optionalText',
                  style: AppText.body14.copyWith(color: AppColors.schooner),
                ),
            ],
          ),
        ),
        const AppGap(6),
        child,
      ],
    );
  }
}

class LpTextField extends StatelessWidget {
  const LpTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.focused = false,
    this.maxLines = 1,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool focused;
  final int maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;

  /// False while a submit using this field's value is in flight, so the user
  /// can't edit (or double-submit) mid-request.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      enabled: enabled,
      maxLines: obscureText ? 1 : maxLines,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: AppText.body14.copyWith(fontSize: 15, color: AppColors.zeus),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: !enabled
            ? AppColors.pampas
            : (focused ? AppColors.white : AppColors.pampas),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 15,
          vertical: maxLines == 1 ? 15 : 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: focused ? AppColors.tahitiGold : AppColors.westar,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.westar),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.tahitiGold),
        ),
      ),
    );
  }
}

/// Full-page error state with an optional retry action — for a fetch that
/// has no sensible fallback (e.g. a specific call/lead that failed to load).
/// Not for list screens that fall back to mock data on failure; use
/// [LpFallbackBanner] there instead so a "fail soft" screen doesn't also look
/// broken.
class LpErrorState extends StatelessWidget {
  const LpErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.alizarin, size: 32),
            const AppGap.sm(),
            Text(
              message,
              style: AppText.body14.copyWith(color: AppColors.schooner),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const AppGap.sm(),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact banner for screens that deliberately fall back to cached/mock
/// data rather than blocking on a failed fetch — tells the telecaller what
/// they're looking at isn't necessarily live, with a one-tap retry. Meant to
/// sit above the (still-visible) fallback content, not replace it.
class LpFallbackBanner extends StatelessWidget {
  const LpFallbackBanner({super.key, required this.onRetry, this.message = 'Showing cached data'});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      color: AppColors.warningSurface,
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 14, color: AppColors.warningText),
          const AppGap.xs(axis: Axis.horizontal),
          Expanded(
            child: Text(
              message,
              style: AppText.caption11.copyWith(color: AppColors.warningText),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Retry',
              style: AppText.caption11.copyWith(
                color: AppColors.warningText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
