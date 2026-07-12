import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../core/api/api_exception.dart';
import '../models/lead.dart';
import '../services/call_actions.dart';
import '../services/local_call_store.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_closed_sheet.dart';
import '../widgets/edit_lead_sheet.dart';
import '../widgets/leadpilot_widgets.dart';
import '../widgets/schedule_call_sheet.dart';
import '../widgets/upload_recording_sheet.dart';
import 'call_detail_screen.dart';

class LeadDetailScreen extends ConsumerStatefulWidget {
  const LeadDetailScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<LeadDetailScreen> createState() => _LeadDetailScreenState();
}

class _LeadDetailScreenState extends ConsumerState<LeadDetailScreen> {
  @override
  void initState() {
    super.initState();
    // The lead can arrive here as a *thin* inbox card (no memory bubble, call
    // history, script or objections) — enrichment is otherwise only fired
    // fire-and-forget from the Home tile tap, so reaching this screen any other
    // way (post-call, follow-ups, call log, a deep link) would show empty
    // panels. Fetch the full detail as soon as the screen opens; enrich() is
    // idempotent and fail-soft, so a duplicate call from the Home tap is fine.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(leadsProvider.notifier).enrich(widget.leadId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final leadId = widget.leadId;
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.isEmpty ? Lead.empty() : leads.first,
    );

    // Merge any locally-recorded calls for this lead into the backend history.
    final localCalls = ref.watch(localCallsProvider);
    final mergedHistory = _mergeHistory(lead, localCalls);

    return LpScreen(
      title: 'Lead Detail',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LpPill(
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
          const AppGap.xs(axis: Axis.horizontal),
          LpIconButton(
            icon: Icons.edit_outlined,
            onTap: () => EditLeadSheet.show(context, lead),
          ),
        ],
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
            onTap: () => ScheduleCallSheet.show(context, lead),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          LeadSummaryCard(lead: lead),
          const AppGap.md(),
          _PipelineStrip(leadId: lead.id),
          const AppGap.md(),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Total Calls',
                  value: '${mergedHistory.length > lead.totalCalls ? mergedHistory.length : lead.totalCalls}',
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
          CallHistoryPanel(
            leadId: lead.id,
            leadName: lead.name,
            history: mergedHistory,
            onUploadRecording: () =>
                UploadRecordingSheet.show(context, lead),
          ),
        ],
      ),
    );
  }

  /// Backend call history plus locally-recorded calls for this lead, newest
  /// first, with same-minute duplicates collapsed.
  List<CallRecord> _mergeHistory(Lead lead, List<CallLogEntry> localCalls) {
    final merged = [...lead.history];
    for (final c in localCalls) {
      if (c.leadId != lead.id) continue;
      final dup = merged.any((h) =>
          h.calledAt != null &&
          h.calledAt!.difference(c.calledAt).inMinutes.abs() < 1);
      if (dup) continue;
      merged.add(CallRecord(
        title:
            '${c.calledAt.day.toString().padLeft(2, '0')}/${c.calledAt.month.toString().padLeft(2, '0')} · placed',
        duration: c.duration,
        score: c.score,
        calledAt: c.calledAt,
        leadId: lead.id,
      ));
    }
    merged.sort((a, b) =>
        (b.calledAt ?? DateTime(0)).compareTo(a.calledAt ?? DateTime(0)));
    return merged;
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

// ─── Lead pipeline strip ─────────────────────────────────────────────────────

class _PipelineStrip extends ConsumerWidget {
  const _PipelineStrip({required this.leadId});

  final String leadId;

  static const _stages = LeadStage.values;

  Future<void> _selectStage(BuildContext context, WidgetRef ref, LeadStage stage) async {
    final notifier = ref.read(leadStageProvider.notifier);
    if (stage == LeadStage.closedWon) {
      final deal = await showDealClosedSheet(context);
      if (deal == null) return; // user dismissed without confirming
      await notifier.setStage(
        leadId,
        stage,
        dealValue: deal.dealValue,
        listPrice: deal.listPrice,
        discountPct: deal.discountPct,
      );
      return;
    }
    await notifier.setStage(leadId, stage);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = ref.watch(leadStageProvider.select((m) => m[leadId] ?? LeadStage.newLead));

    return LpCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PIPELINE STAGE', style: AppText.label11),
          const AppGap.sm(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _stages.length; i++) ...[
                  SizedBox(
                    width: 60,
                    child: _StageChip(
                      label: _stages[i].label,
                      isActive: _stages[i] == stage,
                      isDead: _stages[i].isTerminalNegative,
                      onTap: () => _selectStage(context, ref, _stages[i]),
                    ),
                  ),
                  if (i < _stages.length - 1)
                    Container(
                      width: 10,
                      height: 1.5,
                      color: stage.index > i ? AppColors.blueRibbon : AppColors.westar,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageChip extends StatelessWidget {
  const _StageChip({
    required this.label,
    required this.isActive,
    required this.isDead,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool isDead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = isDead ? AppColors.alizarin : AppColors.blueRibbon;
    final activeSurface = isDead ? AppColors.redSurface : AppColors.ribbonSurface;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? activeColor : AppColors.white,
              border: Border.all(
                color: isActive ? activeColor : AppColors.westar,
                width: 1.5,
              ),
            ),
            child: isActive
                ? Icon(Icons.check, size: 11, color: AppColors.white)
                : null,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: isActive ? activeSurface : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: AppText.label11.copyWith(
                fontSize: 9,
                color: isActive ? activeColor : AppColors.schooner,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class MemoryPanel extends ConsumerStatefulWidget {
  const MemoryPanel({super.key, required this.lead, this.compact = false});

  final Lead lead;
  final bool compact;

  @override
  ConsumerState<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends ConsumerState<MemoryPanel> {
  bool _rebuilding = false;

  /// Recompute the bubble from all of this contact's calls, then re-enrich so
  /// the refreshed facts/verdict show without leaving the screen.
  Future<void> _rebuild() async {
    if (_rebuilding) return;
    setState(() => _rebuilding = true);
    try {
      await ref.read(leadsProvider.notifier).rebuildMemory(widget.lead.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory rebuilt')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 = this contact has no analysed calls yet, so retrying won't help;
      // say so plainly instead of a generic error.
      final msg = e.isNotFound
          ? 'No analysed calls yet — nothing to rebuild.'
          : 'Couldn’t rebuild memory. Try again.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t rebuild memory. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final compact = widget.compact;
    return SectionPanel(
      title: 'Memory Bubble',
      icon: Icons.graphic_eq,
      titleColor: AppColors.electricViolet,
      color: AppColors.violetSurface,
      borderColor: AppColors.violetBorder,
      // Rebuild is a full-detail action only — the compact (pre-call) view is
      // read-only glanceable context.
      trailing: compact
          ? null
          : (_rebuilding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.electricViolet,
                  ),
                )
              : IconButton(
                  onPressed: _rebuild,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Rebuild memory from all calls',
                  icon: const Icon(Icons.refresh,
                      size: 18, color: AppColors.electricViolet),
                )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact && lead.history.isNotEmpty) ...[
            Builder(builder: (_) {
              final last = lead.history.first;
              final when = last.calledAt;
              final ago = when == null
                  ? 'recently'
                  : _agoLabel(DateTime.now().difference(when));
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.ribbonSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  last.score > 0
                      ? 'Last called $ago · Score ${last.score}'
                      : 'Last called $ago',
                  style: AppText.body13.copyWith(
                    color: AppColors.blueRibbon,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }),
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

  String _agoLabel(Duration diff) {
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return '1 day ago';
    return '${diff.inDays} days ago';
  }
}

class CallHistoryPanel extends StatelessWidget {
  const CallHistoryPanel({
    super.key,
    required this.leadId,
    required this.leadName,
    required this.history,
    this.onUploadRecording,
  });

  final String leadId;
  final String leadName;
  final List<CallRecord> history;
  final VoidCallback? onUploadRecording;

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('00');
    return LpCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'CALL HISTORY (${history.length})',
                    style: AppText.label11,
                  ),
                ),
                if (onUploadRecording != null)
                  Tooltip(
                    message: 'Upload recording',
                    child: InkWell(
                      onTap: onUploadRecording,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.upload_file,
                                size: 15, color: AppColors.blueRibbon),
                            const SizedBox(width: 4),
                            Text('Upload',
                                style: AppText.caption11.copyWith(
                                  color: AppColors.blueRibbon,
                                  fontWeight: FontWeight.w700,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Text(
                'No calls yet. Make your first call to see history here.',
                style: AppText.caption11.copyWith(color: AppColors.schooner),
              ),
            ),
          for (var i = 0; i < history.length; i++)
            Column(
              children: [
                InkWell(
                  // A call with a stored call_id has its own transcript/
                  // analysis on the backend — open that specific call.
                  // Calls with no call_id yet (just placed, not captured/
                  // uploaded) fall back to the live-capture screen.
                  onTap: () => history[i].callId != null
                      ? context.push(
                          '/leads/$leadId/calls/${history[i].callId}',
                          extra: CallDetailArgs(
                            leadName: leadName,
                            calledAt: history[i].calledAt,
                          ),
                        )
                      : context.push('/leads/$leadId/post-call'),
                  child: Padding(
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
                                history[i].duration == Duration.zero
                                    ? '—'
                                    : '${formatter.format(history[i].duration.inMinutes)}:${formatter.format(history[i].duration.inSeconds.remainder(60))}',
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
                ),
                if (i < history.length - 1) const Divider(height: 1),
              ],
            ),
        ],
      ),
    );
  }
}

