import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppSpacing, AppRadius;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/call_actions.dart';
import '../services/call_recording_service.dart';
import '../services/recording_diagnostics.dart';
import '../state/call_capture.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';

/// "Recording Check" — the self-diagnosis a telecaller can run when calls stop
/// being captured, and the evidence support needs to fix it.
///
/// Until now the app could only say "no recent recording found", which is true
/// of at least five unrelated causes. This runs the same folder probe the real
/// scan uses, states which one it is in plain language, offers the one action
/// that fixes it, and (on request) sends the anonymised snapshot to the backend
/// so a specific failing handset can be diagnosed without the telecaller
/// reading paths aloud over the phone.
class RecordingCheckScreen extends ConsumerStatefulWidget {
  const RecordingCheckScreen({super.key});

  @override
  ConsumerState<RecordingCheckScreen> createState() =>
      _RecordingCheckScreenState();
}

class _RecordingCheckScreenState extends ConsumerState<RecordingCheckScreen> {
  RecordingDiagnosticsReport? _report;
  bool _running = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    // Run on open: the user came here because something is broken, and making
    // them press a button first only delays the answer.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _sent = false;
    });
    final report = await const RecordingDiagnostics().run();
    if (!mounted) return;
    setState(() {
      _report = report;
      _running = false;
    });
    // Report every run automatically. The whole point of Phase 0 is a fleet
    // picture of which OEMs fail and why; asking each telecaller to opt in
    // would leave exactly the phones that fail most under-represented. It
    // carries no filenames or call content — see RecordingDiagnostics.
    unawaited(_send(report, silent: true));
  }

  Future<void> _send(
    RecordingDiagnosticsReport report, {
    bool silent = false,
  }) async {
    await ref
        .read(captureTelemetryServiceProvider)
        .report(
          report.outcome,
          accessLevel: report.accessLevel.wireName,
          source: 'diagnostic',
          details: report.toJson(),
        );
    if (!mounted || silent) return;
    setState(() => _sent = true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Report sent to support')));
  }

  Future<void> _grantPermission() async {
    const service = CallRecordingService();
    await service.ensureStoragePermission();
    await _run();
  }

  Future<void> _grantAllFiles() async {
    const service = CallRecordingService();
    await service.requestAllFilesAccess();
    await _run();
  }

  /// The automatic in-call ask for battery-optimization/MIUI-autostart
  /// exemption fires at most once per app process, with no way back in if
  /// the telecaller dismissed it — a very plausible thing to do mid-call,
  /// before understanding why it matters. This re-shows it on demand.
  Future<void> _grantBackgroundPermissions() async {
    await requestBackgroundPermissions();
  }

  void _copyReport() {
    final report = _report;
    if (report == null) return;
    Clipboard.setData(ClipboardData(text: report.toJson().toString()));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Report copied')));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return LpScreen(
      title: 'Recording Check',
      subtitle: 'Why calls are or aren\'t being captured',
      trailing: LpIconButton(
        icon: Icons.refresh,
        onTap: _running ? null : _run,
      ),
      child: _running && report == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : report == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _VerdictCard(report: report),
                const AppGap(AppSpacing.sm),
                ..._actions(report),
                const AppGap(AppSpacing.sm),
                _BackgroundPermissionsCard(onTap: _grantBackgroundPermissions),
                const AppGap(AppSpacing.sm),
                _DeviceCard(report: report),
                const AppGap(AppSpacing.sm),
                _FoldersCard(report: report),
                const AppGap(AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyReport,
                        icon: const Icon(Icons.copy_all_outlined, size: 16),
                        label: const Text('Copy report'),
                      ),
                    ),
                    const AppGap(AppSpacing.xs, axis: Axis.horizontal),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _sent ? null : () => _send(report),
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label: Text(_sent ? 'Sent' : 'Send to support'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// The one button that actually addresses this verdict — never a menu of
  /// everything the screen can do.
  List<Widget> _actions(RecordingDiagnosticsReport report) {
    return switch (report.verdict) {
      RecordingVerdict.permissionMissing => [
        FilledButton(
          onPressed: _grantPermission,
          child: const Text('Grant permission'),
        ),
      ],
      // Offer the escalation whenever access is short of all-files, including
      // when the probe found no folders at all: a folder the app may not stat
      // is indistinguishable from an absent one, and on MIUI that is exactly
      // what happens — 81 real recordings in a folder that reads as missing.
      //
      // This deliberately does NOT hide itself on Android 13+. That guess was
      // wrong on real hardware (a sideloaded app on Android 16 gets a working
      // toggle) and hid the only button that fixes the phone.
      RecordingVerdict.foldersUnreadable ||
      RecordingVerdict.noFolders ||
      RecordingVerdict.foldersEmpty
          when report.accessLevel != StorageAccessLevel.allFiles =>
        [
          FilledButton(
            onPressed: _grantAllFiles,
            child: const Text('Grant "All files access"'),
          ),
        ],
      _ => const [],
    };
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.report});

  final RecordingDiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    final ok = report.verdict == RecordingVerdict.working;
    return LpCard(
      color: ok ? AppColors.foam : AppColors.warningSurface,
      borderColor: ok ? AppColors.iceCold : AppColors.warningBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: ok ? AppColors.greenHaze : AppColors.tahitiGold,
              ),
              const AppGap(AppSpacing.xs, axis: Axis.horizontal),
              Expanded(
                child: Text(
                  report.headline,
                  style: AppText.body14.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ok ? AppColors.greenHaze : AppColors.warningDark,
                  ),
                ),
              ),
            ],
          ),
          const AppGap(AppSpacing.xs),
          Text(
            report.action,
            style: AppText.body13.copyWith(
              color: ok ? AppColors.greenHaze : AppColors.warningText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Always visible (not tied to a specific verdict) — the automatic in-call
/// ask for battery-optimization/MIUI-autostart exemption fires at most once
/// per app process, with no way back in if the telecaller dismissed it, and
/// this is a very plausible thing to dismiss mid-call before understanding
/// why it matters. This is the missing "ask me again" entry point.
class _BackgroundPermissionsCard extends StatelessWidget {
  const _BackgroundPermissionsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      child: Row(
        children: [
          const Icon(
            Icons.battery_alert_outlined,
            size: 18,
            color: AppColors.schooner,
          ),
          const AppGap(AppSpacing.sm, axis: Axis.horizontal),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Background running',
                  style: AppText.body14.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Some phones (Xiaomi, Oppo, Vivo) kill the call overlay '
                  "mid-call unless it's allowed to run in the background. If "
                  "you dismissed that prompt before, you can ask again here.",
                  style: AppText.caption11.copyWith(color: AppColors.schooner),
                ),
              ],
            ),
          ),
          const AppGap(AppSpacing.xs, axis: Axis.horizontal),
          OutlinedButton(onPressed: onTap, child: const Text('Check')),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.report});

  final RecordingDiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    return LpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DEVICE', style: AppText.label11),
          const AppGap(AppSpacing.xs),
          _Row(
            label: 'Phone',
            value: [
              report.manufacturer,
              report.model,
            ].where((v) => v != null && v.isNotEmpty).join(' '),
          ),
          _Row(
            label: 'Android',
            value: report.sdkInt == null
                ? (report.osVersion ?? 'unknown')
                : '${report.osVersion ?? 'Android'} (API ${report.sdkInt})',
          ),
          _Row(label: 'File access', value: _accessLabel(report.accessLevel)),
          if (report.allFilesUnavailable)
            _Row(
              label: 'All files access',
              value: 'Blocked by Android (app not installed from Play Store)',
            ),
        ],
      ),
    );
  }

  static String _accessLabel(StorageAccessLevel level) => switch (level) {
    StorageAccessLevel.allFiles => 'All files',
    StorageAccessLevel.mediaAudio => 'Music and audio only',
    StorageAccessLevel.legacy => 'Storage (legacy)',
    StorageAccessLevel.none => 'None',
  };
}

class _FoldersCard extends StatelessWidget {
  const _FoldersCard({required this.report});

  final RecordingDiagnosticsReport report;

  @override
  Widget build(BuildContext context) {
    final existing = report.existingDirs;
    return LpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RECORDING FOLDERS', style: AppText.label11),
          const AppGap(AppSpacing.xs),
          if (existing.isEmpty)
            Text(
              'None of the ${report.dirs.length} known folders exist on this '
              'phone.',
              style: AppText.body13.copyWith(color: AppColors.schooner),
            )
          else
            for (final dir in existing) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Trim the storage prefix every path shares — it costs a
                      // line of wrapping on a phone and says nothing.
                      dir.path.replaceFirst('/storage/emulated/0/', ''),
                      style: AppText.mono(size: 11, color: AppColors.merlin),
                    ),
                    const AppGap(2),
                    Text(
                      !dir.readable
                          ? 'Cannot be opened by this app'
                          : dir.audioFiles == 0
                          ? 'Readable, no audio files'
                          : '${dir.audioFiles} audio file'
                                '${dir.audioFiles == 1 ? '' : 's'}'
                                '${dir.newestAudioAge == null ? '' : ' · newest ${_age(dir.newestAudioAge!)}'}',
                      style: AppText.caption11.copyWith(
                        color: dir.readable
                            ? AppColors.schooner
                            : AppColors.alizarin,
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  static String _age(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: AppText.body13.copyWith(color: AppColors.schooner),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'unknown' : value,
              style: AppText.body13.copyWith(color: AppColors.zeus),
            ),
          ),
        ],
      ),
    );
  }
}
