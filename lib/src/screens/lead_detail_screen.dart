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
      // Normal in-app navigation can pop back to Home. A restored/deep-linked
      // detail route may have no history, so keep the back button functional by
      // explicitly returning to the lead list in that case.
      onBack: () => context.canPop() ? context.pop() : context.go('/home'),
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
          LeadSummaryCard(
            lead: lead,
            totalCalls: mergedHistory.length > lead.totalCalls
                ? mergedHistory.length
                : lead.totalCalls,
            lastContactLabel: _relativeDay(lead.lastContact),
          ),
          const AppGap.md(),
          _PipelineStrip(leadId: lead.id),
          const AppGap.md(),
          CallHistoryPanel(
            leadId: lead.id,
            leadName: lead.name,
            history: mergedHistory,
            onUploadRecording: () => UploadRecordingSheet.show(context, lead),
          ),
          const AppGap.md(),
          MemoryPanel(lead: lead),
          const AppGap.md(),
          _NextStepsPanel(
            lead: lead,
            onSchedule: () => ScheduleCallSheet.show(context, lead),
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
      final dup = merged.any(
        (h) =>
            h.calledAt != null &&
            h.calledAt!.difference(c.calledAt).inMinutes.abs() < 1,
      );
      if (dup) continue;
      merged.add(
        CallRecord(
          title:
              '${c.calledAt.day.toString().padLeft(2, '0')}/${c.calledAt.month.toString().padLeft(2, '0')} · placed',
          duration: c.duration,
          score: c.score,
          calledAt: c.calledAt,
          leadId: lead.id,
        ),
      );
    }
    merged.sort(
      (a, b) =>
          (b.calledAt ?? DateTime(0)).compareTo(a.calledAt ?? DateTime(0)),
    );
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

// ─── Lead pipeline (current-stage hero + tap-to-advance) ─────────────────────

class _PipelineStrip extends ConsumerStatefulWidget {
  const _PipelineStrip({required this.leadId});

  final String leadId;

  /// The linear selling progression, in order. Terminal outcomes (Closed Won as
  /// the win; Closed Lost / Junk as the negatives) are handled separately, not
  /// counted as numbered steps — so the counter reads "4 / 6", not "4 / 9".
  static const List<LeadStage> _working = [
    LeadStage.newLead,
    LeadStage.assigned,
    LeadStage.contacted,
    LeadStage.interested,
    LeadStage.proposalSent,
    LeadStage.negotiation,
  ];

  @override
  ConsumerState<_PipelineStrip> createState() => _PipelineStripState();
}

class _PipelineStripState extends ConsumerState<_PipelineStrip> {
  /// True while a stage change is being pushed to the backend — swaps the
  /// "advance" row for a spinner and disables the card, mirroring
  /// MemoryPanel's rebuild-spinner idiom elsewhere on this screen.
  bool _applying = false;

  int get _total => _PipelineStrip._working.length;

  Future<void> _applyStage(LeadStage stage, {String? note}) async {
    final notifier = ref.read(leadStageProvider.notifier);
    if (stage == LeadStage.closedWon) {
      final deal = await showDealClosedSheet(context);
      if (deal == null) return; // dismissed without confirming
      if (!mounted) return;
      setState(() => _applying = true);
      try {
        await notifier.setStage(
          widget.leadId,
          stage,
          dealValue: deal.dealValue,
          listPrice: deal.listPrice,
          discountPct: deal.discountPct,
          note: note,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Couldn’t save the stage move. Try again.'),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _applying = false);
      }
      return;
    }
    setState(() => _applying = true);
    try {
      await notifier.setStage(widget.leadId, stage, note: note);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Couldn’t save the stage move. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// Bottom sheet listing every stage this lead can move to: the remaining
  /// forward selling stages + Closed Won, the terminal negatives, and —
  /// separated below a divider — a "move back" section for reopening a lead
  /// or correcting a wrong stage. Picking a backward stage requires a note
  /// (collected in a second step of the same sheet) before it's applied.
  Future<void> _openPicker(LeadStage current) async {
    final options = computeStagePickerOptions(current, _PipelineStrip._working);
    final forward = options.forward;
    final backward = options.backward;
    final canLose = options.canCloseWithoutNote;

    final result = await showModalBottomSheet<_StagePickerResult>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StagePickerSheet(
        current: current,
        forward: forward,
        backward: backward,
        canLose: canLose,
      ),
    );

    if (result == null || !mounted) return;
    await _applyStage(result.stage, note: result.note);
  }

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(
      leadStageProvider.select((m) => m[widget.leadId] ?? LeadStage.newLead),
    );

    final isNegative = stage.isTerminalNegative;
    final isWon = stage == LeadStage.closedWon;

    final workingIndex = _PipelineStrip._working.indexOf(stage);
    final step = workingIndex >= 0 ? workingIndex + 1 : _total;
    final accent = isNegative
        ? AppColors.alizarin
        : isWon
        ? AppColors.salem
        : AppColors.blueRibbon;

    return LpCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        // Whole card is the tap target (well above the 44px minimum). Closed
        // leads can still reopen (via the "move back" section), so only an
        // in-flight change disables the card — never the closed state itself.
        onTap: _applying ? null : () => _openPicker(stage),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PIPELINE STAGE', style: AppText.label11),
              const AppGap.sm(),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const AppGap.xs(axis: Axis.horizontal),
                  Expanded(
                    child: Text(
                      stage.label,
                      style: AppText.body14.copyWith(
                        fontWeight: FontWeight.w700,
                        color: accent,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_applying)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (isWon)
                    const Icon(
                      Icons.emoji_events,
                      size: 16,
                      color: AppColors.salem,
                    )
                  else if (isNegative) ...[
                    Text(
                      'Closed',
                      style: AppText.caption11.copyWith(color: accent),
                    ),
                    const AppGap.xs(axis: Axis.horizontal),
                    Text(
                      'reopen',
                      style: AppText.caption11.copyWith(
                        color: AppColors.blueRibbon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppColors.blueRibbon,
                    ),
                  ] else ...[
                    Text(
                      '$step / $_total',
                      style: AppText.mono(
                        size: 12,
                      ).copyWith(color: AppColors.schooner),
                    ),
                    const AppGap.xs(axis: Axis.horizontal),
                    Text(
                      'advance',
                      style: AppText.caption11.copyWith(
                        color: AppColors.blueRibbon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppColors.blueRibbon,
                    ),
                  ],
                ],
              ),
              const AppGap.sm(),
              _ProgressSegments(
                total: _total,
                filled: isNegative ? _total : step,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picker sheet result — [note] is only ever non-null for a backward move
/// (see [_StagePickerSheet]'s note-required step).
class _StagePickerResult {
  const _StagePickerResult(this.stage, {this.note});
  final LeadStage stage;
  final String? note;
}

/// Two-step bottom sheet: a list of reachable stages (forward + terminal
/// negatives + a "move back" section), then — only when a backward stage is
/// picked — a required note before the move is confirmed.
class _StagePickerSheet extends StatefulWidget {
  const _StagePickerSheet({
    required this.current,
    required this.forward,
    required this.backward,
    required this.canLose,
  });

  final LeadStage current;
  final List<LeadStage> forward;
  final List<LeadStage> backward;
  final bool canLose;

  @override
  State<_StagePickerSheet> createState() => _StagePickerSheetState();
}

class _StagePickerSheetState extends State<_StagePickerSheet> {
  LeadStage? _pendingBackward;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingBackward;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: pending == null ? _buildList() : _buildNoteStep(pending),
        ),
      ),
    );
  }

  List<Widget> _buildList() {
    return [
      Center(
        child: Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.westar,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Text('Move to stage', style: AppText.display20.copyWith(fontSize: 18)),
      const SizedBox(height: 2),
      Text(
        'Currently: ${widget.current.label}',
        style: AppText.caption11.copyWith(color: AppColors.schooner),
      ),
      const AppGap.md(),
      for (final s in widget.forward)
        _StageOptionRow(
          stage: s,
          onTap: () => Navigator.of(context).pop(_StagePickerResult(s)),
        ),
      if (widget.canLose) ...[
        const AppGap.sm(),
        const Divider(height: 1),
        const AppGap.sm(),
        Text('CLOSE LEAD', style: AppText.label11),
        const AppGap.xs(),
        Row(
          children: [
            Expanded(
              child: _NegativeButton(
                label: 'Closed Lost',
                icon: Icons.cancel_outlined,
                onTap: () => Navigator.of(
                  context,
                ).pop(_StagePickerResult(LeadStage.closedLost)),
              ),
            ),
            const AppGap.xs(axis: Axis.horizontal),
            Expanded(
              child: _NegativeButton(
                label: 'Junk',
                icon: Icons.block_outlined,
                onTap: () => Navigator.of(
                  context,
                ).pop(_StagePickerResult(LeadStage.junk)),
              ),
            ),
          ],
        ),
      ],
      if (widget.backward.isNotEmpty) ...[
        const AppGap.sm(),
        const Divider(height: 1),
        const AppGap.sm(),
        Text('MOVE BACK / REOPEN', style: AppText.label11),
        const SizedBox(height: 2),
        Text(
          'Requires a note explaining why — it gets saved with the change.',
          style: AppText.caption11.copyWith(color: AppColors.schooner),
        ),
        const AppGap.xs(),
        for (final s in widget.backward)
          _StageOptionRow(
            stage: s,
            muted: true,
            onTap: () => setState(() => _pendingBackward = s),
          ),
      ],
    ];
  }

  List<Widget> _buildNoteStep(LeadStage stage) {
    final note = _noteController.text.trim();
    return [
      Row(
        children: [
          InkWell(
            onTap: () => setState(() => _pendingBackward = null),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.arrow_back, size: 20, color: AppColors.merlin),
            ),
          ),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              'Move back to ${stage.label}',
              style: AppText.display20.copyWith(fontSize: 18),
            ),
          ),
        ],
      ),
      const AppGap.xs(),
      Text(
        'Moving a lead backward needs a reason on record.',
        style: AppText.caption11.copyWith(color: AppColors.schooner),
      ),
      const AppGap.md(),
      TextField(
        controller: _noteController,
        autofocus: true,
        maxLines: 3,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Why is this lead moving back? (required)',
          hintStyle: AppText.body13.copyWith(color: AppColors.tide),
          filled: true,
          fillColor: AppColors.pampas,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.westar),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.westar),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.tahitiGold),
          ),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
      const AppGap.lg(),
      SizedBox(
        width: double.infinity,
        child: PrimaryButton(
          label: 'Confirm move',
          icon: Icons.check,
          onTap: note.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_StagePickerResult(stage, note: note)),
        ),
      ),
    ];
  }
}

/// Segmented progress bar — [filled] of [total] segments in [color], the rest
/// muted. Reads at a glance without a legend.
class _ProgressSegments extends StatelessWidget {
  const _ProgressSegments({
    required this.total,
    required this.filled,
    required this.color,
  });

  final int total;
  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < filled ? color : AppColors.westar,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

/// A single forward-stage row in the pipeline picker sheet.
class _StageOptionRow extends StatelessWidget {
  const _StageOptionRow({
    required this.stage,
    required this.onTap,
    this.muted = false,
  });

  final LeadStage stage;
  final VoidCallback onTap;

  /// True for a "move back" option — uses a distinct amber accent instead of
  /// the forward-move blue, so backward options never read as a normal
  /// advance at a glance.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final isWin = stage == LeadStage.closedWon;
    final accent = isWin
        ? AppColors.salem
        : (muted ? AppColors.tahitiGold : AppColors.blueRibbon);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isWin
                  ? Icons.emoji_events_outlined
                  : (muted ? Icons.undo : Icons.radio_button_unchecked),
              size: 18,
              color: accent,
            ),
            const AppGap.sm(axis: Axis.horizontal),
            Expanded(
              child: Text(
                stage.label,
                style: AppText.body14.copyWith(
                  fontWeight: isWin ? FontWeight.w700 : FontWeight.w500,
                  color: isWin ? AppColors.salem : AppColors.zeus,
                ),
              ),
            ),
            if (isWin)
              Text(
                'deal',
                style: AppText.caption11.copyWith(color: AppColors.salem),
              )
            else
              Icon(
                Icons.chevron_right,
                size: 18,
                color: muted ? AppColors.tahitiGold : AppColors.tide,
              ),
          ],
        ),
      ),
    );
  }
}

/// One of the two terminal-negative outcome buttons in the picker sheet.
class _NegativeButton extends StatelessWidget {
  const _NegativeButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.redSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.redBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.alizarin),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.body13.copyWith(
                color: AppColors.alizarin,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Next Steps ──────────────────────────────────────────────────────────────

/// AI-recommended next action for this lead (from the memory bubble's
/// `next_call_strategy`) plus any promises the telecaller still owes the
/// prospect (`pending_commitments`). Read-only guidance with a quick shortcut
/// to schedule the follow-up.
class _NextStepsPanel extends StatelessWidget {
  const _NextStepsPanel({required this.lead, this.onSchedule});

  final Lead lead;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final step = lead.nextStep.trim();
    final commitments = lead.pendingCommitments;
    final hasContent = step.isNotEmpty || commitments.isNotEmpty;

    return SectionPanel(
      title: 'Next Steps',
      icon: Icons.flag_outlined,
      titleColor: AppColors.blueRibbon,
      color: AppColors.ribbonSurface,
      borderColor: AppColors.ribbonBorder,
      trailing: onSchedule == null
          ? null
          : InkWell(
              onTap: onSchedule,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: AppColors.blueRibbon,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Schedule',
                      style: AppText.caption11.copyWith(
                        color: AppColors.blueRibbon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasContent)
            Text(
              'No next steps yet. Make a call to get AI recommendations.',
              style: AppText.caption11.copyWith(color: AppColors.schooner),
            ),
          if (step.isNotEmpty)
            _NextStepRow(
              icon: Icons.bolt,
              iconColor: AppColors.blueRibbon,
              label: 'Recommended',
              text: step,
            ),
          if (step.isNotEmpty && commitments.isNotEmpty) const AppGap.sm(),
          for (var i = 0; i < commitments.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == commitments.length - 1 ? 0 : 8,
              ),
              child: _NextStepRow(
                icon: Icons.check_circle_outline,
                iconColor: AppColors.tahitiGold,
                label: 'Owed',
                text: commitments[i],
              ),
            ),
        ],
      ),
    );
  }
}

class _NextStepRow extends StatelessWidget {
  const _NextStepRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const AppGap(10, axis: Axis.horizontal),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppText.caption11.copyWith(
                  color: iconColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(text, style: AppText.body14),
            ],
          ),
        ),
      ],
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Memory rebuilt')));
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 = this contact has no analysed calls yet, so retrying won't help;
      // say so plainly instead of a generic error.
      final msg = e.isNotFound
          ? 'No analysed calls yet — nothing to rebuild.'
          : 'Couldn’t rebuild memory. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                    icon: const Icon(
                      Icons.refresh,
                      size: 18,
                      color: AppColors.electricViolet,
                    ),
                  )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact && lead.history.isNotEmpty) ...[
            Builder(
              builder: (_) {
                final last = lead.history.first;
                final when = last.calledAt;
                final ago = when == null
                    ? 'recently'
                    : _agoLabel(DateTime.now().difference(when));
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
              },
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
                            const Icon(
                              Icons.upload_file,
                              size: 15,
                              color: AppColors.blueRibbon,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Upload',
                              style: AppText.caption11.copyWith(
                                color: AppColors.blueRibbon,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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
                      // No call_id yet means it was never captured/uploaded —
                      // pass extra: true so this re-entry retries the scan
                      // for the recording, same as the other post-call routes.
                      : context.push('/leads/$leadId/post-call', extra: true),
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
