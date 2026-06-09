import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LeadPilot',
                          style: AppText.display20.copyWith(fontSize: 26),
                        ),
                        Text(
                          'Outbound queue',
                          style: AppText.body13.copyWith(
                            color: AppColors.schooner,
                          ),
                        ),
                      ],
                    ),
                  ),
                  LpIconButton(
                    icon: Icons.add,
                    onTap: () => context.push('/outbound/add'),
                    background: AppColors.blueRibbon,
                    foreground: AppColors.white,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Row(
                    children: const [
                      Expanded(
                        child: MetricTile(
                          label: 'Due Today',
                          value: '18',
                          mono: true,
                        ),
                      ),
                      AppGap.xs(axis: Axis.horizontal),
                      Expanded(
                        child: MetricTile(
                          label: 'Hot Leads',
                          value: '6',
                          valueColor: AppColors.alizarin,
                          mono: true,
                        ),
                      ),
                      AppGap.xs(axis: Axis.horizontal),
                      Expanded(
                        child: MetricTile(
                          label: 'Avg Score',
                          value: '78',
                          valueColor: AppColors.salem,
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  const AppGap.md(),
                  SectionPanel(
                    title: 'Priority Leads',
                    icon: Icons.local_fire_department_outlined,
                    titleColor: AppColors.tahitiGold,
                    color: AppColors.warningSurface,
                    borderColor: AppColors.warningBorder,
                    child: Column(
                      children: [
                        for (final lead in leads) _LeadQueueTile(lead: lead),
                      ],
                    ),
                  ),
                  const AppGap.md(),
                  SectionPanel(
                    title: 'Inbound Call Flow',
                    icon: Icons.call_received,
                    titleColor: AppColors.electricViolet,
                    color: AppColors.violetSurface,
                    borderColor: AppColors.violetBorder,
                    child: Text(
                      'Incoming calls open the same lead memory, transcript cues, and post-call checklist. The shell keeps this as a navigable placeholder until telephony integration is added.',
                      style: AppText.body14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: AppColors.blueRibbon,
        unselectedItemColor: AppColors.schooner,
        backgroundColor: AppColors.white,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.view_list_outlined),
            label: 'Queue',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.call_outlined),
            label: 'Calls',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights_outlined),
            label: 'Insights',
          ),
        ],
      ),
    );
  }
}

class _LeadQueueTile extends ConsumerWidget {
  const _LeadQueueTile({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TapScale(
      onTap: () {
        ref.read(selectedLeadIdProvider.notifier).set(lead.id);
        context.push('/leads/${lead.id}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ScoreRing(score: lead.score, size: 52),
            const AppGap.sm(axis: Axis.horizontal),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lead.name,
                    style: AppText.body14.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(lead.phone, style: AppText.mono(size: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.schooner),
          ],
        ),
      ),
    );
  }
}
