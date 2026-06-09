import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../models/lead.dart';
import '../services/call_actions.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class LeadDetailScreen extends ConsumerWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.first,
    );

    return LpScreen(
      title: 'Lead Detail',
      trailing: LpPill(
        label: lead.temperature.name,
        foreground: switch (lead.temperature) {
          LeadTemperature.hot => AppColors.alizarin,
          LeadTemperature.warm => AppColors.tahitiGold,
          LeadTemperature.cold => AppColors.schooner,
        },
        background: switch (lead.temperature) {
          LeadTemperature.hot => AppColors.redSurface,
          LeadTemperature.warm => AppColors.warningSurface,
          LeadTemperature.cold => AppColors.pampas,
        },
        border: switch (lead.temperature) {
          LeadTemperature.hot => AppColors.redBorder,
          LeadTemperature.warm => AppColors.warningBorder,
          LeadTemperature.cold => AppColors.westar,
        },
      ),
      bottom: BottomActionBar(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Start Call',
              icon: Icons.phone_outlined,
              onTap: () => context.push('/leads/${lead.id}/pre-call'),
            ),
          ),
          const AppGap.xs(axis: Axis.horizontal),
          SecondaryButton(
            label: '',
            icon: Icons.sms_outlined,
            onTap: () => launchSms(lead.phone),
          ),
          const AppGap.xs(axis: Axis.horizontal),
          SecondaryButton(
            label: '',
            icon: Icons.calendar_today_outlined,
            onTap: () {},
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          LeadSummaryCard(lead: lead),
          const AppGap.md(),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Total Calls',
                  value: '${lead.totalCalls}',
                  mono: true,
                ),
              ),
              const AppGap.xs(axis: Axis.horizontal),
              Expanded(
                child: MetricTile(
                  label: 'Avg Score',
                  value: '${lead.averageScore}',
                  valueColor: AppColors.salem,
                  mono: true,
                ),
              ),
              const AppGap.xs(axis: Axis.horizontal),
              Expanded(
                child: MetricTile(
                  label: 'Last Contact',
                  value: _relativeDay(lead.lastContact),
                ),
              ),
            ],
          ),
          const AppGap.md(),
          MemoryPanel(lead: lead),
          const AppGap.md(),
          CallHistoryPanel(history: lead.history),
        ],
      ),
    );
  }

  String _relativeDay(DateTime date) {
    final n = DateTime.now();
    final now = DateTime(n.year, n.month, n.day);
    final days = now
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }
}

class MemoryPanel extends StatelessWidget {
  const MemoryPanel({super.key, required this.lead, this.compact = false});

  final Lead lead;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SectionPanel(
      title: 'Memory Bubble',
      icon: Icons.graphic_eq,
      titleColor: AppColors.electricViolet,
      color: AppColors.violetSurface,
      borderColor: AppColors.violetBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.ribbonSurface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Last called 4 days ago - Score 68',
                style: AppText.body13.copyWith(
                  color: AppColors.blueRibbon,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const AppGap.sm(),
          ],
          for (final item in compact ? lead.memory.take(3) : lead.memory)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: compact ? 8 : 7,
                    height: compact ? 8 : 7,
                    margin: const EdgeInsets.only(top: 7),
                    decoration: BoxDecoration(
                      color: _memoryColor(item.colorKey),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const AppGap(10, axis: Axis.horizontal),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.text, style: AppText.body14),
                        if (!compact)
                          Text(
                            item.callLabel,
                            style: AppText.caption11.copyWith(
                              color: AppColors.tide,
                            ),
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

  Color _memoryColor(String key) {
    return switch (key) {
      'green' => AppColors.salem,
      'orange' => AppColors.tahitiGold,
      _ => AppColors.electricViolet,
    };
  }
}

class CallHistoryPanel extends StatelessWidget {
  const CallHistoryPanel({super.key, required this.history});

  final List<CallRecord> history;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('00');
    return LpCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'CALL HISTORY (${history.length})',
                    style: AppText.label11,
                  ),
                ),
                const Icon(
                  Icons.expand_more,
                  size: 16,
                  color: AppColors.schooner,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (var i = 0; i < history.length; i++)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              history[i].title,
                              style: AppText.body14.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${formatter.format(history[i].duration.inMinutes)}:${formatter.format(history[i].duration.inSeconds.remainder(60))}',
                              style: AppText.mono(size: 11.5),
                            ),
                          ],
                        ),
                      ),
                      LpPill(
                        label: '${history[i].score} pts',
                        foreground: AppColors.salem,
                        background: AppColors.white,
                        border: AppColors.iceCold,
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.tide,
                      ),
                    ],
                  ),
                ),
                if (i < history.length - 1) const Divider(height: 1),
              ],
            ),
        ],
      ),
    );
  }
}
