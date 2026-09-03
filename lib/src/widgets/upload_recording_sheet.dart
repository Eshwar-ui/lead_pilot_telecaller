import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../core/api/api_exception.dart';
import '../data/lead_repository.dart';
import '../models/call_recording.dart';
import '../models/lead.dart';
import '../screens/call_detail_screen.dart';
import '../services/call_recording_service.dart';
import '../services/local_upload_ledger.dart';
import '../services/local_upload_outbox.dart';
import '../services/upload_error_copy.dart';
import '../state/call_capture.dart' show callRecordingServiceProvider;
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'leadpilot_widgets.dart';

enum _UpPhase { idle, uploading, processing, done, error }

/// Bottom sheet for uploading a past call recording to an **existing** lead.
///
/// Opens with [show]; on completion calls `leadsProvider.enrich(leadId)` so
/// the lead detail screen refreshes and shows the new call in history.
class UploadRecordingSheet extends ConsumerStatefulWidget {
  const UploadRecordingSheet._({required this.leadId, required this.leadName});

  final String leadId;
  final String leadName;

  static Future<void> show(BuildContext context, Lead lead) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) =>
            UploadRecordingSheet._(leadId: lead.id, leadName: lead.name),
      );

  @override
  ConsumerState<UploadRecordingSheet> createState() =>
      _UploadRecordingSheetState();
}

class _UploadRecordingSheetState extends ConsumerState<UploadRecordingSheet> {
  _UpPhase _phase = _UpPhase.idle;
  String? _fileName;
  String _stageLabel = '';
  String? _error;
  List<TranscriptTurn> _turns = const [];
  String? _verdict;
  List<String> _keyPoints = const [];
  DateTime _callDate = DateTime.now();
  String? _callId;

  /// True from the moment "Browse Files" is tapped until the OS file picker
  /// returns. `_busy` (derived from `_phase`) only flips to true once
  /// `_uploadPath` starts, well after the picker's own `await` resolves — a
  /// fast double-tap in that gap could open two concurrent picker/upload
  /// attempts, since both taps would see `_busy == false`. This closes that
  /// gap with a guard that's set synchronously, before the first `await`.
  bool _picking = false;

  // ── Auto-find state ─────────────────────────────────────────────────────
  bool _finding = false;
  List<CallRecording> _foundRecordings = const [];
  String? _findMessage;
  bool _findPermissionBlocked = false;

  /// Path + name of whatever was last selected (auto-found or browsed), so
  /// the error state's "Retry" button re-uploads the same file instead of
  /// forcing the telecaller to find/browse it all over again.
  String? _lastPath;
  String? _lastFileName;

  /// True when the current [_error] came from [LeadRepository.awaitProcessing]
  /// giving up on a slow-but-still-running analysis, rather than a real
  /// upload/processing failure. "Retry" in that case must resume polling the
  /// SAME [_callId] — re-uploading would pay for transcription+analysis a
  /// second time on a call whose first run may well still finish on its own.
  bool _errorIsTimeout = false;

  bool get _busy =>
      _phase == _UpPhase.uploading || _phase == _UpPhase.processing;

  String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _callDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _callDate = picked);
  }

  Lead? get _lead {
    final matches = ref.read(leadsProvider).where((l) => l.id == widget.leadId);
    return matches.isEmpty ? null : matches.first;
  }

  /// Scans the same OEM call-recording folders the live-call auto-capture
  /// flow reads (see [CallRecordingService]), instead of making the
  /// telecaller hunt through a generic file browser for a folder most phones
  /// bury several levels deep. Shows every match it finds so they can pick
  /// the right one for the call date selected above — auto-capture only
  /// needs the single newest file, but a past call being uploaded manually
  /// could be any of several recent recordings.
  Future<void> _findRecordings() async {
    if (_busy || _finding) return;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() {
        _findMessage =
            "Automatic search isn't available on this device — "
            'use Browse Files instead.';
        _findPermissionBlocked = false;
      });
      return;
    }

    setState(() {
      _finding = true;
      _findMessage = null;
      _findPermissionBlocked = false;
      _foundRecordings = const [];
    });

    final service = ref.read(callRecordingServiceProvider);
    final permission = await service.ensureStoragePermission();
    if (!mounted) return;

    switch (permission.result) {
      case StoragePermissionResult.unsupported:
        setState(() {
          _finding = false;
          _findMessage = 'Call recording capture is available on Android only.';
        });
        return;
      case StoragePermissionResult.denied:
        setState(() {
          _finding = false;
          _findMessage =
              'Allow access to music and audio so recordings can be found.';
        });
        return;
      case StoragePermissionResult.permanentlyDenied:
        setState(() {
          _finding = false;
          _findPermissionBlocked = true;
          _findMessage =
              'Open Settings → Permissions and allow "Music and '
              'audio" for LeadPilot.';
        });
        return;
      case StoragePermissionResult.granted:
        break;
    }

    final recordings = await service.listRecentRecordings(
      phoneHint: _lead?.phone,
    );
    if (!mounted) return;
    setState(() {
      _finding = false;
      _foundRecordings = recordings;
      _findMessage = recordings.isEmpty
          ? 'No recordings found in common folders. Try Browse Files below.'
          : null;
    });
  }

  /// Dropzone tap handler. After a successful upload the dropzone reads "Tap
  /// to replace" — tapping it used to silently start a second upload (and a
  /// second call_id/paid pipeline run) rather than actually replacing
  /// anything, since the first call is never deleted. Confirm first so that's
  /// a deliberate choice, not an accidental double-tap.
  Future<void> _onDropzoneTap() async {
    if (_phase == _UpPhase.done) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload a different recording?'),
          content: const Text(
            "This call's transcript and score are already saved. Uploading "
            'another file creates a SEPARATE call — it does not replace this '
            'one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Upload Another'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _browseAndUpload();
  }

  Future<void> _browseAndUpload() async {
    if (_busy || _picking) return;
    _picking = true;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // 'opus' covers WhatsApp voice notes, which are shared as .opus files.
        allowedExtensions: [
          'mp3',
          'wav',
          'm4a',
          'ogg',
          'opus',
          'aac',
          'mpeg',
          'mp4',
        ],
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      await _uploadPath(path, picked!.files.single.name);
    } finally {
      _picking = false;
    }
  }

  Future<void> _uploadPath(String path, String fileName) async {
    if (_busy) return;

    _lastPath = path;
    _lastFileName = fileName;
    setState(() {
      _fileName = fileName;
      _phase = _UpPhase.uploading;
      _stageLabel = 'Uploading…';
      _error = null;
      _errorIsTimeout = false;
      _turns = const [];
      _verdict = null;
      _keyPoints = const [];
      // The picker list served its purpose once a file is chosen.
      _foundRecordings = const [];
    });

    final repo = ref.read(leadRepositoryProvider);
    // Pull the lead's phone/source so the manual upload keys on phone (the
    // backend's canonical key) and records the real acquisition source, matching
    // the auto-capture path — previously the sheet sent neither.
    final lead = _lead;
    String? callId;
    try {
      callId = await repo.uploadRecording(
        File(path),
        name: widget.leadName,
        phone: lead?.phone,
        source: lead?.source.name,
        contactKey: widget.leadId,
        callDate: _callDate,
        captureSource: 'manual_upload',
      );
      if (!mounted) return;
      setState(() {
        _callId = callId;
        _phase = _UpPhase.processing;
        _stageLabel = 'Transcribing…';
      });

      // Recognized by a later auto-capture scan of this same file so it isn't
      // silently re-uploaded (and re-billed) a second time, and clear any
      // stale queued retry left over from an earlier failed attempt at it.
      unawaited(
        ref
            .read(localUploadLedgerProvider)
            .remember(CallRecording.fromFile(File(path)), callId),
      );
      unawaited(ref.read(localUploadOutboxProvider).remove(path));

      await _awaitAndFinish(callId);
    } catch (e) {
      if (!mounted) return;
      if (callId == null) {
        // The upload itself never reached the server — queue it for
        // automatic retry on the next app resume/reconnect instead of losing
        // the recording the moment this sheet is closed. (A failure AFTER
        // callId was assigned means the upload succeeded and only the
        // subsequent wait failed — see _errorIsTimeout / _resumeAwaiting,
        // which resumes polling the same call instead of re-uploading it.)
        unawaited(
          ref
              .read(localUploadOutboxProvider)
              .enqueue(
                OutboxEntry(
                  leadId: widget.leadId,
                  path: path,
                  name: widget.leadName,
                  phone: lead?.phone,
                  source: lead?.source.name,
                  contactKey: widget.leadId,
                  callDateIso: _callDate.toIso8601String(),
                  captureSource: 'manual_upload',
                ),
              ),
        );
      }
      setState(() {
        _phase = _UpPhase.error;
        _error = describeUploadError(e);
        _errorIsTimeout = e is ApiException && e.isTimeout;
      });
    }
  }

  /// Polls processing status through to completion for an already-uploaded
  /// [callId] and loads its transcript/analysis. Split out of [_uploadPath]
  /// so a timed-out wait (see [_errorIsTimeout]) can be retried by resuming
  /// the wait on the same call instead of uploading the file all over again.
  Future<void> _awaitAndFinish(String callId) async {
    final repo = ref.read(leadRepositoryProvider);
    await repo.awaitProcessing(
      callId,
      timeout: const Duration(minutes: 10),
      onTick: (s) {
        if (!mounted) return;
        setState(
          () => _stageLabel = '${_stageWord(s.currentStage)}… ${s.percent}%',
        );
      },
    );

    final turns = (await repo.transcript(callId)).turns;
    final analysis = await repo.leadAnalysis(callId);
    if (!mounted) return;
    setState(() {
      _turns = turns;
      _verdict = analysis['lead_verdict']?.toString();
      _keyPoints = (analysis['key_points'] is List)
          ? (analysis['key_points'] as List).map((e) => e.toString()).toList()
          : const [];
      _phase = _UpPhase.done;
      _stageLabel = 'Done';
    });
    ref.read(leadsProvider.notifier).enrich(widget.leadId);
  }

  /// "Retry" after a still-processing timeout: resumes waiting on the same
  /// [_callId] rather than re-uploading, since the original upload is likely
  /// still being transcribed/analysed by the backend in the background.
  Future<void> _resumeAwaiting() async {
    final callId = _callId;
    if (callId == null || _busy) return;
    setState(() {
      _phase = _UpPhase.processing;
      _error = null;
      _errorIsTimeout = false;
    });
    try {
      await _awaitAndFinish(callId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpPhase.error;
        _error = describeUploadError(e);
        _errorIsTimeout = e is ApiException && e.isTimeout;
      });
    }
  }

  static String _stageWord(String key) => switch (key) {
    'transcribe' => 'Transcribing',
    'analyse' => 'Analysing',
    'done' => 'Done',
    _ => 'Processing',
  };

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    // Half the screen, not "however tall the content wants to be" — this
    // sheet used to fill almost the entire screen (isScrollControlled sizes
    // it to content, and the Expanded ListView inside happily grew to fill
    // all available height). Content that overflows still scrolls inside the
    // ListView below.
    final sheetHeight = MediaQuery.of(context).size.height * 0.5;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Color(0x28111827),
            blurRadius: 18,
            offset: Offset(0, -6),
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
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload Recording', style: AppText.display20),
                      Text(
                        widget.leadName,
                        style: AppText.body14.copyWith(
                          color: AppColors.schooner,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_busy)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    color: AppColors.schooner,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // ── Date picker ───────────────────────────────────────────
                GestureDetector(
                  onTap: _busy ? null : _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.pampas,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.westar),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 15,
                          color: AppColors.schooner,
                        ),
                        const AppGap.sm(axis: Axis.horizontal),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Recording Date', style: AppText.label11),
                              Text(_fmtDate(_callDate), style: AppText.body14),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          size: 16,
                          color: AppColors.schooner,
                        ),
                      ],
                    ),
                  ),
                ),
                const AppGap.md(),
                // ── Find / pick a file ───────────────────────────────────
                if (_phase == _UpPhase.idle) ...[
                  _AutoFindSection(
                    finding: _finding,
                    message: _findMessage,
                    permissionBlocked: _findPermissionBlocked,
                    recordings: _foundRecordings,
                    leadPhone: _lead?.phone,
                    onFind: _findRecordings,
                    onOpenSettings: () =>
                        ref.read(callRecordingServiceProvider).openSettings(),
                    onPickRecording: (r) => _uploadPath(r.path, r.fileName),
                  ),
                  const AppGap.sm(),
                  Center(
                    child: TextButton(
                      onPressed: _browseAndUpload,
                      child: const Text('Or choose a file manually'),
                    ),
                  ),
                ] else
                  _Dropzone(
                    phase: _phase,
                    fileName: _fileName,
                    stageLabel: _stageLabel,
                    onTap: _busy ? null : _onDropzoneTap,
                  ),
                // ── Transcript preview ────────────────────────────────────
                if (_phase == _UpPhase.done) ...[
                  const AppGap.md(),
                  _TranscriptPreview(
                    turns: _turns,
                    verdict: _verdict,
                    keyPoints: _keyPoints,
                  ),
                ],
                // ── Error ─────────────────────────────────────────────────
                if (_phase == _UpPhase.error) ...[
                  const AppGap.sm(),
                  _ErrorRow(
                    message: _error ?? 'Upload failed',
                    retryLabel: _errorIsTimeout ? 'Check again' : 'Retry',
                    isTimeout: _errorIsTimeout,
                    onRetry: () {
                      if (_errorIsTimeout) {
                        // The upload already went through — resume waiting on
                        // it instead of paying to transcribe/analyse it again.
                        _resumeAwaiting();
                        return;
                      }
                      final path = _lastPath;
                      final name = _lastFileName;
                      if (path != null && name != null) {
                        _uploadPath(path, name);
                      } else {
                        _browseAndUpload();
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, bottomPad + 16),
            child: SizedBox(
              width: double.infinity,
              child: _phase == _UpPhase.done
                  ? PrimaryButton(
                      label: 'View Score',
                      icon: Icons.check,
                      color: AppColors.greenHaze,
                      onTap: () {
                        // Capture the router before popping — once the sheet's
                        // route is popped, this context is on its way to being
                        // deactivated and GoRouter.of(context) on a deactivated
                        // context throws.
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        // Land straight on the Score tab — same rings +
                        // breakdown the live-call flow shows immediately
                        // after hanging up (PostCallScreen's Score tab),
                        // instead of leaving the telecaller to find this
                        // call in history and tap into it themselves.
                        router.push(
                          '/leads/${widget.leadId}/calls/$_callId',
                          extra: CallDetailArgs(
                            leadName: widget.leadName,
                            calledAt: _callDate,
                            initialTab: 1,
                          ),
                        );
                      },
                    )
                  : SecondaryButton(
                      label: _busy ? 'Processing… keep open' : 'Cancel',
                      onTap: _busy ? null : () => Navigator.of(context).pop(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Auto-find ──────────────────────────────────────────────────────────────

/// Primary "find the recording for me" action — scans the device's known
/// call-recording folders (see [CallRecordingService]) and lists what it
/// finds, rather than sending the telecaller into a generic file browser to
/// hunt for a folder most OEMs bury several levels deep.
/// Whether [recording]'s filename contains [leadPhone]'s digits — `null`
/// when there's no phone to check against at all (can't judge either way).
bool? _matchesPhone(CallRecording recording, String? leadPhone) {
  final digits = CallRecordingService.phoneDigits(leadPhone);
  if (digits.isEmpty) return null;
  return CallRecordingService.fileNameDigits(recording.path).contains(digits);
}

class _AutoFindSection extends StatelessWidget {
  const _AutoFindSection({
    required this.finding,
    required this.message,
    required this.permissionBlocked,
    required this.recordings,
    required this.leadPhone,
    required this.onFind,
    required this.onOpenSettings,
    required this.onPickRecording,
  });

  final bool finding;
  final String? message;
  final bool permissionBlocked;
  final List<CallRecording> recordings;

  /// The open lead's phone, so each result can be flagged when its filename
  /// doesn't contain it — sort order alone (phone-matches first) gave no
  /// visual cue that the TOP result might still not actually be this lead's
  /// call, which is exactly how a recording gets attached to the wrong lead.
  final String? leadPhone;

  final VoidCallback onFind;
  final VoidCallback onOpenSettings;
  final ValueChanged<CallRecording> onPickRecording;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: finding ? null : onFind,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.ribbonSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.periwinkle),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: finding
                      ? const CircularProgressIndicator(strokeWidth: 2.5)
                      : const Icon(
                          Icons.manage_search,
                          color: AppColors.blueRibbon,
                        ),
                ),
                const AppGap.sm(axis: Axis.horizontal),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        finding
                            ? 'Searching this phone…'
                            : 'Find recordings automatically',
                        style: AppText.body14.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Scans the folders your dialer saves call recordings to',
                        style: AppText.caption11.copyWith(
                          color: AppColors.schooner,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!finding)
                  const Icon(Icons.chevron_right, color: AppColors.schooner),
              ],
            ),
          ),
        ),
        if (message != null) ...[
          const AppGap.sm(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warningBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.warningDark,
                ),
                const AppGap.sm(axis: Axis.horizontal),
                Expanded(
                  child: Text(
                    message!,
                    style: AppText.body13.copyWith(
                      color: AppColors.warningDark,
                    ),
                  ),
                ),
                if (permissionBlocked)
                  TextButton(
                    onPressed: onOpenSettings,
                    child: const Text('Settings'),
                  ),
              ],
            ),
          ),
        ],
        if (recordings.isNotEmpty) ...[
          const AppGap.sm(),
          Text('FOUND ON THIS PHONE', style: AppText.label11),
          const AppGap.xs(),
          for (final r in recordings) ...[
            _FoundRecordingRow(
              recording: r,
              matchesLeadPhone: _matchesPhone(r, leadPhone),
              onTap: () => onPickRecording(r),
            ),
            const AppGap.xs(),
          ],
        ],
      ],
    );
  }
}

class _FoundRecordingRow extends StatelessWidget {
  const _FoundRecordingRow({
    required this.recording,
    required this.onTap,
    this.matchesLeadPhone,
  });

  final CallRecording recording;
  final VoidCallback onTap;

  /// null = no phone to check against; true/false = filename does/doesn't
  /// contain this lead's phone digits.
  final bool? matchesLeadPhone;

  String _fmt(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${months[d.month - 1]}, '
        '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.westar),
        ),
        child: Row(
          children: [
            const Icon(Icons.audiotrack, size: 18, color: AppColors.blueRibbon),
            const AppGap.sm(axis: Axis.horizontal),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recording.fileName,
                    style: AppText.body13.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_fmt(recording.recordedAt)} · ${recording.readableSize}',
                    style: AppText.caption11.copyWith(
                      color: AppColors.schooner,
                    ),
                  ),
                  if (matchesLeadPhone == false) ...[
                    const AppGap.xxs(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 12,
                          color: AppColors.tahitiGold,
                        ),
                        const AppGap.xxs(axis: Axis.horizontal),
                        Text(
                          "Filename doesn't match this lead's number",
                          style: AppText.caption11.copyWith(
                            color: AppColors.tahitiGold,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.schooner,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dropzone ─────────────────────────────────────────────────────────────────

class _Dropzone extends StatelessWidget {
  const _Dropzone({
    required this.phase,
    required this.fileName,
    required this.stageLabel,
    required this.onTap,
  });

  final _UpPhase phase;
  final String? fileName;
  final String stageLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final busy = phase == _UpPhase.uploading || phase == _UpPhase.processing;
    final done = phase == _UpPhase.done;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.pampas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: done ? AppColors.iceCold : AppColors.westar,
          ),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: busy
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const AppGap.xs(),
                      Text(
                        stageLabel,
                        style: AppText.body14.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Keep this open',
                        style: AppText.caption11.copyWith(
                          color: AppColors.schooner,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        done ? Icons.check_circle_outline : Icons.upload_file,
                        size: 26,
                        color: done ? AppColors.greenHaze : AppColors.schooner,
                      ),
                      const AppGap.xs(),
                      Text(
                        fileName ?? 'Tap to upload recording',
                        style: AppText.body14.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        done
                            ? 'Tap to replace'
                            : '.mp3 · .wav · .m4a · .opus · max 100 MB',
                        style: AppText.caption11.copyWith(
                          color: AppColors.schooner,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Transcript preview ───────────────────────────────────────────────────────

class _TranscriptPreview extends StatelessWidget {
  const _TranscriptPreview({
    required this.turns,
    required this.verdict,
    required this.keyPoints,
  });

  final List<TranscriptTurn> turns;
  final String? verdict;
  final List<String> keyPoints;

  @override
  Widget build(BuildContext context) {
    final preview = turns.length > 6 ? turns.sublist(0, 6) : turns;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.westar),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Transcript', style: AppText.display16),
              const Spacer(),
              if (verdict != null && verdict!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.westar),
                  ),
                  child: Text(
                    verdict!,
                    style: AppText.caption11.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            '${turns.length} turns',
            style: AppText.caption11.copyWith(color: AppColors.schooner),
          ),
          const AppGap.sm(),
          for (final t in preview) ...[_Bubble(turn: t), const AppGap.xs()],
          if (turns.length > 6)
            Text(
              '+${turns.length - 6} more turns — open call detail to see all',
              style: AppText.caption11.copyWith(color: AppColors.schooner),
            ),
          if (keyPoints.isNotEmpty) ...[
            const AppGap.sm(),
            Text('AI Key Points', style: AppText.display16),
            const AppGap.xs(),
            for (final p in keyPoints)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(p, style: AppText.body14)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.turn});
  final TranscriptTurn turn;

  @override
  Widget build(BuildContext context) {
    final isAgent = turn.speaker.toUpperCase() == 'AGENT';
    return Align(
      alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 270),
        decoration: BoxDecoration(
          color: isAgent ? AppColors.white : AppColors.springWood,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.westar),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAgent ? 'You' : 'Lead',
              style: AppText.caption11.copyWith(
                color: AppColors.schooner,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(turn.text, style: AppText.body14),
          ],
        ),
      ),
    );
  }
}

// ─── Error row ────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Retry',
    this.isTimeout = false,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  /// True for "still processing, just slow" — styled as a heads-up rather
  /// than a failure, since nothing actually broke.
  final bool isTimeout;

  @override
  Widget build(BuildContext context) {
    final bg = isTimeout ? AppColors.warningSurface : AppColors.redSurface;
    final border = isTimeout ? AppColors.warningBorder : AppColors.redBorder;
    final fg = isTimeout ? AppColors.warningDark : AppColors.alizarin;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            isTimeout ? Icons.hourglass_top : Icons.error_outline,
            color: fg,
          ),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              message,
              style: AppText.body14.copyWith(color: fg),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}
