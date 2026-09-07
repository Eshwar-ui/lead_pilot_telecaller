import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/call_readiness.dart';
import '../services/call_recording_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Stands between the telecaller and a call this phone could not record.
///
/// There is deliberately no "call anyway": an unrecorded call yields no
/// transcript, no score and no lead memory, so it costs the telecaller the
/// work twice over. What there is instead is a way out on this screen — the
/// two things that actually fix it are the buttons, rather than instructions
/// pointing somewhere else.
class RecordingRequiredDialog extends StatefulWidget {
  const RecordingRequiredDialog._({required this.reason});

  final CallBlockReason reason;

  /// Shows the dialog and resolves once it closes. The caller re-runs
  /// [CallReadiness.check] afterwards rather than trusting a return value —
  /// whether the fix took is a question only the OS can answer.
  static Future<void> show(BuildContext context, CallBlockReason reason) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => RecordingRequiredDialog._(reason: reason),
    );
  }

  @override
  State<RecordingRequiredDialog> createState() =>
      _RecordingRequiredDialogState();
}

class _RecordingRequiredDialogState extends State<RecordingRequiredDialog> {
  static const _service = CallRecordingService();
  bool _busy = false;

  String get _body => switch (widget.reason) {
    CallBlockReason.permissionMissing =>
      'This app needs permission to read audio files before it can pick up '
          'your call recordings. Without it, every call you make is lost.',
    CallBlockReason.noRecordingsVisible =>
      'No call recordings can be found on this phone. Turn on "Record calls" '
          'in your Phone app settings — and if it is already on, point the app '
          'at the folder your phone saves them in.',
  };

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _grantPermission() =>
      _run(() async => _service.ensureStoragePermission());

  Future<void> _pickFolder() =>
      _run(() async => _service.pickRecordingsFolder());

  @override
  Widget build(BuildContext context) {
    final permission = widget.reason == CallBlockReason.permissionMissing;

    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      icon: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(
          color: AppColors.warningSurface,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.mic_off_outlined,
          color: AppColors.tahitiGold,
          size: 24,
        ),
      ),
      title: Text(
        'Call recording is not set up',
        style: AppText.display16,
        textAlign: TextAlign.center,
      ),
      content: Text(
        _body,
        style: AppText.body13.copyWith(color: AppColors.schooner),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blueRibbon,
                  foregroundColor: AppColors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                ),
                onPressed: _busy
                    ? null
                    : (permission ? _grantPermission : _pickFolder),
                child: Text(
                  permission
                      ? 'Grant permission'
                      : 'Select recordings folder',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        context.push('/recording-check');
                      },
                child: Text(
                  'Run recording check',
                  style: AppText.body13.copyWith(color: AppColors.merlin),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Runs the gate and, when a call is blocked, explains why and offers the fix.
///
/// Returns true when the call may proceed. After the dialog closes the check
/// runs once more, so a telecaller who grants the permission or picks the
/// folder right there gets their call through on the same tap rather than
/// having to press call again.
Future<bool> ensureCallCanBeRecorded(BuildContext context) async {
  final reason = await const CallReadiness().check();
  if (reason == null) return true;
  if (!context.mounted) return false;

  await RecordingRequiredDialog.show(context, reason);
  return await const CallReadiness().check() == null;
}
