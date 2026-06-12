import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppRadius, AppSpacing;

import '../models/lead.dart';
import '../services/call_actions.dart';
import '../services/transcription_service.dart';
import '../state/call_capture.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class PostCallScreen extends ConsumerStatefulWidget {
  const PostCallScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<PostCallScreen> createState() => _PostCallScreenState();
}

class _PostCallScreenState extends ConsumerState<PostCallScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AnimationController _renderController;
  Timer? _renderTimer;
  int _selectedTab = 0;
  bool _rendering = true;

  static const _tabs = ['Summary', 'Score', 'Transcript'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _renderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _renderTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _rendering = false);
      _renderController.stop();
    });
    _syncCallNotes(stopOverlay: true);
    // Pick up the recording the dialer saved for the call that just ended.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(callCaptureProvider.notifier).captureLatest(widget.leadId);
    });
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    _renderController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncCallNotes();
      // Returning from the call screen — the recording should exist by now.
      ref.read(callCaptureProvider.notifier).captureLatest(widget.leadId);
    }
  }

  Future<void> _syncCallNotes({bool stopOverlay = false}) async {
    if (stopOverlay) {
      await stopCallNotesBubble();
    }

    final notes = await getNativeCallNotes(widget.leadId);
    if (!mounted) return;
    ref.read(callNotesProvider.notifier).setNotes(widget.leadId, notes);
  }

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (l) => l.id == widget.leadId,
      orElse: () => leads.first,
    );
    final callNotes = ref.watch(callNotesProvider)[widget.leadId] ?? '';
    final capture = ref.watch(callCaptureProvider)[widget.leadId];
    final analysis = capture?.transcription?.analysis;
    final isAnalysing = capture?.status == CaptureStatus.transcribing;

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          children: [
            _CallDetailHeader(lead: lead, analysis: analysis),
            _TabStrip(
              tabs: _tabs,
              selectedIndex: _selectedTab,
              onSelected: (index) => setState(() => _selectedTab = index),
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  _SummaryTab(
                    lead: lead,
                    notes: callNotes,
                    rendering: _rendering,
                    isAnalysing: isAnalysing,
                    analysis: analysis,
                    animation: _renderController,
                  ),
                  _ScoreTab(lead: lead, analysis: analysis),
                  _TranscriptTab(leadId: lead.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallDetailHeader extends StatelessWidget {
  const _CallDetailHeader({required this.lead, this.analysis});

  final Lead lead;
  final CallAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: [
          Row(
            children: [
              LpIconButton(
                icon: Icons.arrow_back,
                onTap: () => context.go('/leads/${lead.id}'),
                size: 38,
              ),
              const Spacer(),
              Text(
                'CALL DETAIL',
                style: AppText.label11.copyWith(
                  color: AppColors.schooner,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 38),
            ],
          ),
          Text(
            lead.name,
            style: AppText.display20.copyWith(fontSize: 19),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          _HeroScore(score: analysis?.scores.overall),
        ],
      ),
    );
  }
}

class _HeroScore extends StatelessWidget {
  const _HeroScore({required this.score});

  /// Overall score 0–100, or null when there's no analysis yet.
  final int? score;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 128,
      child: CustomPaint(
        painter: _HeroScorePainter((score ?? 0) / 100),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score?.toString() ?? '--',
                style: AppText.mono(
                  size: 38,
                  weight: FontWeight.w800,
                  color: AppColors.salem,
                ),
              ),
              Text(
                '/ 100',
                style: AppText.caption11.copyWith(
                  color: AppColors.tide,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroScorePainter extends CustomPainter {
  _HeroScorePainter(this.progress);

  final double progress;

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
      ..color = AppColors.salem;

    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - stroke, base);
    const gap = math.pi / 5;
    final sweep = ((math.pi * 2) - (gap * 4)) / 4 * progress.clamp(0.12, 1.0);
    for (var i = 0; i < 4; i++) {
      final start = -math.pi / 2 + i * ((math.pi * 2) / 4) + gap / 2;
      canvas.drawArc(rect.deflate(stroke), start, sweep, false, active);
    }
  }

  @override
  bool shouldRepaint(covariant _HeroScorePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      height: 48,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          tabs[i],
                          style: AppText.body13.copyWith(
                            color: i == selectedIndex
                                ? AppColors.blueRibbon
                                : AppColors.schooner,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 2,
                      width: i == selectedIndex ? 96 : 0,
                      color: AppColors.blueRibbon,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.lead,
    required this.notes,
    required this.rendering,
    required this.isAnalysing,
    required this.animation,
    this.analysis,
  });

  final Lead lead;
  final String notes;
  final bool rendering;
  final bool isAnalysing;
  final Animation<double> animation;
  final CallAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    // Show the analysing skeleton during the initial render, or while the
    // backend is still transcribing/scoring and no analysis has arrived yet.
    final showSkeleton = analysis == null && (rendering || isAnalysing);
    if (showSkeleton) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _CallRecordingCard(leadId: lead.id),
          const AppGap.md(),
          _RenderingAnalysisPanel(animation: animation),
          const AppGap.md(),
          const _SkeletonSummary(),
        ],
      );
    }

    final a = analysis;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _CallRecordingCard(leadId: lead.id),
        const AppGap.md(),
        if (a != null && a.summary.trim().isNotEmpty) ...[
          _AnalysisSummaryCard(summary: a.summary.trim()),
          const AppGap.md(),
        ],
        _CallNotesCard(notes: notes),
        if (a != null) ...[
          if (a.keyPoints.isNotEmpty) ...[
            const AppGap.md(),
            _KeyPointsCard(keyPoints: a.keyPoints, notes: notes),
          ],
          if (a.nextSteps.isNotEmpty) ...[
            const AppGap.md(),
            _NextStepsCard(steps: a.nextSteps),
          ],
        ] else ...[
          const AppGap.md(),
          const _AwaitingAnalysisCard(
            message:
                'Key points and next steps appear after you capture and '
                'transcribe the call.',
          ),
        ],
      ],
    );
  }
}

/// Honest empty state shown before a real analysis exists.
class _AwaitingAnalysisCard extends StatelessWidget {
  const _AwaitingAnalysisCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.insights_outlined, size: 20, color: AppColors.tide),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              message,
              style: AppText.body13.copyWith(
                color: AppColors.schooner,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisSummaryCard extends StatelessWidget {
  const _AnalysisSummaryCard({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppColors.electricViolet,
              ),
              const AppGap.xs(axis: Axis.horizontal),
              Text('Call Summary', style: AppText.display16),
            ],
          ),
          const AppGap.sm(),
          Text(summary, style: AppText.body14.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}

class _RenderingAnalysisPanel extends StatelessWidget {
  const _RenderingAnalysisPanel({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final pulse =
            0.58 + (0.42 * Curves.easeInOut.transform(animation.value));

        return LpCard(
          color: AppColors.ribbonSurface,
          borderColor: AppColors.periwinkle,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _PulseDot(opacity: pulse),
              const AppGap.sm(axis: Axis.horizontal),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Analysing call...',
                      style: AppText.body14.copyWith(
                        color: AppColors.blueRibbon,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Key points and scores appear within 60 seconds',
                      style: AppText.caption11.copyWith(
                        color: AppColors.schooner,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonSummary extends StatelessWidget {
  const _SkeletonSummary();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Key Points', style: AppText.display16),
        const AppGap.sm(),
        const _SkeletonLine(widthFactor: 0.94),
        const AppGap.xs(),
        const _SkeletonLine(widthFactor: 0.80),
        const AppGap.xs(),
        const _SkeletonLine(widthFactor: 0.88),
        const AppGap.xs(),
        const _SkeletonLine(widthFactor: 0.66),
        const AppGap.xl(),
        Text('Next Steps', style: AppText.display16),
        const AppGap.sm(),
        const _SkeletonBlock(),
        const AppGap.xs(),
        const _SkeletonBlock(),
        const AppGap.xs(),
        const _SkeletonBlock(),
      ],
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: AppColors.westar.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.westar.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    );
  }
}

class _CallNotesCard extends StatelessWidget {
  const _CallNotesCard({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final trimmedNotes = notes.trim();

    return LpCard(
      color: AppColors.ribbonSurface,
      borderColor: AppColors.periwinkle,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sticky_note_2_outlined,
                size: 16,
                color: AppColors.blueRibbon,
              ),
              const AppGap.xs(axis: Axis.horizontal),
              Text(
                'CALL NOTES',
                style: AppText.label11.copyWith(color: AppColors.blueRibbon),
              ),
            ],
          ),
          const AppGap.xs(),
          Text(
            trimmedNotes.isEmpty ? 'No notes captured yet.' : trimmedNotes,
            style: AppText.body13.copyWith(
              color: trimmedNotes.isEmpty
                  ? AppColors.schooner
                  : AppColors.merlin,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyPointsCard extends StatelessWidget {
  const _KeyPointsCard({required this.keyPoints, required this.notes});

  final List<String> keyPoints;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final capturedNotes = notes.trim();
    final points = [
      ...keyPoints,
      if (capturedNotes.isNotEmpty) capturedNotes,
    ];

    return LpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 16,
                color: AppColors.electricViolet,
              ),
              const AppGap.xs(axis: Axis.horizontal),
              Text('Key Points', style: AppText.display16),
            ],
          ),
          const AppGap.sm(),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.blueRibbon,
                    ),
                  ),
                  const AppGap.sm(axis: Axis.horizontal),
                  Expanded(child: Text(point, style: AppText.body14)),
                  const Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: AppColors.tide,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NextStepsCard extends StatelessWidget {
  const _NextStepsCard({required this.steps});

  final List<AnalysisNextStep> steps;

  @override
  Widget build(BuildContext context) {
    final rows = [for (final s in steps) (s.title, s.action)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next Steps', style: AppText.display16),
        const AppGap.sm(),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: LpCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.ribbonSurface,
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: AppText.body13.copyWith(
                        color: AppColors.blueRibbon,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const AppGap.sm(axis: Axis.horizontal),
                  Expanded(
                    child: Text(
                      rows[i].$1,
                      style: AppText.body13.copyWith(
                        color: AppColors.zeus,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _SoftAction(label: rows[i].$2),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SoftAction extends StatelessWidget {
  const _SoftAction({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ribbonSurface,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: AppText.body13.copyWith(
          color: AppColors.blueRibbon,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ScoreTab extends StatelessWidget {
  const _ScoreTab({required this.lead, this.analysis});

  final Lead lead;
  final CallAnalysis? analysis;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    if (a == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: const [
          _AwaitingAnalysisCard(
            message:
                'Call scores appear after you capture and transcribe the '
                'call from the Summary tab.',
          ),
        ],
      );
    }

    final s = a.scores;
    final metrics = <(String, int)>[
      ('Overall', s.overall),
      ('Telecaller', s.telecaller),
      ('Lead Quality', s.leadQuality),
      ('Sentiment', s.sentiment),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.08,
          children: [
            for (final m in metrics)
              _MetricScoreCard(
                label: m.$1,
                score: m.$2,
                delta: '',
                good: m.$2 >= 70,
              ),
          ],
        ),
        const AppGap.lg(),
        Row(
          children: [
            Expanded(child: Text('Score Breakdown', style: AppText.display16)),
            _ScoreTag(label: 'Overall - ${s.overall}/100'),
          ],
        ),
        const AppGap.sm(),
        for (final b in a.breakdown)
          _BreakdownRow(
            label: b.label,
            score: '${b.score}/20',
            progress: b.progress,
            note: b.note,
            good: b.good,
          ),
        const AppGap.md(),
        _ScoreSentimentCard(note: a.sentimentNote),
      ],
    );
  }
}

class _MetricScoreCard extends StatelessWidget {
  const _MetricScoreCard({
    required this.label,
    required this.score,
    required this.delta,
    this.good = true,
  });

  final String label;
  final int score;
  final String delta;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.greenHaze : AppColors.tahitiGold;
    return LpCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _MiniScoreRing(score: score, color: color),
          const AppGap.sm(),
          Text(
            label,
            style: AppText.body13.copyWith(
              color: AppColors.merlin,
              fontWeight: FontWeight.w700,
            ),
          ),
          const AppGap.xxs(),
          Text(
            delta,
            style: AppText.body13.copyWith(
              color: good ? AppColors.greenHaze : AppColors.alizarin,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniScoreRing extends StatelessWidget {
  const _MiniScoreRing({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(
        painter: _MiniScorePainter(score / 100, color),
        child: Center(
          child: Text(
            '$score',
            style: AppText.mono(
              size: 24,
              weight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniScorePainter extends CustomPainter {
  _MiniScorePainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.09;
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
  bool shouldRepaint(covariant _MiniScorePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _ScoreTag extends StatelessWidget {
  const _ScoreTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.westar),
      ),
      child: Text(
        label,
        style: AppText.caption11.copyWith(color: AppColors.merlin),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.score,
    required this.progress,
    required this.note,
    this.good = true,
  });

  final String label;
  final String score;
  final double progress;
  final String note;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.greenHaze : AppColors.tahitiGold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppText.body14.copyWith(
                    color: AppColors.zeus,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                score,
                style: AppText.body13.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const AppGap.xs(),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              color: color,
              backgroundColor: AppColors.westar,
            ),
          ),
          const AppGap.xs(),
          Text(
            note,
            style: AppText.caption11.copyWith(
              color: AppColors.schooner,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreSentimentCard extends StatelessWidget {
  const _ScoreSentimentCard({this.note});

  final String? note;

  @override
  Widget build(BuildContext context) {
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
              Text(
                'SENTIMENT TIMELINE',
                style: AppText.label11.copyWith(
                  color: AppColors.electricViolet,
                ),
              ),
            ],
          ),
          const AppGap.sm(),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Row(
              children: const [
                Expanded(
                  flex: 2,
                  child: ColoredBox(
                    color: AppColors.westar,
                    child: SizedBox(height: 18),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ColoredBox(
                    color: Color(0xFFFBBF24),
                    child: SizedBox(height: 18),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ColoredBox(
                    color: AppColors.westar,
                    child: SizedBox(height: 18),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: ColoredBox(
                    color: Color(0xFF34D399),
                    child: SizedBox(height: 18),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ColoredBox(
                    color: Color(0xFF34D399),
                    child: SizedBox(height: 18),
                  ),
                ),
              ],
            ),
          ),
          const AppGap.xs(),
          Text(
            (note != null && note!.trim().isNotEmpty)
                ? note!.trim()
                : 'Prospect warmed up after pitch at 3:54. No negative spike detected.',
            style: AppText.caption11.copyWith(color: AppColors.schooner),
          ),
        ],
      ),
    );
  }
}

String _formatTimestamp(double? seconds) {
  if (seconds == null) return '';
  final total = seconds.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// Renders the real diarized transcript once a recording has been transcribed,
/// with an original ⇄ English toggle. Empty state until then.
class _TranscriptTab extends ConsumerStatefulWidget {
  const _TranscriptTab({required this.leadId});

  final String leadId;

  @override
  ConsumerState<_TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends ConsumerState<_TranscriptTab> {
  bool _showEnglish = false;

  @override
  Widget build(BuildContext context) {
    final capture = ref.watch(callCaptureProvider)[widget.leadId];
    final transcription = capture?.transcription;
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (l) => l.id == widget.leadId,
      orElse: () => leads.first,
    );

    if (transcription == null || transcription.entries.isEmpty) {
      return const _TranscriptEmptyState();
    }

    // Heuristic: the first speaker is the telecaller ("You"); the other is the
    // lead. speakerId is Sarvam's diarization label ("0"/"1").
    final firstSpeaker = transcription.entries.first.speakerId;
    final hasEnglish =
        transcription.entries.any((e) => (e.textEn ?? '').trim().isNotEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if ((transcription.language ?? '').isNotEmpty)
              _MetaChip(label: transcription.language!),
            if (capture?.recording != null)
              _MetaChip(label: capture!.recording!.readableSize),
            _MetaChip(label: '${transcription.entries.length} turns'),
          ],
        ),
        const AppGap.sm(),
        if (hasEnglish) ...[
          _TranscriptLanguageToggle(
            showEnglish: _showEnglish,
            onToggle: () => setState(() => _showEnglish = !_showEnglish),
          ),
          const AppGap.sm(),
        ],
        const AppGap.xs(),
        for (final entry in transcription.entries)
          _MessageBubble(
            speaker: entry.speakerId == firstSpeaker ? 'You' : lead.name,
            time: _formatTimestamp(entry.start),
            text: _showEnglish && (entry.textEn ?? '').trim().isNotEmpty
                ? entry.textEn!.trim()
                : entry.text,
            outgoing: entry.speakerId == firstSpeaker,
          ),
      ],
    );
  }
}

class _TranscriptLanguageToggle extends StatelessWidget {
  const _TranscriptLanguageToggle({
    required this.showEnglish,
    required this.onToggle,
  });

  final bool showEnglish;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      color: AppColors.ribbonSurface,
      borderColor: AppColors.periwinkle,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.language, size: 18, color: AppColors.blueRibbon),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              showEnglish
                  ? 'Showing English translation.'
                  : 'Showing original language.',
              style: AppText.body13.copyWith(color: AppColors.merlin),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: AppColors.periwinkle),
              ),
              child: Text(
                showEnglish ? 'View original' : 'View English',
                style: AppText.body13.copyWith(
                  color: AppColors.blueRibbon,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptEmptyState extends StatelessWidget {
  const _TranscriptEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq, size: 40, color: AppColors.schooner),
            const AppGap.sm(),
            Text('No transcript yet', style: AppText.display16),
            const AppGap.xs(),
            Text(
              'Capture the call recording and tap Transcribe on the Summary '
              'tab. The conversation will appear here, speaker by speaker.',
              style: AppText.body13.copyWith(
                color: AppColors.schooner,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.westar),
      ),
      child: Text(
        label,
        style: AppText.caption11.copyWith(
          color: AppColors.merlin,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.speaker,
    required this.time,
    required this.text,
    this.outgoing = false,
  });

  final String speaker;
  final String time;
  final String text;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final alignment = outgoing ? Alignment.centerRight : Alignment.centerLeft;
    final width = MediaQuery.sizeOf(context).width * 0.74;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: alignment,
        child: Column(
          crossAxisAlignment: outgoing
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              outgoing ? '$time  $speaker' : '$speaker  $time',
              style: AppText.caption11.copyWith(
                color: AppColors.schooner,
                fontWeight: FontWeight.w700,
              ),
            ),
            const AppGap.xxs(),
            Container(
              width: width,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: outgoing ? AppColors.ribbonSurface : AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: outgoing ? AppColors.periwinkle : AppColors.westar,
                ),
              ),
              child: Text(text, style: AppText.body13.copyWith(height: 1.35)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: AppColors.blueRibbon.withValues(
          alpha: opacity.clamp(0.20, 0.38),
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.blueRibbon,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Reflects the capture → transcribe flow for the call's recording file.
///
/// Reads [callCaptureProvider] (kept in sync by [_PostCallScreenState], which
/// triggers a scan on open and on resume) and offers the actions appropriate to
/// the current [CaptureStatus].
class _CallRecordingCard extends ConsumerWidget {
  const _CallRecordingCard({required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(callCaptureProvider.notifier);
    final capture =
        ref.watch(callCaptureProvider)[leadId] ?? const CallCaptureState();

    final (icon, iconColor, title, subtitle) = _present(capture);

    return LpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: capture.isBusy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: iconColor,
                        ),
                      )
                    : Icon(icon, size: 19, color: iconColor),
              ),
              const AppGap.sm(axis: Axis.horizontal),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.body14.copyWith(
                        color: AppColors.zeus,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const AppGap.xxs(),
                    Text(
                      subtitle,
                      style: AppText.caption11.copyWith(
                        color: AppColors.schooner,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ..._actions(context, ref, notifier, capture),
        ],
      ),
    );
  }

  /// (icon, color, title, subtitle) for the current status.
  (IconData, Color, String, String) _present(CallCaptureState capture) {
    switch (capture.status) {
      case CaptureStatus.idle:
      case CaptureStatus.checkingPermission:
      case CaptureStatus.scanning:
        return (
          Icons.graphic_eq,
          AppColors.blueRibbon,
          'Finding call recording…',
          'Reading the recording your dialer saved for this call.',
        );
      case CaptureStatus.found:
        final r = capture.recording!;
        return (
          Icons.audiotrack,
          AppColors.greenHaze,
          'Recording captured',
          '${r.fileName} · ${r.readableSize}',
        );
      case CaptureStatus.transcribing:
        return (
          Icons.cloud_upload_outlined,
          AppColors.blueRibbon,
          'Transcribing…',
          'Uploading audio for speech-to-text.',
        );
      case CaptureStatus.transcribed:
        return (
          Icons.check_circle_outline,
          AppColors.greenHaze,
          'Transcript ready',
          'Open the Transcript tab to read it.',
        );
      case CaptureStatus.notFound:
        return (
          Icons.search_off,
          AppColors.tahitiGold,
          'No recording found',
          capture.message ?? 'Is auto-record enabled in your dialer?',
        );
      case CaptureStatus.permissionDenied:
        return (
          Icons.lock_outline,
          AppColors.tahitiGold,
          'Storage access needed',
          capture.message ?? 'Grant access to read the recording file.',
        );
      case CaptureStatus.permissionBlocked:
        return (
          Icons.lock_outline,
          AppColors.tahitiGold,
          'Enable "All files access"',
          capture.message ?? 'Turn it on in Settings to read recordings.',
        );
      case CaptureStatus.unsupported:
        return (
          Icons.info_outline,
          AppColors.schooner,
          'Android only',
          capture.message ?? 'Call recording capture is not available here.',
        );
      case CaptureStatus.error:
        return (
          Icons.error_outline,
          AppColors.alizarin,
          'Something went wrong',
          capture.message ?? 'Please try again.',
        );
    }
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    CallCaptureController notifier,
    CallCaptureState capture,
  ) {
    Widget bar(List<Widget> buttons) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: buttons),
    );

    switch (capture.status) {
      case CaptureStatus.found:
        return [
          bar([
            _RecordingActionButton(
              label: 'Transcribe',
              filled: true,
              onTap: () => notifier.transcribe(leadId),
            ),
          ]),
        ];
      case CaptureStatus.notFound:
        return [
          bar([
            _RecordingActionButton(
              label: 'Retry',
              onTap: () => notifier.captureLatest(leadId),
            ),
          ]),
        ];
      case CaptureStatus.permissionDenied:
        return [
          bar([
            _RecordingActionButton(
              label: 'Grant access',
              filled: true,
              onTap: () => notifier.captureLatest(leadId),
            ),
          ]),
        ];
      case CaptureStatus.permissionBlocked:
        return [
          bar([
            _RecordingActionButton(
              label: 'Open settings',
              filled: true,
              onTap: () => notifier.openPermissionSettings(),
            ),
          ]),
        ];
      case CaptureStatus.error:
        // If we already have a file, the failure was during transcription.
        return [
          bar([
            _RecordingActionButton(
              label: capture.hasRecording ? 'Retry transcription' : 'Retry',
              onTap: () => capture.hasRecording
                  ? notifier.transcribe(leadId)
                  : notifier.captureLatest(leadId),
            ),
          ]),
        ];
      case CaptureStatus.idle:
      case CaptureStatus.checkingPermission:
      case CaptureStatus.scanning:
      case CaptureStatus.transcribing:
      case CaptureStatus.transcribed:
      case CaptureStatus.unsupported:
        return const [];
    }
  }
}

class _RecordingActionButton extends StatelessWidget {
  const _RecordingActionButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: filled ? AppColors.blueRibbon : AppColors.ribbonSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          label,
          style: AppText.body13.copyWith(
            color: filled ? AppColors.white : AppColors.blueRibbon,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
