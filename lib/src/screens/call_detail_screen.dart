import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppRadius, AppSpacing;

import '../data/lead_repository.dart';
import '../routing/back_navigation.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';
import '../widgets/schedule_call_sheet.dart';

/// ISO language codes → display names, shared by every tab's "View English"
/// banner (Summary/Score/Transcript) so they all describe the source
/// language the same way.
const _langNames = {
  'en': 'English',
  'hi': 'Hindi',
  'te': 'Telugu',
  'ta': 'Tamil',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'mr': 'Marathi',
  'bn': 'Bengali',
  'gu': 'Gujarati',
  'pa': 'Punjabi',
};

/// Splits a flat, index-aligned [translated] list (as returned by
/// `translateTexts`) back into per-key-point + per-next-step translations.
/// Pulled out of `_CallDetailScreenState._toggleSummaryEnglish` so this index
/// math — fragile to any length mismatch from the backend — can be tested
/// directly.
({List<String> keyPoints, List<Map<String, dynamic>> nextSteps})
reassembleTranslatedSummary({
  required List<String> keyPoints,
  required List<Map> nextSteps,
  required List<String> translated,
}) {
  final translatedKeyPoints = translated.take(keyPoints.length).toList();
  final translatedNextStepTexts = translated.skip(keyPoints.length).toList();
  return (
    keyPoints: translatedKeyPoints,
    nextSteps: [
      for (var i = 0; i < nextSteps.length; i++)
        {
          ...Map<String, dynamic>.from(nextSteps[i]),
          if (nextSteps[i].containsKey('text'))
            'text': translatedNextStepTexts[i],
          if (nextSteps[i].containsKey('title'))
            'title': translatedNextStepTexts[i],
        },
    ],
  );
}

/// Splits a flat, index-aligned [translated] list back into the per-dimension
/// breakdown notes/evidence + the overall relevance reason. Pulled out of
/// `_CallDetailScreenState._toggleScoreEnglish` for the same testing reason
/// as [reassembleTranslatedSummary].
({List<Map<String, dynamic>> breakdown, String? relevanceReason})
reassembleTranslatedScore({
  required List<Map> breakdown,
  required List<String> notes,
  required String relevanceReason,
  required List<List<Map>> evidenceLists,
  required List<String> translated,
}) {
  var cursor = 0;
  final translatedNotes = translated.sublist(cursor, cursor + notes.length);
  cursor += notes.length;
  String? translatedRelevance;
  if (relevanceReason.isNotEmpty) {
    translatedRelevance = translated[cursor];
    cursor += 1;
  }
  final translatedEvidence = translated.sublist(cursor);

  var evIdx = 0;
  final newBreakdown = [
    for (var i = 0; i < breakdown.length; i++)
      {
        ...Map<String, dynamic>.from(breakdown[i]),
        'note': translatedNotes[i],
        'evidence': [
          for (final q in evidenceLists[i])
            {
              ...Map<String, dynamic>.from(q),
              'text': translatedEvidence[evIdx++],
            },
        ],
      },
  ];
  return (breakdown: newBreakdown, relevanceReason: translatedRelevance);
}

/// Passed via `go_router`'s `extra` when navigating here from a known
/// [CallRecord] (Lead Detail's history list) so this screen doesn't have to
/// re-fetch the lead's name / this call's date for the header.
class CallDetailArgs {
  const CallDetailArgs({this.leadName, this.calledAt, this.initialTab});

  final String? leadName;
  final DateTime? calledAt;

  /// Tab to open on (0 Summary / 1 Score / 2 Transcript). Used to land
  /// straight on Score right after an upload finishes processing, since
  /// that's the whole point of the screen the user just waited through —
  /// same tab index [PostCallScreen] uses for its own Score tab.
  final int? initialTab;
}

/// Read-only view of one specific historical call — the exact recording that
/// was uploaded or captured for [callId], not "whatever the device's dialer
/// most recently recorded" (that live-capture flow lives in `PostCallScreen`
/// and only applies to a call still in progress).
class CallDetailScreen extends ConsumerStatefulWidget {
  const CallDetailScreen({
    super.key,
    required this.leadId,
    required this.callId,
    this.args,
  });

  final String leadId;
  final String callId;
  final CallDetailArgs? args;

  @override
  ConsumerState<CallDetailScreen> createState() => _CallDetailScreenState();
}

class _CallDetailScreenState extends ConsumerState<CallDetailScreen> {
  late Future<_CallDetailData> _future;
  late int _tab;
  bool _showEnglish = false;
  List<TranscriptTurn>? _translated;
  bool _translating = false;
  final _searchController = TextEditingController();
  String _query = '';

  void _goBack() => goBackOr(context, '/leads/${widget.leadId}');

  // Summary tab's own "View English" toggle — independent of the transcript
  // one above, since a telecaller may only care about one or the other.
  bool _showSummaryEnglish = false;
  Map<String, dynamic>? _translatedAnalysis;
  bool _summaryTranslating = false;

  // Score tab's own "View English" toggle.
  bool _showScoreEnglish = false;
  Map<String, dynamic>? _translatedScore;
  bool _scoreTranslating = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.args?.initialTab ?? 0;
    _future = _load();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<_CallDetailData> _load() async {
    final repo = ref.read(leadRepositoryProvider);
    final transcript = await repo.transcript(widget.callId);
    final analysis = await repo
        .leadAnalysis(widget.callId)
        .catchError((_) => <String, dynamic>{});
    final score = await repo
        .callScore(widget.callId)
        .catchError((_) => <String, dynamic>{});
    return _CallDetailData(
      transcript: transcript,
      analysis: analysis,
      score: score,
    );
  }

  Future<void> _toggleEnglish() async {
    if (_showEnglish) {
      setState(() => _showEnglish = false);
      return;
    }
    if (_translated != null) {
      setState(() => _showEnglish = true);
      return;
    }
    setState(() => _translating = true);
    try {
      final turns = await ref
          .read(leadRepositoryProvider)
          .translatedTranscript(widget.callId);
      if (!mounted) return;
      setState(() {
        _translated = turns;
        _showEnglish = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('Could not translate: $e')));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  /// Translates the Summary tab's key points + next-step text via the
  /// batch `/api/translate` endpoint, lazily and cached — same shape as
  /// [_toggleEnglish] above, just for free-text fields instead of turns.
  Future<void> _toggleSummaryEnglish(Map<String, dynamic> analysis) async {
    if (_showSummaryEnglish) {
      setState(() => _showSummaryEnglish = false);
      return;
    }
    if (_translatedAnalysis != null) {
      setState(() => _showSummaryEnglish = true);
      return;
    }
    setState(() => _summaryTranslating = true);
    try {
      final keyPoints = (analysis['key_points'] is List)
          ? (analysis['key_points'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final nextSteps = (analysis['next_steps'] is List)
          ? (analysis['next_steps'] as List).whereType<Map>().toList()
          : <Map>[];
      final nextStepTexts = [
        for (final s in nextSteps) (s['text'] ?? s['title'] ?? '').toString(),
      ];
      final translated = await ref.read(leadRepositoryProvider).translateTexts([
        ...keyPoints,
        ...nextStepTexts,
      ]);
      if (!mounted) return;
      final reassembled = reassembleTranslatedSummary(
        keyPoints: keyPoints,
        nextSteps: nextSteps,
        translated: translated,
      );
      final newAnalysis = Map<String, dynamic>.from(analysis);
      newAnalysis['key_points'] = reassembled.keyPoints;
      newAnalysis['next_steps'] = reassembled.nextSteps;
      setState(() {
        _translatedAnalysis = newAnalysis;
        _showSummaryEnglish = true;
      });
    } catch (e) {
      if (!mounted) return;
      _toast('Could not translate: $e');
    } finally {
      if (mounted) setState(() => _summaryTranslating = false);
    }
  }

  /// Translates the Score tab's per-dimension notes, evidence quotes, and
  /// relevance note. Same lazy-fetch-and-cache shape as the other toggles.
  Future<void> _toggleScoreEnglish(Map<String, dynamic> rings) async {
    if (_showScoreEnglish) {
      setState(() => _showScoreEnglish = false);
      return;
    }
    if (_translatedScore != null) {
      setState(() => _showScoreEnglish = true);
      return;
    }
    setState(() => _scoreTranslating = true);
    try {
      final breakdown = (rings['breakdown'] is List)
          ? (rings['breakdown'] as List).whereType<Map>().toList()
          : <Map>[];
      final relevanceReason = (rings['relevance_reason'] ?? '').toString();
      final notes = [for (final b in breakdown) (b['note'] ?? '').toString()];
      final evidenceLists = [
        for (final b in breakdown)
          (b['evidence'] is List
              ? (b['evidence'] as List).whereType<Map>().toList()
              : <Map>[]),
      ];
      final evidenceTexts = [
        for (final list in evidenceLists)
          for (final q in list) (q['text'] ?? '').toString(),
      ];
      final translated = await ref.read(leadRepositoryProvider).translateTexts([
        ...notes,
        if (relevanceReason.isNotEmpty) relevanceReason,
        ...evidenceTexts,
      ]);
      if (!mounted) return;

      final reassembled = reassembleTranslatedScore(
        breakdown: breakdown,
        notes: notes,
        relevanceReason: relevanceReason,
        evidenceLists: evidenceLists,
        translated: translated,
      );
      setState(() {
        _translatedScore = {
          ...Map<String, dynamic>.from(rings),
          'breakdown': reassembled.breakdown,
          if (reassembled.relevanceReason != null)
            'relevance_reason': reassembled.relevanceReason,
        };
        _showScoreEnglish = true;
      });
    } catch (e) {
      if (!mounted) return;
      _toast('Could not translate: $e');
    } finally {
      if (mounted) setState(() => _scoreTranslating = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveKeyPoints(List<String> keyPoints) async {
    try {
      await ref
          .read(leadRepositoryProvider)
          .updateKeyPoints(widget.callId, keyPoints);
      if (!mounted) return;
      setState(() => _future = _load());
      _toast('Key points updated.');
    } catch (e) {
      if (!mounted) return;
      _toast('Could not save key points: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackOrFallback(
      fallback: '/leads/${widget.leadId}',
      child: Scaffold(
        backgroundColor: AppColors.springWood,
        body: SafeArea(
          child: FutureBuilder<_CallDetailData>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Column(
                  children: [
                    _Header(
                      onBack: _goBack,
                      leadName: widget.args?.leadName ?? '',
                      calledAt: widget.args?.calledAt,
                      duration: null,
                      heroScore: null,
                      tab: _tab,
                      onTabChanged: (i) => setState(() => _tab = i),
                    ),
                    const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    _Header(
                      onBack: _goBack,
                      leadName: widget.args?.leadName ?? '',
                      calledAt: widget.args?.calledAt,
                      duration: null,
                      heroScore: null,
                      tab: _tab,
                      onTabChanged: (i) => setState(() => _tab = i),
                    ),
                    Expanded(
                      child: LpErrorState(
                        message: snapshot.error.toString(),
                        onRetry: () {
                          // An assignment expression returns the assigned Future;
                          // use a block so setState's callback remains synchronous.
                          setState(() {
                            _future = _load();
                          });
                        },
                      ),
                    ),
                  ],
                );
              }

              final data = snapshot.data!;
              final overall =
                  _toInt(data.score['rings']?['overall']?['value']) ??
                  _toInt(data.analysis['agent_debrief']?['total_score']);
              // Every analysed call is now scored on its own merits — even
              // off-topic / wrong-number calls (the analyzer no longer zeroes
              // them; a genuine wrong number simply scores low). So always show
              // the hero ring; there's no "not a qualifying lead" hiding anymore.
              final duration = _approxDuration(data.transcript.turns);
              final activeTurns = _showEnglish && _translated != null
                  ? _translated!
                  : data.transcript.turns;
              final activeAnalysis =
                  _showSummaryEnglish && _translatedAnalysis != null
                  ? _translatedAnalysis!
                  : data.analysis;
              final activeScore = _showScoreEnglish && _translatedScore != null
                  ? _translatedScore!
                  : data.score;
              final entityPhrases = _entityPhrases(data.analysis['entities']);

              return Column(
                children: [
                  _Header(
                    onBack: _goBack,
                    leadName: widget.args?.leadName ?? '',
                    calledAt: widget.args?.calledAt,
                    duration: duration,
                    heroScore: overall,
                    tab: _tab,
                    onTabChanged: (i) => setState(() => _tab = i),
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        _SummaryTab(
                          leadId: widget.leadId,
                          analysis: activeAnalysis,
                          analysing: data.analysis.isEmpty,
                          language: data.transcript.language,
                          showEnglish: _showSummaryEnglish,
                          translating: _summaryTranslating,
                          onToggleEnglish: () =>
                              _toggleSummaryEnglish(data.analysis),
                          onToast: _toast,
                          onSaveKeyPoints: _saveKeyPoints,
                        ),
                        _ScoreTab(
                          rings: activeScore,
                          language: data.transcript.language,
                          showEnglish: _showScoreEnglish,
                          translating: _scoreTranslating,
                          onToggleEnglish: () =>
                              _toggleScoreEnglish(data.score),
                        ),
                        _TranscriptTab(
                          leadName: widget.args?.leadName ?? 'Lead',
                          calledAt: widget.args?.calledAt,
                          duration: duration,
                          language: data.transcript.language,
                          showEnglish: _showEnglish,
                          translating: _translating,
                          onToggleEnglish: _toggleEnglish,
                          turns: activeTurns,
                          searchController: _searchController,
                          query: _query,
                          highlightPhrases: entityPhrases,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static int? _toInt(Object? v) => v is num ? v.round() : null;

  /// Approximates call length from the last transcript turn's `MM:SS`
  /// timestamp. The backend doesn't store a real duration field yet.
  static Duration? _approxDuration(List<TranscriptTurn> turns) {
    for (final t in turns.reversed) {
      final ts = t.timestamp;
      if (ts == null) continue;
      final parts = ts.split(':');
      if (parts.length != 2) continue;
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m == null || s == null) continue;
      return Duration(minutes: m, seconds: s);
    }
    return null;
  }

  /// Flattens string values out of the call's extracted entities (budget,
  /// timeline, etc.) so the transcript view can highlight where they were
  /// actually said — grounded in real analysis output, not guessed.
  static List<String> _entityPhrases(Object? entities) {
    final out = <String>[];
    void walk(Object? v) {
      if (v is String && v.trim().length >= 3) {
        out.add(v.trim());
      } else if (v is Map) {
        for (final e in v.values) {
          walk(e);
        }
      } else if (v is List) {
        for (final e in v) {
          walk(e);
        }
      }
    }

    walk(entities);
    return out;
  }
}

class _CallDetailData {
  const _CallDetailData({
    required this.transcript,
    required this.analysis,
    required this.score,
  });

  final TranscriptResult transcript;
  final Map<String, dynamic> analysis;
  final Map<String, dynamic> score;
}

// ─── Header (shared across all 3 tabs) ─────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.leadName,
    required this.calledAt,
    required this.duration,
    required this.heroScore,
    required this.tab,
    required this.onTabChanged,
  });

  final VoidCallback onBack;
  final String leadName;
  final DateTime? calledAt;
  final Duration? duration;
  final int? heroScore;
  final int tab;
  final ValueChanged<int> onTabChanged;

  static const _tabs = ['Summary', 'Score', 'Transcript'];

  String _subtitle() {
    final parts = <String>[];
    if (calledAt != null) {
      parts.add(DateFormat('MMM d, h:mm a').format(calledAt!));
    }
    if (duration != null) {
      final m = duration!.inMinutes;
      final s = duration!.inSeconds.remainder(60).toString().padLeft(2, '0');
      parts.add('Duration $m:$s');
    }
    return parts.isEmpty ? '' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.westar)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xxs,
            ),
            child: Row(
              children: [
                LpIconButton(icon: Icons.arrow_back, onTap: onBack),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'CALL DETAIL',
                        style: AppText.label11.copyWith(
                          color: AppColors.schooner,
                          letterSpacing: 0.6,
                        ),
                      ),
                      if (leadName.isNotEmpty)
                        Text(leadName, style: AppText.display16),
                    ],
                  ),
                ),
                const SizedBox(width: 40), // balances the back button
              ],
            ),
          ),
          if (_subtitle().isNotEmpty)
            Text(
              _subtitle(),
              style: AppText.caption11.copyWith(color: AppColors.schooner),
            ),
          const AppGap.sm(),
          if (heroScore != null) ScoreRing(score: heroScore!, size: 120),
          const AppGap.sm(),
          Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTabChanged(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: tab == i
                                ? AppColors.blueRibbon
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _tabs[i],
                        style: AppText.body14.copyWith(
                          fontWeight: tab == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: tab == i
                              ? AppColors.blueRibbon
                              : AppColors.schooner,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Summary tab ────────────────────────────────────────────────────────────

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({
    required this.leadId,
    required this.analysis,
    required this.analysing,
    required this.language,
    required this.showEnglish,
    required this.translating,
    required this.onToggleEnglish,
    required this.onToast,
    required this.onSaveKeyPoints,
  });

  final String leadId;
  final Map<String, dynamic> analysis;
  final bool analysing;
  final String? language;
  final bool showEnglish;
  final bool translating;
  final VoidCallback onToggleEnglish;
  final void Function(String) onToast;
  final Future<void> Function(List<String>) onSaveKeyPoints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (analysing) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          _AnalysingBanner(),
          AppGap.md(),
          _SkeletonCard(lines: 4),
          AppGap.md(),
          _SkeletonCard(lines: 3),
        ],
      );
    }

    final keyPoints = (analysis['key_points'] is List)
        ? (analysis['key_points'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    final nextSteps = (analysis['next_steps'] is List)
        ? (analysis['next_steps'] as List).whereType<Map>().toList()
        : const <Map>[];
    final langName = language != null
        ? (_langNames[language] ?? language!)
        : null;
    // Some completed calls have no language tag even when the transcript is
    // Telugu or another non-English language. Treat an unknown tag as
    // translatable instead of hiding the English action.
    final canTranslate =
        language != 'en' && (keyPoints.isNotEmpty || nextSteps.isNotEmpty);

    final followUps = ref.watch(followUpsProvider);
    final followUpMatches = followUps.where((f) => f.leadId == leadId);
    final followUp = followUpMatches.isEmpty ? null : followUpMatches.first;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (canTranslate) ...[
          _EnglishToggleBanner(
            langName: langName ?? 'the original language',
            sourceLabel: 'Summary',
            showEnglish: showEnglish,
            translating: translating,
            onToggle: onToggleEnglish,
          ),
          const AppGap.md(),
        ],
        if (keyPoints.isNotEmpty)
          LpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Key Points', style: AppText.display16),
                const AppGap.sm(),
                for (final p in keyPoints)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.xs),
                          child: Icon(
                            Icons.circle,
                            size: 5,
                            color: AppColors.blueRibbon,
                          ),
                        ),
                        const AppGap.xs(axis: Axis.horizontal),
                        Expanded(child: Text(p, style: AppText.body14)),
                        InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          onTap: () => _openEditKeyPoints(context, keyPoints),
                          child: const Padding(
                            padding: EdgeInsets.all(AppSpacing.xxs),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: AppColors.schooner,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (nextSteps.isNotEmpty) ...[
          const AppGap.md(),
          LpCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Next Steps', style: AppText.display16),
                const AppGap.sm(),
                for (var i = 0; i < nextSteps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.pampas,
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: AppText.caption11.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const AppGap.sm(axis: Axis.horizontal),
                        Expanded(
                          child: Text(
                            (nextSteps[i]['text'] ??
                                    nextSteps[i]['title'] ??
                                    '')
                                .toString(),
                            style: AppText.body14,
                          ),
                        ),
                        TextButton(
                          onPressed: () => _actOnNextStep(
                            context,
                            ref,
                            (nextSteps[i]['text'] ??
                                    nextSteps[i]['title'] ??
                                    '')
                                .toString(),
                          ),
                          child: Text(
                            (nextSteps[i]['action_label'] ?? 'Note').toString(),
                            style: AppText.caption11.copyWith(
                              color: AppColors.blueRibbon,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (followUp != null) ...[
          const AppGap.md(),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.salem.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.iceCold),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_available,
                  color: AppColors.salem,
                  size: 18,
                ),
                const AppGap.sm(axis: Axis.horizontal),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FOLLOW-UP SCHEDULED',
                        style: AppText.label11.copyWith(color: AppColors.salem),
                      ),
                      Text(
                        followUp.dueLabel ?? '',
                        style: AppText.body14.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final matches = ref
                        .read(leadsProvider)
                        .where((l) => l.id == leadId);
                    if (matches.isNotEmpty) {
                      ScheduleCallSheet.show(context, matches.first);
                    }
                  },
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(followUpsProvider.notifier).delete(followUp.id),
                  child: Text(
                    'Cancel',
                    style: AppText.caption11.copyWith(
                      color: AppColors.alizarin,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (keyPoints.isEmpty && nextSteps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'No analysis available for this call.',
              textAlign: TextAlign.center,
              style: AppText.body14.copyWith(color: AppColors.schooner),
            ),
          ),
      ],
    );
  }

  void _openEditKeyPoints(BuildContext context, List<String> keyPoints) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _EditKeyPointsSheet(initial: keyPoints, onSave: onSaveKeyPoints),
    );
  }

  Future<void> _actOnNextStep(
    BuildContext context,
    WidgetRef ref,
    String stepText,
  ) async {
    try {
      final lead = await ref.read(leadRepositoryProvider).leadDetail(leadId);
      if (!context.mounted) return;
      await ScheduleCallSheet.show(context, lead, initialNote: stepText);
    } catch (e) {
      onToast('Could not open follow-up: $e');
    }
  }
}

/// Bottom sheet for editing a call's AI-extracted key points — add, edit
/// inline, or remove a bullet, then persist via `PATCH /lead-analysis`.
class _EditKeyPointsSheet extends StatefulWidget {
  const _EditKeyPointsSheet({required this.initial, required this.onSave});

  final List<String> initial;
  final Future<void> Function(List<String>) onSave;

  @override
  State<_EditKeyPointsSheet> createState() => _EditKeyPointsSheetState();
}

class _EditKeyPointsSheetState extends State<_EditKeyPointsSheet> {
  late final List<TextEditingController> _controllers = [
    for (final p in widget.initial) TextEditingController(text: p),
  ];
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final points = _controllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    setState(() => _saving = true);
    await widget.onSave(points);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        decoration: const BoxDecoration(
          color: AppColors.springWood,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit key points', style: AppText.display16),
            const AppGap.md(),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < _controllers.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controllers[i],
                                style: AppText.body14,
                                maxLines: null,
                                decoration: const InputDecoration(
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: AppColors.schooner,
                              ),
                              onPressed: () => setState(
                                () => _controllers.removeAt(i).dispose(),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _controllers.add(TextEditingController())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add point'),
            ),
            const AppGap.md(),
            PrimaryButton(
              label: _saving ? 'Saving…' : 'Save',
              onTap: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysingBanner extends StatelessWidget {
  const _AnalysingBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.blueRibbon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analysing call…',
                  style: AppText.body14.copyWith(
                    color: AppColors.blueRibbon,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Key points and scores appear within 60 seconds',
                  style: AppText.caption11.copyWith(color: AppColors.schooner),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.lines});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Container(
                height: 12,
                width: i.isEven ? double.infinity : 180,
                decoration: BoxDecoration(
                  color: AppColors.pampas,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Score tab ──────────────────────────────────────────────────────────────

class _ScoreTab extends StatelessWidget {
  const _ScoreTab({
    required this.rings,
    required this.language,
    required this.showEnglish,
    required this.translating,
    required this.onToggleEnglish,
  });

  final Map<String, dynamic> rings;
  final String? language;
  final bool showEnglish;
  final bool translating;
  final VoidCallback onToggleEnglish;

  @override
  Widget build(BuildContext context) {
    if (rings.isEmpty) {
      return Center(
        child: Text(
          'Score not available yet for this call.',
          style: AppText.body14.copyWith(color: AppColors.schooner),
        ),
      );
    }

    final ringData = rings['rings'] is Map<String, dynamic>
        ? rings['rings'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final breakdown = rings['breakdown'] is List
        ? (rings['breakdown'] as List).whereType<Map>().toList()
        : const <Map>[];
    final overall = _val(ringData['overall']);
    final timeline = rings['sentiment_timeline'] is Map<String, dynamic>
        ? rings['sentiment_timeline'] as Map<String, dynamic>
        : const <String, dynamic>{};

    // Every analysed call is scored on its own merits now (off-topic /
    // wrong-number calls included — the analyzer no longer blanks them), so
    // the rings + breakdown always render. A genuine wrong number simply shows
    // low lead-quality rather than a "not a qualifying lead" empty-state.
    // `relevance_reason` (if any) is surfaced as a note below the rings.
    final relevanceReason = (rings['relevance_reason'] ?? '').toString();
    final hasTranslatableText =
        relevanceReason.trim().isNotEmpty ||
        breakdown.any((b) => (b['note'] ?? '').toString().trim().isNotEmpty);
    final langName = language != null
        ? (_langNames[language] ?? language!)
        : null;
    final canTranslate = language != 'en' && hasTranslatableText;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (canTranslate) ...[
          _EnglishToggleBanner(
            langName: langName ?? 'the original language',
            sourceLabel: 'Score notes',
            showEnglish: showEnglish,
            translating: translating,
            onToggle: onToggleEnglish,
          ),
          const AppGap.md(),
        ],
        if (relevanceReason.trim().isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.pampas,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.schooner,
                ),
                const AppGap.xs(axis: Axis.horizontal),
                Expanded(
                  child: Text(
                    'Relevance note: $relevanceReason',
                    style: AppText.caption11.copyWith(
                      color: AppColors.schooner,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const AppGap.md(),
        ],
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.3,
          children: [
            _RingTile(label: 'Overall', ring: ringData['overall']),
            _RingTile(label: 'Telecaller', ring: ringData['telecaller']),
            _RingTile(label: 'Lead Quality', ring: ringData['lead_quality']),
            _RingTile(label: 'Sentiment', ring: ringData['sentiment']),
          ],
        ),
        const AppGap.md(),
        LpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Score Breakdown', style: AppText.display16),
                  const Spacer(),
                  LpPill(
                    label: 'Overall · $overall/100',
                    foreground: AppColors.salem,
                    background: AppColors.white,
                    border: AppColors.iceCold,
                  ),
                ],
              ),
              const AppGap.sm(),
              for (final b in breakdown) _BreakdownRow(item: b),
            ],
          ),
        ),
        // Render the card whenever the backend computed a timeline at all —
        // including the empty case (no sentiment signal in the call), which
        // still carries an explanatory caption. Previously this was gated on
        // segments being non-empty, so a call with no sentiment signal (an
        // empty sentiment_arc — happens for a handful of real calls) showed
        // no card and no explanation at all, reading as "broken" rather than
        // "nothing to show, and here's why."
        if (timeline.isNotEmpty) ...[
          const AppGap.md(),
          _SentimentTimelineCard(timeline: timeline),
        ],
      ],
    );
  }

  static int _val(Object? ring) => ring is Map ? (_num(ring['value'])) : 0;
  static int _num(Object? v) => v is num ? v.round() : 0;
}

class _RingTile extends StatelessWidget {
  const _RingTile({required this.label, required this.ring});

  final String label;
  final Object? ring;

  @override
  Widget build(BuildContext context) {
    final map = ring is Map ? ring as Map : const {};
    final value = map['value'] is num ? (map['value'] as num).round() : 0;
    final trend = map['trend'] is num ? (map['trend'] as num) : null;

    return LpCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScoreRing(score: value, size: 64),
          const AppGap.xs(),
          Text(
            label,
            style: AppText.caption11.copyWith(fontWeight: FontWeight.w700),
          ),
          if (trend != null)
            Text(
              trend > 0
                  ? '↑ ${trend.abs().round()}'
                  : (trend < 0 ? '↓ ${trend.abs().round()}' : '—'),
              style: AppText.caption11.copyWith(
                color: trend > 0
                    ? AppColors.salem
                    : (trend < 0 ? AppColors.alizarin : AppColors.schooner),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.item});

  final Map item;

  @override
  Widget build(BuildContext context) {
    final score = item['score'] is num ? (item['score'] as num).round() : 0;
    final max = item['max'] is num ? (item['max'] as num).round() : 20;
    final progress = max > 0 ? (score / max).clamp(0, 1).toDouble() : 0.0;
    final good = progress >= 0.7;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                (item['label'] ?? '').toString(),
                style: AppText.body14.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                '$score/$max',
                style: AppText.caption11.copyWith(color: AppColors.schooner),
              ),
            ],
          ),
          const AppGap.xs(),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.pampas,
              valueColor: AlwaysStoppedAnimation(
                good ? AppColors.salem : AppColors.tahitiGold,
              ),
            ),
          ),
          if ((item['note'] ?? '').toString().isNotEmpty) ...[
            const AppGap.xs(),
            Text(
              (item['note']).toString(),
              style: AppText.caption11.copyWith(color: AppColors.schooner),
            ),
          ],
          // Audit trail: the backend attaches the transcript quotes the score
          // was grounded in (evidence: [{turn,t,speaker,text}]). Surface them so
          // a manager can verify why a dimension scored the way it did.
          for (final q in _evidence(item['evidence'])) ...[
            const AppGap.xs(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 2,
                  height: 14,
                  margin: const EdgeInsets.only(top: 2, right: 8),
                  color: AppColors.iceCold,
                ),
                Expanded(
                  child: Text(
                    '${(q['speaker'] ?? '').toString().isNotEmpty ? '${q['speaker']}: ' : ''}“${(q['text'] ?? '').toString()}”',
                    style: AppText.caption11.copyWith(
                      color: AppColors.schooner,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Auditable quotes for this dimension, defensively parsed — each is a
  /// `{turn, t, speaker, text}` map with a non-empty `text`.
  static List<Map> _evidence(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .where((e) => (e['text'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }
}

class _SentimentTimelineCard extends StatelessWidget {
  const _SentimentTimelineCard({required this.timeline});

  final Map<String, dynamic> timeline;

  static const _colors = {
    'neutral': AppColors.tide,
    'cautious': AppColors.tahitiGold,
    'interested': AppColors.salem,
    'frustrated': AppColors.alizarin,
  };

  String _mmss(int sec) =>
      '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final segments = timeline['segments'] is List
        ? (timeline['segments'] as List).whereType<Map>().toList()
        : const <Map>[];
    final caption = (timeline['caption'] ?? '').toString();

    return LpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 14,
                color: AppColors.electricViolet,
              ),
              const AppGap.xs(axis: Axis.horizontal),
              Text('SENTIMENT TIMELINE', style: AppText.label11),
            ],
          ),
          if (segments.isEmpty) ...[
            const AppGap.sm(),
            Text(
              caption.isNotEmpty
                  ? caption
                  : 'No sentiment signal in this call.',
              style: AppText.caption11.copyWith(color: AppColors.schooner),
            ),
          ] else ...[
            const AppGap.sm(),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (final s in segments)
                      Expanded(
                        child: Container(
                          color:
                              _colors[(s['label'] ?? '').toString()] ??
                              AppColors.tide,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const AppGap.xs(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final s in segments)
                  Text(
                    (s['t0'] ?? _mmss((s['t0_sec'] as num?)?.toInt() ?? 0))
                        .toString(),
                    style: AppText.caption11.copyWith(
                      color: AppColors.schooner,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
            const AppGap.sm(),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final e in _colors.entries)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: e.value,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        e.key[0].toUpperCase() + e.key.substring(1),
                        style: AppText.caption11.copyWith(
                          color: AppColors.schooner,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (caption.isNotEmpty) ...[
              const AppGap.xs(),
              Text(
                caption,
                style: AppText.caption11.copyWith(color: AppColors.schooner),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Shared "View English" banner (Summary / Score / Transcript tabs) ──────

class _EnglishToggleBanner extends StatelessWidget {
  const _EnglishToggleBanner({
    required this.langName,
    required this.sourceLabel,
    required this.showEnglish,
    required this.translating,
    required this.onToggle,
  });

  final String langName;

  /// What was in [langName] — "Transcript", "Call", "Score notes" — so each
  /// tab's banner reads naturally.
  final String sourceLabel;
  final bool showEnglish;
  final bool translating;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.blueRibbon.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.language, size: 16, color: AppColors.blueRibbon),
          const AppGap.xs(axis: Axis.horizontal),
          Expanded(
            child: Text(
              showEnglish
                  ? 'Showing English translation.'
                  : '$sourceLabel is in $langName.',
              style: AppText.body14,
            ),
          ),
          if (translating)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: onToggle,
              child: Text(showEnglish ? 'View Original' : 'View English'),
            ),
        ],
      ),
    );
  }
}

// ─── Transcript tab ─────────────────────────────────────────────────────────

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab({
    required this.leadName,
    required this.calledAt,
    required this.duration,
    required this.language,
    required this.showEnglish,
    required this.translating,
    required this.onToggleEnglish,
    required this.turns,
    required this.searchController,
    required this.query,
    required this.highlightPhrases,
  });

  final String leadName;
  final DateTime? calledAt;
  final Duration? duration;
  final String? language;
  final bool showEnglish;
  final bool translating;
  final VoidCallback onToggleEnglish;
  final List<TranscriptTurn> turns;
  final TextEditingController searchController;
  final String query;
  final List<String> highlightPhrases;

  @override
  Widget build(BuildContext context) {
    final langName = language != null
        ? (_langNames[language] ?? language!)
        : null;
    final canTranslate = language != 'en' && turns.isNotEmpty;

    final filtered = query.isEmpty
        ? turns
        : turns.where((t) => t.text.toLowerCase().contains(query)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (calledAt != null)
                _Chip(DateFormat('d MMM yyyy').format(calledAt!)),
              if (calledAt != null)
                _Chip(DateFormat('h:mm a').format(calledAt!)),
              if (duration != null)
                _Chip(
                  '${duration!.inMinutes}m ${(duration!.inSeconds.remainder(60)).toString().padLeft(2, '0')}s',
                ),
              if (langName != null) _Chip(langName),
            ],
          ),
        ),
        if (canTranslate)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _EnglishToggleBanner(
              langName: langName ?? 'the original language',
              sourceLabel: 'Transcript',
              showEnglish: showEnglish,
              translating: translating,
              onToggle: onToggleEnglish,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xxs,
          ),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search in transcript',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: AppColors.pampas,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? 'No transcript available.'
                        : 'No matches found.',
                    style: AppText.body14.copyWith(color: AppColors.schooner),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _TranscriptBubble(
                      turn: filtered[i],
                      leadName: leadName,
                      highlightPhrases: highlightPhrases,
                      query: query,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.westar),
      ),
      child: Text(
        label,
        style: AppText.caption11.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({
    required this.turn,
    required this.leadName,
    required this.highlightPhrases,
    required this.query,
  });

  final TranscriptTurn turn;
  final String leadName;
  final List<String> highlightPhrases;
  final String query;

  @override
  Widget build(BuildContext context) {
    final isAgent = turn.speaker.toUpperCase() == 'AGENT';
    final speakerLabel = isAgent ? 'You' : leadName;

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: isAgent
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [
        if (turn.timestamp != null && isAgent) ...[
          Text(
            turn.timestamp!,
            style: AppText.caption11.copyWith(
              color: AppColors.schooner,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(
          speakerLabel,
          style: AppText.caption11.copyWith(
            color: AppColors.schooner,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (turn.timestamp != null && !isAgent) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            turn.timestamp!,
            style: AppText.caption11.copyWith(
              color: AppColors.schooner,
              fontSize: 10,
            ),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: isAgent
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        labelRow,
        const SizedBox(height: 2),
        Align(
          alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: isAgent
                  ? AppColors.blueRibbon.withValues(alpha: 0.08)
                  : AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: isAgent ? null : Border.all(color: AppColors.westar),
            ),
            child: _highlightedText(turn.text),
          ),
        ),
      ],
    );
  }

  Widget _highlightedText(String text) {
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final ranges = <List<int>>[]; // [start, end)

    void markAll(String needle) {
      if (needle.isEmpty) return;
      final n = needle.toLowerCase();
      var start = 0;
      while (true) {
        final idx = lower.indexOf(n, start);
        if (idx < 0) break;
        ranges.add([idx, idx + n.length]);
        start = idx + n.length;
      }
    }

    if (query.isNotEmpty) markAll(query);
    for (final p in highlightPhrases) {
      markAll(p);
    }
    ranges.sort((a, b) => a[0].compareTo(b[0]));

    var cursor = 0;
    for (final r in ranges) {
      if (r[0] < cursor) continue; // skip overlaps
      if (r[0] > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r[0])));
      }
      spans.add(
        TextSpan(
          text: text.substring(r[0], r[1]),
          style: const TextStyle(backgroundColor: AppColors.warningBorder),
        ),
      );
      cursor = r[1];
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(
        style: AppText.body14.copyWith(color: AppColors.zeus),
        children: spans,
      ),
    );
  }
}
