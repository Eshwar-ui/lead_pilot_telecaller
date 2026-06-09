import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing, AppRadius;

import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class PostCallScreen extends ConsumerWidget {
  const PostCallScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (l) => l.id == leadId,
      orElse: () => leads.first,
    );

    return LpScreen(
      title: 'Post-Call',
      subtitle: lead.name,
      bottom: BottomActionBar(
        children: [
          SecondaryButton(
            label: '',
            icon: Icons.arrow_back,
            onTap: () => context.go('/leads/$leadId'),
          ),
          const AppGap.xs(axis: Axis.horizontal),
          Expanded(
            child: PrimaryButton(
              label: 'Schedule Follow-up',
              icon: Icons.calendar_today_outlined,
              onTap: () => context.go('/leads/$leadId'),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _ScoreCard(lead: lead),
          const AppGap.md(),
          _SummaryPanel(lead: lead),
          const AppGap.md(),
          _SentimentBar(lead: lead),
          const AppGap.md(),
          _ObjectionsPanel(lead: lead),
          const AppGap.md(),
          _NextStepsPanel(lead: lead),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          ScoreRing(score: lead.score, size: 80),
          const AppGap.md(axis: Axis.horizontal),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Call Score', style: AppText.label11),
                const AppGap.xxs(),
                Text(
                  _scoreLabel(lead.score),
                  style: AppText.display16.copyWith(
                    color: _scoreColor(lead.score),
                  ),
                ),
                const AppGap.xs(),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: const [
                    _ScorePill('Rapport', 88),
                    _ScorePill('Clarity', 82),
                    _ScorePill('Objections', 76),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scoreLabel(int s) {
    if (s >= 80) return 'Strong Call';
    if (s >= 60) return 'Average Call';
    return 'Needs Work';
  }

  Color _scoreColor(int s) {
    if (s >= 80) return AppColors.salem;
    if (s >= 60) return AppColors.tahitiGold;
    return AppColors.alizarin;
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: AppColors.westar),
      ),
      child: Text(
        '$label $value',
        style: AppText.caption11.copyWith(
          color: AppColors.merlin,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.lead});

  final Lead lead;

  static const _bullets = [
    'Lead confirmed interest in Phase 2 3BHK',
    'Budget range confirmed within target',
    'Completion timeline concern addressed with Phase 1 data',
    'Site visit tentatively agreed for Saturday',
  ];

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: 'AI Summary',
      icon: Icons.summarize_outlined,
      titleColor: AppColors.electricViolet,
      color: AppColors.violetSurface,
      borderColor: AppColors.violetBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final bullet in _bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: const BoxDecoration(
                      color: AppColors.electricViolet,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const AppGap(10, axis: Axis.horizontal),
                  Expanded(
                    child: Text(bullet, style: AppText.body13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SentimentBar extends StatelessWidget {
  const _SentimentBar({required this.lead});

  final Lead lead;

  // (color, flex weight)
  static const _segments = [
    (AppColors.tide, 2),
    (AppColors.salem, 5),
    (AppColors.tahitiGold, 2),
    (AppColors.salem, 3),
  ];

  @override
  Widget build(BuildContext context) {
    return LpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SENTIMENT TIMELINE', style: AppText.label11),
          const AppGap.sm(),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Row(
              children: [
                for (final seg in _segments)
                  Expanded(
                    flex: seg.$2,
                    child: Container(height: 10, color: seg.$1),
                  ),
              ],
            ),
          ),
          const AppGap.xs(),
          Row(
            children: [
              _Legend('Positive', AppColors.salem),
              const SizedBox(width: 12),
              _Legend('Neutral', AppColors.tide),
              const SizedBox(width: 12),
              _Legend('Concerned', AppColors.tahitiGold),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppText.caption11.copyWith(color: AppColors.schooner),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ObjectionsPanel extends StatelessWidget {
  const _ObjectionsPanel({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: 'Objections Handled',
      icon: Icons.shield_outlined,
      titleColor: AppColors.tahitiGold,
      color: AppColors.warningSurface,
      borderColor: AppColors.warningBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final obj in lead.objections)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 14,
                    color: AppColors.salem,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      obj.question,
                      style: AppText.body13.copyWith(
                        color: AppColors.warningDark,
                        fontWeight: FontWeight.w600,
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

// ─────────────────────────────────────────────────────────────────────────────

class _NextStepsPanel extends StatelessWidget {
  const _NextStepsPanel({required this.lead});

  final Lead lead;

  static const _steps = [
    (Icons.chat_outlined, 'Send EMI sheet on WhatsApp'),
    (Icons.calendar_today_outlined, 'Confirm Saturday site visit'),
    (Icons.description_outlined, 'Share RERA timeline document'),
  ];

  @override
  Widget build(BuildContext context) {
    return LpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_outlined,
                size: 14,
                color: AppColors.blueRibbon,
              ),
              const AppGap(6, axis: Axis.horizontal),
              Text(
                'NEXT STEPS',
                style: AppText.label11.copyWith(color: AppColors.blueRibbon),
              ),
            ],
          ),
          const AppGap.xs(),
          for (final step in _steps)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.ribbonSurface,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Icon(
                      step.$1,
                      size: 14,
                      color: AppColors.blueRibbon,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(step.$2, style: AppText.body13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
