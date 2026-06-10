import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppRadius, AppSpacing;

import '../models/lead.dart';
import '../services/call_actions.dart';
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

    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Column(
          children: [
            _CallDetailHeader(lead: lead),
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
                    animation: _renderController,
                  ),
                  _ScoreTab(lead: lead),
                  const _TranscriptTab(),
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
  const _CallDetailHeader({required this.lead});

  final Lead lead;

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
          const SizedBox(height: 2),
          Text(
            'Today, 11:48 AM - Duration 06:22',
            style: AppText.caption11.copyWith(
              color: AppColors.schooner,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          _HeroScore(score: _scoreFor(lead)),
        ],
      ),
    );
  }
}

class _HeroScore extends StatelessWidget {
  const _HeroScore({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 128,
      child: CustomPaint(
        painter: _HeroScorePainter(score / 100),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
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
    required this.animation,
  });

  final Lead lead;
  final String notes;
  final bool rendering;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    if (rendering) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _RenderingAnalysisPanel(animation: animation),
          const AppGap.md(),
          const _SkeletonSummary(),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _CallNotesCard(notes: notes),
        const AppGap.md(),
        _KeyPointsCard(lead: lead, notes: notes),
        const AppGap.md(),
        const _NextStepsCard(),
        const AppGap.md(),
        const _ScheduledFollowUpCard(),
        const AppGap.lg(),
        const _CallHistoryCard(),
      ],
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
  const _KeyPointsCard({required this.lead, required this.notes});

  final Lead lead;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final capturedNotes = notes.trim();
    final points = [
      'Looking for a 3BHK in Electronic City, ready-to-move',
      'Budget mentioned: Rs 80L - Rs 1.2Cr',
      "Wife's approval needed before final decision",
      'Compared pricing with Sobha & Prestige projects',
      'Open to a site visit this weekend if a corner unit is available',
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
  const _NextStepsCard();

  static const _steps = [
    ('1', 'Send project brochure via WhatsApp', 'Send now'),
    ('2', 'Call back on Friday after 6 PM', 'Schedule'),
    ('3', 'Check availability of corner unit', 'Note'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next Steps', style: AppText.display16),
        const AppGap.sm(),
        for (final step in _steps)
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
                      step.$1,
                      style: AppText.body13.copyWith(
                        color: AppColors.blueRibbon,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const AppGap.sm(axis: Axis.horizontal),
                  Expanded(
                    child: Text(
                      step.$2,
                      style: AppText.body13.copyWith(
                        color: AppColors.zeus,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _SoftAction(label: step.$3),
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

class _ScheduledFollowUpCard extends StatelessWidget {
  const _ScheduledFollowUpCard();

  @override
  Widget build(BuildContext context) {
    return LpCard(
      color: AppColors.foam,
      borderColor: AppColors.iceCold,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.iceCold),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              color: AppColors.greenHaze,
              size: 18,
            ),
          ),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FOLLOW-UP SCHEDULED',
                  style: AppText.label11.copyWith(color: AppColors.greenHaze),
                ),
                Text(
                  'Friday, 6 June - 6:00 PM',
                  style: AppText.body13.copyWith(
                    color: AppColors.zeus,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const AppGap.xxs(),
                Row(
                  children: [
                    Text('Edit', style: AppText.caption11),
                    const AppGap.sm(axis: Axis.horizontal),
                    Text('Cancel', style: AppText.caption11),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallHistoryCard extends StatelessWidget {
  const _CallHistoryCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Call History', style: AppText.display16),
        const AppGap.sm(),
        LpCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: const [
              _HistoryRow(
                date: '28 May 2026 - 2:47 PM',
                duration: '6m 31s',
                score: 71,
              ),
              Divider(height: 1),
              _HistoryRow(
                date: '21 May 2026 - 1:10 AM',
                duration: '3m 04s',
                score: 76,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.date,
    required this.duration,
    required this.score,
  });

  final String date;
  final String duration;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: AppText.body13.copyWith(
                    color: AppColors.zeus,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text('Duration $duration', style: AppText.caption11),
              ],
            ),
          ),
          _ScoreBadge(score: score),
          const AppGap.sm(axis: Axis.horizontal),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: AppColors.schooner,
          ),
        ],
      ),
    );
  }
}

class _ScoreTab extends StatelessWidget {
  const _ScoreTab({required this.lead});

  final Lead lead;

  @override
  Widget build(BuildContext context) {
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
          children: const [
            _MetricScoreCard(
              label: 'Overall',
              score: 71,
              delta: '^ 5',
              good: false,
            ),
            _MetricScoreCard(label: 'Telecaller', score: 84, delta: '^ 2'),
            _MetricScoreCard(label: 'Lead Quality', score: 76, delta: 'v 3'),
            _MetricScoreCard(
              label: 'Sentiment',
              score: 63,
              delta: '- ',
              good: false,
            ),
          ],
        ),
        const AppGap.lg(),
        Row(
          children: [
            Expanded(child: Text('Score Breakdown', style: AppText.display16)),
            _ScoreTag(label: 'Overall - 71/100'),
          ],
        ),
        const AppGap.sm(),
        const _BreakdownRow(
          label: 'Opening',
          score: '16/20',
          progress: 0.80,
          note:
              "Warm greeting and prospect's name used early - strong rapport.",
        ),
        const _BreakdownRow(
          label: 'Discovery',
          score: '15/20',
          progress: 0.75,
          note: 'Budget and configuration captured; timeline not explored.',
        ),
        const _BreakdownRow(
          label: 'Pitch',
          score: '16/20',
          progress: 0.80,
          note: 'Solution matched to 3BHK need; key amenities highlighted.',
        ),
        const _BreakdownRow(
          label: 'Objection Handling',
          score: '13/20',
          progress: 0.65,
          note: 'Sobha pricing raised but no specific comparison was offered.',
          good: false,
        ),
        const _BreakdownRow(
          label: 'Closing',
          score: '11/20',
          progress: 0.55,
          note: 'Interest confirmed but no firm site-visit date was locked in.',
          good: false,
        ),
        const AppGap.md(),
        const _ScoreSentimentCard(),
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
  const _ScoreSentimentCard();

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
            'Prospect warmed up after pitch at 3:54. No negative spike detected.',
            style: AppText.caption11.copyWith(color: AppColors.schooner),
          ),
        ],
      ),
    );
  }
}

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: const [
        _TranscriptMetaRow(),
        AppGap.sm(),
        _LanguageNotice(),
        AppGap.sm(),
        _TranscriptSearch(),
        AppGap.md(),
        _MessageBubble(
          time: '0:00',
          speaker: 'You',
          text:
              'Namaste Rakesh ji, main LeadPilot Realty se baat kar raha hoon. Aapke paas 2 minute hain?',
          outgoing: true,
        ),
        _MessageBubble(
          speaker: 'Rakesh Sharma',
          time: '0:12',
          text:
              'Haan boliye. Main Electronic City mein 3BHK dhoondh raha hoon, ready-to-move chahiye.',
          highlight: '3BHK dhoondh raha hoon',
        ),
        _MessageBubble(
          time: '0:34',
          speaker: 'You',
          text:
              'Bilkul. Aapka budget range kya rahega taaki main best options dikhaaun?',
          outgoing: true,
        ),
        _MessageBubble(
          speaker: 'Rakesh Sharma',
          time: '0:41',
          text:
              '80 lakh se 1.2 crore tak. Lekin Sobha ka project bhi dekh raha hoon, wahan thoda sasta lag raha hai.',
          highlight: '80 lakh se 1.2 crore tak',
        ),
      ],
    );
  }
}

class _TranscriptMetaRow extends StatelessWidget {
  const _TranscriptMetaRow();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: const [
        _MetaChip(label: '28 May 2026'),
        _MetaChip(label: '2:47 PM'),
        _MetaChip(label: '6m 31s'),
        _MetaChip(label: 'Hindi'),
      ],
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

class _LanguageNotice extends StatelessWidget {
  const _LanguageNotice();

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
              'Transcript is in Hindi.',
              style: AppText.body13.copyWith(color: AppColors.merlin),
            ),
          ),
          _SoftAction(label: 'View English'),
        ],
      ),
    );
  }
}

class _TranscriptSearch extends StatelessWidget {
  const _TranscriptSearch();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.westar),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 17, color: AppColors.schooner),
          const AppGap.sm(axis: Axis.horizontal),
          Text(
            'Search in transcript',
            style: AppText.body13.copyWith(color: AppColors.schooner),
          ),
        ],
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
    this.highlight,
  });

  final String speaker;
  final String time;
  final String text;
  final bool outgoing;
  final String? highlight;

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
              child: _HighlightedText(text: text, highlight: highlight),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, this.highlight});

  final String text;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final target = highlight;
    if (target == null || !text.contains(target)) {
      return Text(text, style: AppText.body13.copyWith(height: 1.35));
    }

    final parts = text.split(target);
    return RichText(
      text: TextSpan(
        style: AppText.body13.copyWith(height: 1.35),
        children: [
          TextSpan(text: parts.first),
          TextSpan(
            text: target,
            style: const TextStyle(backgroundColor: Color(0xFFFFF2A8)),
          ),
          TextSpan(text: parts.length > 1 ? parts.last : ''),
        ],
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: score >= 75 ? AppColors.foam : AppColors.warningSurface,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        '$score',
        style: AppText.body13.copyWith(
          color: score >= 75 ? AppColors.greenHaze : AppColors.tahitiGold,
          fontWeight: FontWeight.w800,
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

int _scoreFor(Lead lead) => lead.score <= 0 ? 92 : lead.score;
