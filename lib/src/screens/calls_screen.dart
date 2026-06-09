import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class CallsScreen extends ConsumerWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callLog = ref.watch(callLogProvider);

    // Group by date section label
    final today = <CallLogEntry>[];
    final yesterday = <CallLogEntry>[];
    final older = <CallLogEntry>[];
    final n = DateTime.now();
    final now = DateTime(n.year, n.month, n.day);

    for (final entry in callLog) {
      final days = now
          .difference(DateTime(entry.calledAt.year, entry.calledAt.month, entry.calledAt.day))
          .inDays;
      if (days == 0) {
        today.add(entry);
      } else if (days == 1) {
        yesterday.add(entry);
      } else {
        older.add(entry);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Calls', style: AppText.display20.copyWith(fontSize: 22)),
                        Text(
                          'This week',
                          style: AppText.body13.copyWith(color: AppColors.schooner),
                        ),
                      ],
                    ),
                  ),
                  LpIconButton(icon: Icons.search, onTap: () {}),
                ],
              ),
            ),

            // ── Stats ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  Expanded(
                    child: MetricTile(label: 'This Month', value: '142', mono: true),
                  ),
                  SizedBox(width: 6),
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
                    child: MetricTile(label: 'Avg Duration', value: '4:12', mono: true),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Call list ─────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                children: [
                  if (today.isNotEmpty) ...[
                    _SectionLabel(label: 'TODAY'),
                    for (final e in today) _CallTile(entry: e),
                  ],
                  if (yesterday.isNotEmpty) ...[
                    _SectionLabel(label: 'YESTERDAY'),
                    for (final e in yesterday) _CallTile(entry: e),
                  ],
                  if (older.isNotEmpty) ...[
                    _SectionLabel(label: 'EARLIER'),
                    for (final e in older) _CallTile(entry: e),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(label, style: AppText.label11),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.entry});

  final CallLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final dur = _fmtDuration(entry.duration);
    final time = DateFormat('h:mm a').format(entry.calledAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.westar),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Direction indicator
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.isInbound ? AppColors.violetSurface : AppColors.foam,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              entry.isInbound ? Icons.call_received_outlined : Icons.call_made_outlined,
              size: 16,
              color: entry.isInbound ? AppColors.electricViolet : AppColors.greenHaze,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.leadName,
                        style: AppText.body14.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(time, style: AppText.caption11),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(entry.phone, style: AppText.mono(size: 11)),
                    const Spacer(),
                    Text(dur, style: AppText.mono(size: 11, color: AppColors.schooner)),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    LpMiniPill(
                      label: entry.source.displayName,
                      foreground: AppColors.governorBay,
                      background: AppColors.zircon,
                      border: AppColors.periwinkle,
                    ),
                    const SizedBox(width: 4),
                    LpMiniPill(
                      label: entry.intent,
                      foreground: AppColors.greenHaze,
                      background: AppColors.foam,
                      border: AppColors.iceCold,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.xs),
          ScoreRing(score: entry.score, size: 38),
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

}
