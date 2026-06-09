import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.westar),
                  boxShadow: AppShadows.card,
                ),
                child: SvgPicture.asset('assets/icons/leadpilot_mark.svg'),
              ),
              const AppGap.xl(),
              Text(
                'LeadPilot',
                style: AppText.display20.copyWith(fontSize: 36, height: 1.05),
              ),
              const AppGap.xs(),
              Text(
                'AI-ready call preparation, lead memory, and telecaller workflows in one focused mobile shell.',
                style: AppText.body14.copyWith(
                  fontSize: 16,
                  color: AppColors.schooner,
                ),
              ),
              const AppGap.xl(),
              _OnboardingRow(
                icon: Icons.psychology_outlined,
                text: 'Personalized pre-call scripts',
              ),
              _OnboardingRow(
                icon: Icons.history,
                text: 'Lead memory from prior calls',
              ),
              _OnboardingRow(
                icon: Icons.check_circle_outline,
                text: 'Checklist-driven follow through',
              ),
              const Spacer(),
              PrimaryButton(
                label: 'Open Queue',
                icon: Icons.arrow_forward,
                onTap: () => context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingRow extends StatelessWidget {
  const _OnboardingRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.blueRibbon, size: 20),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              text,
              style: AppText.body14.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
