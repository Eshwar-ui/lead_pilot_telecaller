import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../models/lead.dart';
import '../services/call_actions.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';
import 'lead_detail_screen.dart';

class PreCallScreen extends ConsumerStatefulWidget {
  const PreCallScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<PreCallScreen> createState() => _PreCallScreenState();
}

class _PreCallScreenState extends ConsumerState<PreCallScreen> {
  /// True while the pre-call brief (memory bubble, AI script, org-grounded
  /// checklist, objections) is being fetched from the backend.
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // The lead reached here can be a *thin* inbox card (no memory/script/
    // checklist) — enrichment is otherwise only fired fire-and-forget from the
    // Home tile tap, so any other route into pre-call (post-call "Call again",
    // follow-ups, call log, a deep link) would show empty panels and feed an
    // empty overlay. Fetch the full detail as soon as this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureBrief());
  }

  Future<void> _ensureBrief() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      // enrich() re-GETs /api/leads/{id}, which regenerates the brief when the
      // backend hasn't cached one yet, and replaces the thin card in
      // leadsProvider — this screen watches that list, so it rebuilds when the
      // enriched lead lands. Fire-soft: enrich() swallows its own errors.
      await ref.read(leadsProvider.notifier).enrich(widget.leadId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == widget.leadId,
      orElse: () => leads.isEmpty ? Lead.empty() : leads.first,
    );

    final briefReady = lead.script.openingLine.isNotEmpty ||
        lead.script.keyPoints.isNotEmpty ||
        lead.script.steps.isNotEmpty ||
        lead.checklist.isNotEmpty ||
        lead.memory.isNotEmpty;

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
              onTap: () async {
                final lastCall =
                    lead.history.isNotEmpty ? lead.history.first : null;
                // Feed the overlay the memory facts when we have them, else the
                // AI script's key points — so a first-ever call (no memory yet)
                // still shows useful org-grounded context in the floating
                // bubble instead of the "load context first" empty state.
                final overlayFacts = lead.memory.isNotEmpty
                    ? lead.memory.take(4).map((m) => m.text).toList()
                    : lead.script.keyPoints.take(4).toList();
                final result = await startCallWithNotesBubble(
                  leadId: lead.id,
                  leadName: lead.name,
                  phoneNumber: lead.phone,
                  leadScore: lead.score,
                  temperature: lead.temperature.name,
                  intent: lead.intent,
                  scriptOpeningLine: lead.script.openingLine,
                  memoryFacts: overlayFacts,
                  lastCallTs: lastCall?.calledAt?.toIso8601String() ?? '',
                  lastCallScore: lastCall?.score ?? 0,
                  lastCallSummary: lastCall?.title ?? '',
                );
                if (!context.mounted) return;

                if (!result.overlayPermissionGranted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Allow display over other apps, then tap Start Call again.',
                      ),
                    ),
                  );
                  return;
                }

                if (!result.launched) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No calling app available on this device.'),
                    ),
                  );
                  return;
                }

                // The call is NOT logged here just because the dialer opened —
                // it's logged on the post-call screen only once a recording is
                // actually found, so abandoning the dialer doesn't create a
                // phantom call entry.

                // Replace pre-call with post-call so back returns to lead detail.
                // extra=true tells PostCallScreen to reset any previous capture
                // state so a fresh recording is scanned for.
                context.pushReplacement(
                  '/leads/${lead.id}/post-call',
                  extra: true,
                );
              },
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_loading && !briefReady) const _BriefLoadingBanner(),
          if (!_loading && !briefReady)
            _BriefUnavailableCard(onRetry: _ensureBrief),
          LeadSummaryCard(lead: lead),
          const AppGap.md(),
          MemoryPanel(lead: lead, compact: true),
          const AppGap.md(),
          _OpeningScriptPanel(leadId: lead.id, loading: _loading),
          const AppGap.md(),
          _StepsPanel(leadId: lead.id, loading: _loading),
          const AppGap.md(),
          _ObjectionPanel(leadId: lead.id),
          const AppGap.md(),
          _ChecklistPanel(leadId: lead.id, loading: _loading),
        ],
      ),
    );
  }
}

/// Shown at the top of the list while the AI brief is still being fetched /
/// generated, so empty panels below read as "loading" rather than "broken".
class _BriefLoadingBanner extends StatelessWidget {
  const _BriefLoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.violetSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.violetBorder),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.electricViolet,
              ),
            ),
            const AppGap.sm(axis: Axis.horizontal),
            Expanded(
              child: Text(
                'Preparing the AI brief from your organisation knowledge base…',
                style: AppText.body13.copyWith(color: AppColors.electricViolet),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when enrichment finished but no brief came back (backend/LLM failure,
/// or no org knowledge base configured) — offers a retry instead of silently
/// falling back to generic content.
class _BriefUnavailableCard extends StatelessWidget {
  const _BriefUnavailableCard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warningSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warningBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline,
                size: 18, color: AppColors.warningDark),
            const AppGap.sm(axis: Axis.horizontal),
            Expanded(
              child: Text(
                'AI brief unavailable right now. You can still call — tap to retry.',
                style: AppText.body13.copyWith(color: AppColors.warningDark),
              ),
            ),
            const AppGap.xs(axis: Axis.horizontal),
            TextButton(
              onPressed: () => onRetry(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningScriptPanel extends ConsumerWidget {
  const _OpeningScriptPanel({required this.leadId, this.loading = false});

  final String leadId;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.isEmpty ? Lead.empty() : leads.first,
    );
    final hasContent =
        lead.script.openingLine.isNotEmpty || lead.script.keyPoints.isNotEmpty;
    return SectionPanel(
      title: 'AI Script',
      icon: Icons.edit_outlined,
      titleColor: AppColors.electricViolet,
      color: AppColors.violetSurface,
      borderColor: AppColors.violetBorder,
      trailing: Text(lead.script.generatedAgo, style: AppText.caption11),
      child: !hasContent
          ? _PanelPlaceholder(
              loading: loading,
              emptyText: 'No AI script yet for this lead.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lead.script.openingLine.isNotEmpty)
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
                if (lead.script.keyPoints.isNotEmpty) ...[
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
                            style: AppText.body13
                                .copyWith(color: AppColors.schooner),
                          ),
                          Expanded(
                            child: Text(
                              lead.script.keyPoints[i],
                              style: AppText.body13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _StepsPanel extends ConsumerWidget {
  const _StepsPanel({required this.leadId, this.loading = false});

  final String leadId;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.isEmpty ? Lead.empty() : leads.first,
    );
    return SectionPanel(
      title: 'AI Generated Script',
      icon: Icons.auto_awesome,
      titleColor: AppColors.electricViolet,
      child: lead.script.steps.isEmpty
          ? _PanelPlaceholder(
              loading: loading,
              emptyText: 'No call flow generated yet.',
            )
          : Column(
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
      orElse: () => leads.isEmpty ? Lead.empty() : leads.first,
    );
    // No objections yet (thin/first-call lead) — hide the panel entirely rather
    // than show an empty warning-coloured card.
    if (lead.objections.isEmpty) return const SizedBox.shrink();
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
                  if (objection.response.isNotEmpty)
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

/// Loading spinner / empty-state row shared by the AI Script and Steps panels
/// so an un-generated section reads as "loading" or "nothing yet", never blank.
class _PanelPlaceholder extends StatelessWidget {
  const _PanelPlaceholder({required this.loading, required this.emptyText});

  final bool loading;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Row(
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.electricViolet,
            ),
          ),
          const AppGap.sm(axis: Axis.horizontal),
          Text('Generating…',
              style: AppText.body13.copyWith(color: AppColors.schooner)),
        ],
      );
    }
    return Text(
      emptyText,
      style: AppText.body13.copyWith(color: AppColors.schooner),
    );
  }
}

class _ChecklistPanel extends ConsumerWidget {
  const _ChecklistPanel({required this.leadId, this.loading = false});

  final String leadId;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == leadId,
      orElse: () => leads.isEmpty ? Lead.empty() : leads.first,
    );
    final extras = ref.watch(checklistExtrasProvider)[lead.id] ?? const [];
    // Prefer the AI-generated, org-grounded checklist from the pre-call brief.
    // While the brief is still loading, DON'T fall back to the hard-coded
    // real-estate defaults — that fallback is what made the checklist look
    // "not dynamic / not from org details" for non-real-estate orgs. Only fall
    // back once loading has finished and the backend genuinely returned none.
    final List<ChecklistItem> baseItems;
    if (lead.checklist.isNotEmpty) {
      baseItems = lead.checklist;
    } else if (loading) {
      baseItems = const [];
    } else {
      baseItems = defaultChecklistItems;
    }
    final allItems = [...baseItems, ...extras];
    final completed = ref.watch(checklistProvider)[lead.id] ?? <String>{};

    return LpCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('CHECKLIST', style: AppText.label11)),
              Text(
                '${allItems.where((i) => completed.contains(i.id)).length} / ${allItems.length}',
                style: AppText.caption11,
              ),
            ],
          ),
          const AppGap.xs(),
          if (allItems.isEmpty && loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.blueRibbon,
                    ),
                  ),
                  const AppGap.sm(axis: Axis.horizontal),
                  Text('Building checklist…',
                      style:
                          AppText.body13.copyWith(color: AppColors.schooner)),
                ],
              ),
            ),
          for (final item in allItems)
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
          GestureDetector(
            onTap: () => _showAddItemDialog(context, ref, lead.id),
            child: Container(
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
                    style: AppText.body13.copyWith(color: AppColors.schooner),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddItemDialog(
    BuildContext context,
    WidgetRef ref,
    String leadId,
  ) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add checklist item'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Confirm site visit date'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                ref.read(checklistExtrasProvider.notifier).addItem(leadId, text);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}
