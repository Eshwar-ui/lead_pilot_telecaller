import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/user_profile_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'leadpilot_widgets.dart';

/// Bottom sheet to edit the telecaller's own profile (name, role, company).
class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({super.key, required this.profile});

  final UserProfile profile;

  static Future<void> show(BuildContext context, UserProfile profile) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => EditProfileSheet(profile: profile),
      );

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  late final TextEditingController _name;
  late final TextEditingController _role;
  late final TextEditingController _company;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _role = TextEditingController(text: widget.profile.role);
    _company = TextEditingController(text: widget.profile.company);
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(userProfileProvider.notifier)
          .update(
            widget.profile.copyWith(
              name: _name.text.trim(),
              role: _role.text.trim(),
              company: _company.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Could not save profile. Try again.')),
          );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: AppColors.westar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Edit profile', style: AppText.display20.copyWith(fontSize: 18)),
          const SizedBox(height: 16),
          _Field(label: 'Name', controller: _name),
          const SizedBox(height: 14),
          _Field(label: 'Role', controller: _role),
          const SizedBox(height: 14),
          _Field(label: 'Company', controller: _company),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Save profile',
              icon: Icons.check,
              onTap: _save,
              loading: _saving,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.body14.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.merlin,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: AppText.body14.copyWith(fontSize: 15, color: AppColors.zeus),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.pampas,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.westar),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.blueRibbon),
            ),
          ),
        ),
      ],
    );
  }
}
