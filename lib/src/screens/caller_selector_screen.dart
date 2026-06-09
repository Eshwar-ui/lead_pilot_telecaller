import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class CallerSelectorScreen extends ConsumerWidget {
  const CallerSelectorScreen({super.key, required this.leadId});

  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remember = ref.watch(rememberCallerChoiceProvider);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.72),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'complete action using',
                  style: AppText.body14.copyWith(
                    color: AppColors.zeus,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const AppGap(32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CallerOption(
                      label: 'Phone',
                      icon: Icons.phone,
                      onTap: () {
                        ref
                            .read(callerChoiceProvider.notifier)
                            .set(CallerChoice.phone);
                        context.go('/dialer/$leadId');
                      },
                    ),
                    _CallerOption(
                      label: 'True Caller',
                      icon: Icons.call,
                      selected: true,
                      onTap: () {
                        ref
                            .read(callerChoiceProvider.notifier)
                            .set(CallerChoice.trueCaller);
                        context.go('/dialer/$leadId');
                      },
                    ),
                    _CallerOption(
                      label: 'Others',
                      icon: Icons.more_horiz,
                      onTap: () {
                        ref
                            .read(callerChoiceProvider.notifier)
                            .set(CallerChoice.others);
                        context.go('/dialer/$leadId');
                      },
                    ),
                  ],
                ),
                const AppGap.xl(),
                TapScale(
                  onTap: () => ref
                      .read(rememberCallerChoiceProvider.notifier)
                      .set(!remember),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.westar),
                          color: remember
                              ? AppColors.blueRibbon
                              : AppColors.white,
                        ),
                        child: remember
                            ? const Icon(
                                Icons.check,
                                color: AppColors.white,
                                size: 13,
                              )
                            : null,
                      ),
                      const AppGap.xs(axis: Axis.horizontal),
                      Text(
                        'Remember My Choice',
                        style: AppText.body13.copyWith(
                          color: AppColors.merlin,
                        ),
                      ),
                    ],
                  ),
                ),
                const AppGap(32),
                const Divider(height: 1),
                const AppGap.sm(),
                TextButton(
                  onPressed: () => context.pop(),
                  child: Text(
                    'Cancel',
                    style: AppText.body14.copyWith(
                      color: AppColors.blueRibbon,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallerOption extends StatelessWidget {
  const _CallerOption({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: selected ? AppColors.blueRibbon : AppColors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.westar),
              boxShadow: selected ? AppShadows.blueAction : AppShadows.card,
            ),
            child: Icon(
              icon,
              color: selected ? AppColors.white : AppColors.blueRibbon,
              size: 30,
            ),
          ),
          const AppGap.xs(),
          Text(label, style: AppText.body13.copyWith(color: AppColors.zeus)),
        ],
      ),
    );
  }
}
