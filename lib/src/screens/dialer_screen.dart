import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../services/call_actions.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class DialerScreen extends ConsumerWidget {
  const DialerScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lead = ref
        .watch(leadsProvider)
        .firstWhere((item) => item.id == leadId);

    return Scaffold(
      backgroundColor: const Color(0xFF202020),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScoreRing(score: lead.score, size: 96),
                  const AppGap.lg(),
                  Text(
                    lead.name,
                    style: AppText.display20.copyWith(
                      color: AppColors.white,
                      fontSize: 28,
                    ),
                  ),
                  const AppGap.xs(),
                  Text(
                    lead.phone,
                    style: AppText.mono(size: 15, color: AppColors.tide),
                  ),
                  const AppGap.xl(),
                  LpPill(
                    label: 'Live call shell',
                    foreground: AppColors.white,
                    background: AppColors.greenHaze,
                    border: AppColors.greenHaze,
                    icon: Icons.graphic_eq,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 220,
              child: TapScale(
                onTap: () => launchPhoneCall(lead.phone),
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.open_in_new, color: AppColors.white),
                ),
              ),
            ),
            Positioned(
              left: 72,
              right: 72,
              bottom: 44,
              child: PrimaryButton(
                label: 'End',
                color: AppColors.alizarin,
                onTap: () => context.go('/leads/$leadId'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
