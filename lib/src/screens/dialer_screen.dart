import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing, AppRadius;

import '../services/call_actions.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class DialerScreen extends ConsumerStatefulWidget {
  const DialerScreen({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends ConsumerState<DialerScreen> {
  final _stopwatch = Stopwatch();
  Timer? _ticker;
  bool _muted = false;
  bool _speaker = false;

  // Rotating AI cues to simulate live suggestions
  static const _cues = [
    'Mention Phase 2 completion timeline now',
    'Ask about the site visit - Saturday preferred',
    'Reconfirm budget before closing',
    "Wife's approval needed - offer joint visit",
  ];
  int _cueIndex = 0;
  Timer? _cueTimer;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) { if (mounted) setState(() {}); },
    );
    _cueTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) { if (mounted) setState(() => _cueIndex = (_cueIndex + 1) % _cues.length); },
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cueTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  String get _elapsed {
    final m = _stopwatch.elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(leadsProvider);
    final lead = leads.firstWhere(
      (item) => item.id == widget.leadId,
      orElse: () => leads.first,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF202020),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top: launch native dialer ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TapScale(
                    onTap: () => launchPhoneCall(lead.phone),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.open_in_new,
                        color: AppColors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Centre: score + name + timer ─────────────────────────────
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScoreRing(score: lead.score, size: 96),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    lead.name,
                    style: AppText.display20.copyWith(
                      color: AppColors.white,
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    lead.phone,
                    style: AppText.mono(size: 15, color: AppColors.tide),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Live timer
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      _elapsed,
                      style: AppText.mono(
                        size: 15,
                        weight: FontWeight.w700,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── AI cue strip ─────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Container(
                key: ValueKey(_cueIndex),
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: AppColors.violetSurface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.violetBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: AppColors.electricViolet,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        _cues[_cueIndex],
                        style: AppText.body13.copyWith(
                          color: AppColors.electricViolet,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Controls: mute + speaker ─────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DialControl(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  label: _muted ? 'Unmute' : 'Mute',
                  active: _muted,
                  onTap: () => setState(() => _muted = !_muted),
                ),
                const SizedBox(width: 40),
                _DialControl(
                  icon: _speaker ? Icons.volume_up : Icons.volume_down,
                  label: 'Speaker',
                  active: _speaker,
                  onTap: () => setState(() => _speaker = !_speaker),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── End call ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 72, 32),
              child: PrimaryButton(
                label: 'End',
                color: AppColors.alizarin,
                onTap: () => context.go('/leads/${widget.leadId}/post-call'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialControl extends StatelessWidget {
  const _DialControl({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.blueRibbon
                  : Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppText.caption11.copyWith(color: AppColors.tide),
          ),
        ],
      ),
    );
  }
}
