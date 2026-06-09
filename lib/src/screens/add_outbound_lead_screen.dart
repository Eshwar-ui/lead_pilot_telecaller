import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

class AddOutboundLeadScreen extends ConsumerWidget {
  const AddOutboundLeadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(outboundLeadDraftProvider);
    final controller = ref.read(outboundLeadDraftProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.72),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 820),
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x38111827),
                  blurRadius: 18,
                  offset: Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              children: [
                const AppGap.xs(),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.westar,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add Outbound Lead', style: AppText.display20),
                      Text(
                        'Manually add a lead to your outbound list',
                        style: AppText.body14.copyWith(
                          color: AppColors.schooner,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 17, 20, 24),
                    children: [
                      FormShell(
                        label: 'Name',
                        required: true,
                        child: LpTextField(
                          value: draft.name,
                          onChanged: controller.updateName,
                        ),
                      ),
                      const AppGap.md(),
                      FormShell(
                        label: 'Phone Number',
                        required: true,
                        child: LpTextField(
                          value: draft.phone,
                          onChanged: controller.updatePhone,
                          focused: true,
                        ),
                      ),
                      if (draft.hasDuplicate) ...[
                        const AppGap.xs(),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.warningSurface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.warningBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                color: AppColors.tahitiGold,
                              ),
                              const AppGap.sm(axis: Axis.horizontal),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: AppText.body14.copyWith(
                                      color: AppColors.warningText,
                                    ),
                                    text:
                                        'This number is already in your leads. ',
                                    children: [
                                      TextSpan(
                                        text: 'View existing lead ->',
                                        style: AppText.body14.copyWith(
                                          color: AppColors.blueRibbon,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const AppGap.md(),
                      FormShell(
                        label: 'Reason',
                        required: true,
                        child: LpTextField(
                          value: draft.reason,
                          onChanged: controller.updateReason,
                          maxLines: 3,
                        ),
                      ),
                      const AppGap.md(),
                      FormShell(
                        label: 'Source',
                        required: true,
                        child: Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 19),
                          decoration: BoxDecoration(
                            color: AppColors.pampas,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.westar),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  draft.source,
                                  style: AppText.body14,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down,
                                color: AppColors.schooner,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const AppGap.md(),
                      FormShell(
                        label: 'Call Recording',
                        optionalText: '(optional)',
                        child: Container(
                          height: 120,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: AppColors.pampas,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.westar,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.upload,
                                size: 28,
                                color: AppColors.schooner,
                              ),
                              const AppGap.xs(),
                              Text(
                                'Upload previous call recording',
                                style: AppText.body14.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                '.mp3, .wav, .m4a, .ogg - max 100 MB',
                                style: AppText.caption11.copyWith(
                                  color: AppColors.schooner,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Row(
                    children: [
                      SecondaryButton(
                        label: 'Cancel',
                        onTap: () => context.pop(),
                      ),
                      const AppGap.sm(axis: Axis.horizontal),
                      Expanded(
                        child: SecondaryButton(
                          label: 'Save Lead',
                          onTap: () => context.pop(),
                        ),
                      ),
                      const AppGap.sm(axis: Axis.horizontal),
                      Expanded(
                        child: PrimaryButton(
                          label: 'Save & Call',
                          icon: Icons.phone_outlined,
                          color: AppColors.greenHaze,
                          onTap: () => context.go('/leads/ravi-kumar/pre-call'),
                        ),
                      ),
                    ],
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
