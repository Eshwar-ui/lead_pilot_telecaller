import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_store.dart';
import '../services/user_profile_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The telecaller's own details, shown read-only.
///
/// This used to edit the display name into SharedPreferences — a local copy
/// that never reached the backend, so the app and the founder's dashboard
/// quietly disagreed about who someone was, and a founder's correction was
/// invisible here forever. The name/email now come from the server (the
/// founder manages them from Manage Team), so this sheet's job is to SHOW
/// them and say where they're changed.
///
/// Deliberately still reachable from the same Edit button: a telecaller who
/// goes looking for "change my name" gets an answer at the moment they ask,
/// rather than finding the control silently gone.
class EditProfileSheet extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
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
          Text('Your details', style: AppText.display20.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            'These come from your organisation. Ask your founder to update them '
            'from Manage Team.',
            style: AppText.body13.copyWith(color: AppColors.schooner),
          ),
          const SizedBox(height: 18),
          _ReadOnlyRow(label: 'Name', value: profile.name),
          _ReadOnlyRow(label: 'Email', value: session.email ?? '—'),
          _ReadOnlyRow(label: 'Role', value: profile.role),
          if (profile.company.isNotEmpty)
            _ReadOnlyRow(label: 'Organisation', value: profile.company),
          const SizedBox(height: 8),
          Text(
            'Your email is also how you sign in, so it changes only when your '
            'founder changes it.',
            style: AppText.caption11.copyWith(color: AppColors.tide),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.caption11.copyWith(color: AppColors.schooner),
          ),
          const SizedBox(height: 3),
          Text(
            value.isEmpty ? '—' : value,
            style: AppText.body14.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.merlin,
            ),
          ),
        ],
      ),
    );
  }
}
