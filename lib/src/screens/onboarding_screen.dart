import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

enum _Step { phone, otp }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.phone;

  void _onSendOtp() => setState(() => _step = _Step.otp);
  void _onVerify() => context.go('/home');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              _BrandHeader(),
              const SizedBox(height: AppSpacing.xl),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _step == _Step.phone
                    ? _PhoneStep(key: const ValueKey('phone'))
                    : _OtpStep(key: const ValueKey('otp')),
              ),
              const Spacer(),
              _LanguageSelector(),
              const SizedBox(height: AppSpacing.sm),
              _ConsentText(),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: _step == _Step.phone ? 'Send OTP' : 'Verify OTP',
                onTap: _step == _Step.phone ? _onSendOtp : _onVerify,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.blueRibbon,
            borderRadius: BorderRadius.circular(13),
            boxShadow: AppShadows.blueAction,
          ),
          child: const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LeadPilot', style: AppText.display20.copyWith(fontSize: 26)),
            Text(
              'Your AI-powered calling partner',
              style: AppText.caption11.copyWith(color: AppColors.schooner),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phone number',
          style: AppText.body14.copyWith(fontWeight: FontWeight.w700, color: AppColors.zeus),
        ),
        const SizedBox(height: AppSpacing.xs),
        _PhoneField(),
      ],
    );
  }
}

class _PhoneField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.westar),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.westar)),
            ),
            child: Text(
              '+91',
              style: AppText.body14.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.zeus,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppText.mono(size: 15, color: AppColors.zeus),
              decoration: InputDecoration(
                hintText: '98765 43210',
                hintStyle: AppText.mono(size: 15, color: AppColors.tide),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtpStep extends StatelessWidget {
  const _OtpStep({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter 6-digit OTP', style: AppText.display16),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            style: AppText.caption11.copyWith(color: AppColors.schooner),
            children: [
              const TextSpan(text: 'Sent to +91 986 54 210  '),
              TextSpan(
                text: 'Change',
                style: AppText.caption11.copyWith(
                  color: AppColors.blueRibbon,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _OtpBoxRow(),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Resend OTP in 28s',
          style: AppText.caption11.copyWith(color: AppColors.schooner),
        ),
      ],
    );
  }
}

class _OtpBoxRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(
        6,
        (i) => Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 5 ? 8 : 0),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: i == 0 ? AppColors.blueRibbon : AppColors.westar,
                  width: i == 0 ? 1.5 : 1,
                ),
                boxShadow: i == 0 ? AppShadows.card : null,
              ),
              child: const Center(child: SizedBox()),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  static const _scripts = ['తె', 'हि', 'N', 'த', 'ಕ'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Language',
          style: AppText.caption11.copyWith(color: AppColors.schooner),
        ),
        const SizedBox(width: 10),
        for (final s in _scripts)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: AppColors.westar),
              ),
              child: Center(
                child: Text(s, style: AppText.body13.copyWith(fontSize: 14)),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConsentText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: AppText.caption11.copyWith(color: AppColors.schooner),
        children: const [
          TextSpan(text: 'By continuing you agree to our '),
          TextSpan(
            text: 'Terms',
            style: TextStyle(color: AppColors.blueRibbon, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: ' & '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(color: AppColors.blueRibbon, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
