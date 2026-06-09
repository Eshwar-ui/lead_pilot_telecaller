import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';
import 'lead_detail_screen.dart';

class PreCallScreen extends ConsumerWidget {
  const PreCallScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.first,
    );

    return LpScreen(
      title: 'Pre-Call',
      subtitle: lead.name,
      bottom: BottomActionBar(
        caption: 'Call will be recorded with IVR consent in Telugu',
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Start Call',
              icon: Icons.phone_outlined,
              onTap: () => context.push('/caller-selector/${lead.id}'),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          LeadSummaryCard(lead: lead),
          const AppGap.md(),
          MemoryPanel(lead: lead, compact: true),
          const AppGap.md(),
          _OpeningScriptPanel(leadId: lead.id),
          const AppGap.md(),
          _StepsPanel(leadId: lead.id),
          const AppGap.md(),
          _ObjectionPanel(leadId: lead.id),
          const AppGap.md(),
          _ChecklistPanel(leadId: lead.id),
        ],
      ),
    );
  }
}

class _OpeningScriptPanel extends ConsumerWidget {
  const _OpeningScriptPanel({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.first,
    );
    return SectionPanel(
      title: 'AI Script',
      icon: Icons.edit_outlined,
      titleColor: AppColors.electricViolet,
      color: AppColors.violetSurface,
      borderColor: AppColors.violetBorder,
      trailing: Text(lead.script.generatedAgo, style: AppText.caption11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LpCard(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OPENING LINE', style: AppText.label11),
                const AppGap.xs(),
                Text(lead.script.openingLine, style: AppText.body14),
              ],
            ),
          ),
          const AppGap.sm(),
          Text('KEY POINTS', style: AppText.label11),
          const AppGap.xs(),
          for (var i = 0; i < lead.script.keyPoints.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: AppText.body13.copyWith(color: AppColors.schooner),
                  ),
                  Expanded(child: Text(lead.script.keyPoints[i], style: AppText.body13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepsPanel extends ConsumerWidget {
  const _StepsPanel({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.first,
    );
    return SectionPanel(
      title: 'AI Generated Script',
      icon: Icons.auto_awesome,
      titleColor: AppColors.electricViolet,
      child: Column(
        children: [
          for (var i = 0; i < lead.script.steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == lead.script.steps.length - 1 ? 0 : 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.ribbonSurface,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${i + 1}'.padLeft(2, '0'),
                      style: AppText.body13.copyWith(
                        color: AppColors.blueRibbon,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const AppGap.sm(axis: Axis.horizontal),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.script.steps[i].title,
                          style: AppText.body14.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          lead.script.steps[i].subtitle,
                          style: AppText.caption11,
                        ),
                      ],
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

class _ObjectionPanel extends ConsumerWidget {
  const _ObjectionPanel({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.first,
    );
    return SectionPanel(
      title: 'Likely Objections',
      icon: Icons.lightbulb_outline,
      titleColor: AppColors.tahitiGold,
      color: AppColors.warningSurface,
      borderColor: AppColors.warningBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final objection in lead.objections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    objection.question,
                    style: AppText.body13.copyWith(
                      color: AppColors.warningDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    objection.response,
                    style: AppText.body13.copyWith(
                      color: AppColors.warningDark,
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

class _ChecklistPanel extends ConsumerWidget {
  const _ChecklistPanel({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.first,
    );
    final completed = ref.watch(checklistProvider)[lead.id] ?? <String>{};

    return LpCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('CHECKLIST', style: AppText.label11)),
              Text(
                '${completed.length} / ${lead.checklist.length}',
                style: AppText.caption11,
              ),
            ],
          ),
          const AppGap.xs(),
          for (final item in lead.checklist)
            TapScale(
              onTap: () =>
                  ref.read(checklistProvider.notifier).toggle(lead.id, item.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: completed.contains(item.id)
                            ? AppColors.blueRibbon
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: completed.contains(item.id)
                              ? AppColors.blueRibbon
                              : AppColors.westar,
                        ),
                      ),
                      child: completed.contains(item.id)
                          ? const Icon(
                              Icons.check,
                              color: AppColors.white,
                              size: 12,
                            )
                          : null,
                    ),
                    const AppGap(10, axis: Axis.horizontal),
                    Expanded(
                      child: Text(
                        item.text,
                        style: AppText.body13.copyWith(
                          decoration: completed.contains(item.id)
                              ? TextDecoration.lineThrough
                              : null,
                          color: completed.contains(item.id)
                              ? AppColors.schooner
                              : AppColors.merlin,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.pampas,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.add, size: 14, color: AppColors.schooner),
                const AppGap.xs(axis: Axis.horizontal),
                Text(
                  'Add item...',
                  style: AppText.body13.copyWith(
                    color: AppColors.schooner,
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
