import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../core/api/api_exception.dart';
import '../data/lead_repository.dart';
import '../models/call_recording.dart';
import '../models/lead.dart';
import '../services/local_upload_ledger.dart';
import '../services/local_upload_outbox.dart';
import '../services/upload_error_copy.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';
import 'call_detail_screen.dart';

/// Where the picked recording is in the upload → transcribe → analyse flow.
enum _UploadPhase { idle, uploading, processing, done, error }

class AddOutboundLeadScreen extends ConsumerStatefulWidget {
  const AddOutboundLeadScreen({super.key});

  /// Show as a modal bottom sheet instead of a full-screen route.
  static Future<void> show(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      useSafeArea: true,
      builder: (ctx) => UncontrolledProviderScope(
        container: container,
        child: const AddOutboundLeadScreen(),
      ),
    );
  }

  @override
  ConsumerState<AddOutboundLeadScreen> createState() =>
      _AddOutboundLeadScreenState();
}

class _AddOutboundLeadScreenState extends ConsumerState<AddOutboundLeadScreen> {
  _UploadPhase _phase = _UploadPhase.idle;
  String? _fileName;
  String _stageLabel = '';
  String? _error;
  List<TranscriptTurn> _turns = const [];
  String? _verdict;
  List<String> _keyPoints = const [];
  bool _saving = false;
  DateTime _callDate = DateTime.now();
  String? _callId;
  late final TextEditingController _phoneController;

  /// True when [_error] came from awaitProcessing giving up on a
  /// slow-but-still-running analysis, rather than a real upload failure.
  /// "Retry" in that case must resume polling the SAME [_callId] — mirrors
  /// UploadRecordingSheet's identical fix; this screen had no equivalent, so
  /// its only retry path re-uploaded (and re-billed) a call that may well
  /// still finish on its own.
  bool _errorIsTimeout = false;

  /// True from the moment "upload a recording" is tapped until the OS file
  /// picker returns. `_phase` only flips to `uploading` once the picker's
  /// own `await` resolves — a fast double-tap in that gap could open two
  /// concurrent picker/upload attempts, since both taps would still see
  /// `_phase == idle`. This closes that gap with a guard set synchronously,
  /// before the first `await`.
  bool _picking = false;

  /// Once a recording has been uploaded, the backend has already resolved a
  /// contact for it from whatever name/phone were on screen at that moment.
  /// Editing either field after that would let `createLead()` derive a
  /// different contact_key than the upload did, silently attaching the call
  /// to the wrong lead — so lock identity fields as soon as a call exists.
  bool get _identityLocked => _callId != null;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(
      text: localPhoneDigits(ref.read(outboundLeadDraftProvider).phone),
    );
    _phoneController.addListener(() {
      ref
          .read(outboundLeadDraftProvider.notifier)
          .updatePhone('+91${_phoneController.text.trim()}');
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

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

  // ── Recording upload → transcript ────────────────────────────────────────

  /// Dropzone tap handler. After a successful upload the dropzone reads "Tap
  /// to replace" — tapping it used to silently start a second upload (and a
  /// second call_id/paid pipeline run) rather than actually replacing
  /// anything, since the first call is never deleted. Confirm first so that's
  /// a deliberate choice, not an accidental double-tap.
  Future<void> _onDropzoneTap() async {
    if (_phase == _UploadPhase.done) {
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
    await _pickAndUpload();
  }

  Future<void> _pickAndUpload() async {
    if (_phase == _UploadPhase.uploading ||
        _phase == _UploadPhase.processing ||
        _picking) {
      return; // already in flight
    }

    // Name + a valid phone must be filled before upload so the call links to
    // the right lead, and so the identity fields can be locked afterward
    // (see `_identityLocked`) instead of letting them silently diverge from
    // what the backend already resolved this recording's contact from.
    final draftCheck = ref.read(outboundLeadDraftProvider);
    if (draftCheck.name.trim().isEmpty) {
      _toast('Enter lead name before uploading a recording');
      return;
    }
    if (_phoneController.text.trim().length != 10) {
      _toast(
        'Enter a valid 10-digit phone number before uploading a recording',
      );
      return;
    }

    _picking = true;
    final PlatformFile? pickedFile;
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
      pickedFile = picked?.files.single;
    } finally {
      _picking = false;
    }
    final path = pickedFile?.path;
    if (path == null) return; // cancelled

    setState(() {
      _fileName = pickedFile!.name;
      _phase = _UploadPhase.uploading;
      _stageLabel = 'Uploading…';
      _error = null;
      _turns = const [];
      _verdict = null;
      _keyPoints = const [];
    });

    final repo = ref.read(leadRepositoryProvider);
    final draft = ref.read(outboundLeadDraftProvider);
    final phone = draft.phone.trim().isEmpty ? null : draft.phone.trim();
    final source = draft.source.trim().isEmpty ? null : draft.source.trim();
    String? callId;
    try {
      callId = await repo.uploadRecording(
        File(path),
        name: draft.name.trim(),
        phone: phone,
        source: source,
        callDate: _callDate,
        captureSource: 'manual_upload',
      );
      if (!mounted) return;
      setState(() {
        _callId = callId;
        _phase = _UploadPhase.processing;
        _stageLabel = 'Transcribing…';
      });

      // Recognized by a later auto-capture scan of this same file so it
      // isn't silently re-uploaded (and re-billed) a second time.
      unawaited(
        ref
            .read(localUploadLedgerProvider)
            .remember(CallRecording.fromFile(File(path)), callId),
      );
      unawaited(ref.read(localUploadOutboxProvider).remove(path));

      await _awaitAndFinish(callId);
      // A call now exists for this contact — refresh the inbox.
      ref.read(leadsProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      if (callId == null && phone != null) {
        // The upload itself never reached the server — queue it for
        // automatic retry. No local lead exists yet at this point (this
        // screen creates one only when "Save Lead" is tapped), so the phone
        // number is used as the outbox's tracking key — the backend resolves
        // the same contact from it regardless, since no contactKey override
        // is sent here either way. Skipped when there's no phone at all:
        // without one, a retry couldn't resolve to any contact either.
        unawaited(
          ref
              .read(localUploadOutboxProvider)
              .enqueue(
                OutboxEntry(
                  leadId: phone,
                  path: path,
                  name: draft.name.trim(),
                  phone: phone,
                  source: source,
                  callDateIso: _callDate.toIso8601String(),
                  captureSource: 'manual_upload',
                ),
              ),
        );
      }
      setState(() {
        _phase = _UploadPhase.error;
        _error = describeUploadError(e);
        _errorIsTimeout = e is ApiException && e.isTimeout;
      });
    }
  }

  /// Polls processing status through to completion for an already-uploaded
  /// [callId] and loads its transcript/analysis. Split out so a timed-out
  /// wait (see [_errorIsTimeout]) can be retried by resuming the wait on the
  /// same call instead of uploading the file all over again.
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
      _phase = _UploadPhase.done;
      _stageLabel = 'Done';
    });
  }

  /// "Retry" after a still-processing timeout: resumes waiting on the same
  /// [_callId] rather than re-uploading, since the original upload is likely
  /// still being transcribed/analysed by the backend in the background.
  Future<void> _resumeAwaiting() async {
    final callId = _callId;
    if (callId == null ||
        _phase == _UploadPhase.uploading ||
        _phase == _UploadPhase.processing) {
      return;
    }
    setState(() {
      _phase = _UploadPhase.processing;
      _error = null;
      _errorIsTimeout = false;
    });
    try {
      await _awaitAndFinish(callId);
      ref.read(leadsProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UploadPhase.error;
        _error = describeUploadError(e);
        _errorIsTimeout = e is ApiException && e.isTimeout;
      });
    }
  }

  static String _stageWord(String key) {
    switch (key) {
      case 'transcribe':
        return 'Transcribing';
      case 'analyse':
        return 'Analysing';
      case 'done':
        return 'Done';
      default:
        return 'Processing';
    }
  }

  // ── Save lead ────────────────────────────────────────────────────────────

  Future<String?> _createLead() async {
    // Synchronous guard checked before the first `await`, so "Save Lead" and
    // "Save & Call" tapped in the same frame can't both pass this check and
    // create two leads — `_saving` only becomes true once `setState` below
    // actually runs, which is too late to catch a same-frame double-tap.
    if (_saving) return null;
    final draft = ref.read(outboundLeadDraftProvider);
    if (draft.name.trim().isEmpty) {
      _toast('Name is required');
      return null;
    }
    if (_phoneController.text.trim().length != 10) {
      _toast('Enter a valid 10-digit phone number');
      return null;
    }
    setState(() => _saving = true);
    try {
      final key = await ref.read(leadRepositoryProvider).createLead(draft);
      ref.read(leadsProvider.notifier).refresh();
      return key;
    } on ApiException catch (e) {
      if (e.isConflict) {
        // The number is already a lead. The server's message names it and
        // whoever owns it, so it's shown verbatim — far more useful than
        // "could not save". The banner is refreshed too, so the telecaller
        // gets the tap-through to that lead even when the debounced probe
        // never ran (typed fast, or offline while typing).
        unawaited(ref.read(outboundLeadDraftProvider.notifier).refreshDedupe());
        _toast(e.detail ?? 'This number is already in your leads.');
        return null;
      }
      _toast(e.detail ?? 'Could not save lead. Try again.');
      return null;
    } catch (e) {
      _toast('Could not save lead: $e');
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveLead() async {
    final key = await _createLead();
    if (key != null && mounted) {
      if (_phase == _UploadPhase.done && _callId != null) {
        // Recording was uploaded and analysed — jump straight to its Score
        // tab, same as the live-call flow shows immediately after hanging
        // up (PostCallScreen), instead of leaving the telecaller to find
        // this call in the lead's history and tap into it themselves.
        final name = ref.read(outboundLeadDraftProvider).name.trim();
        _closeAndPush(
          '/leads/$key/calls/$_callId',
          extra: CallDetailArgs(
            leadName: name,
            calledAt: _callDate,
            initialTab: 1,
          ),
        );
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _saveAndCall() async {
    final key = await _createLead();
    if (key != null && mounted) {
      _closeAndPush('/leads/$key');
    }
  }

  /// Close the add-lead sheet, then push the destination above the existing
  /// home route. Using `go()` here replaced `/home`, leaving Lead Detail with
  /// no route to pop and making both the UI and Android back buttons appear
  /// broken. Capture the router before closing because this sheet's context is
  /// disposed as soon as it pops.
  void _closeAndPush(String location, {Object? extra}) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.push(location, extra: extra);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(outboundLeadDraftProvider);
    final controller = ref.read(outboundLeadDraftProvider.notifier);
    final busy =
        _phase == _UploadPhase.uploading || _phase == _UploadPhase.processing;

    // Bottom-sheet container — showModalBottomSheet handles the barrier/backdrop.
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
        maxWidth: 480,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x38111827),
            blurRadius: 18,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
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
                  style: AppText.body14.copyWith(color: AppColors.schooner),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                20,
                17,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              children: [
                FormShell(
                  label: 'Name',
                  required: true,
                  child: LpTextField(
                    value: draft.name,
                    onChanged: controller.updateName,
                    enabled: !_identityLocked,
                  ),
                ),
                const AppGap.md(),
                FormShell(
                  label: 'Phone Number',
                  required: true,
                  optionalText: _identityLocked
                      ? '(locked — matches the uploaded call)'
                      : null,
                  child: LpPhoneField(
                    controller: _phoneController,
                    enabled: !_identityLocked,
                  ),
                ),
                if (draft.hasDuplicate) ...[
                  const AppGap.xs(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: draft.dedupeContactKey == null
                        ? null
                        : () =>
                              _closeAndPush('/leads/${draft.dedupeContactKey}'),
                    child: Container(
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
                                text: draft.dedupeOwnerName == null
                                    ? 'This number is already a lead, so it '
                                          'can\'t be added again. '
                                    : 'This number is already a lead assigned '
                                          'to ${draft.dedupeOwnerName}, so it '
                                          'can\'t be added again. ',
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
                  child: _SourceDropdown(
                    value: draft.source,
                    onChanged: controller.updateSource,
                  ),
                ),
                const AppGap.md(),
                FormShell(
                  label: 'Call Recording',
                  optionalText: '(optional)',
                  child: _RecordingDropzone(
                    phase: _phase,
                    fileName: _fileName,
                    stageLabel: _stageLabel,
                    onTap: busy ? null : _onDropzoneTap,
                  ),
                ),
                const AppGap.md(),
                FormShell(
                  label: 'Recording Date',
                  optionalText: '(when was this call?)',
                  child: GestureDetector(
                    onTap: busy ? null : _pickDate,
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
                            size: 16,
                            color: AppColors.schooner,
                          ),
                          const AppGap.sm(axis: Axis.horizontal),
                          Text(_fmtDate(_callDate), style: AppText.body14),
                          const Spacer(),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: AppColors.schooner,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_phase == _UploadPhase.done) ...[
                  const AppGap.md(),
                  _TranscriptResult(
                    turns: _turns,
                    verdict: _verdict,
                    keyPoints: _keyPoints,
                  ),
                ],
                if (_phase == _UploadPhase.error) ...[
                  const AppGap.sm(),
                  _ErrorPanel(
                    message: _error ?? 'Upload failed',
                    retryLabel: _errorIsTimeout ? 'Check again' : 'Retry',
                    isTimeout: _errorIsTimeout,
                    onRetry: _errorIsTimeout ? _resumeAwaiting : _pickAndUpload,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              14 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Row(
              children: [
                SecondaryButton(
                  label: 'Cancel',
                  onTap: _saving ? null : () => Navigator.of(context).pop(),
                ),
                const AppGap.sm(axis: Axis.horizontal),
                Expanded(
                  child: SecondaryButton(
                    label: 'Save Lead',
                    onTap: _saveLead,
                    loading: _saving,
                  ),
                ),
                const AppGap.sm(axis: Axis.horizontal),
                Expanded(
                  child: PrimaryButton(
                    label: 'Save & Call',
                    icon: Icons.phone_outlined,
                    color: AppColors.greenHaze,
                    onTap: _saveAndCall,
                    loading: _saving,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Source picker backed by the default [LeadSource] options.
class _SourceDropdown extends StatelessWidget {
  const _SourceDropdown({required this.value, required this.onChanged});

  /// The wire value (e.g. "meta") currently selected, or empty when unset.
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final matches = LeadSource.values.where((s) => s.value == value);
    final selected = matches.isEmpty ? null : matches.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.westar),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LeadSource>(
          value: selected,
          isExpanded: true,
          hint: Text(
            'Select a source',
            style: AppText.body14.copyWith(color: AppColors.schooner),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.schooner,
          ),
          style: AppText.body14.copyWith(color: AppColors.zeus),
          borderRadius: BorderRadius.circular(10),
          items: [
            for (final source in LeadSource.values)
              DropdownMenuItem(value: source, child: Text(source.displayName)),
          ],
          onChanged: (s) {
            if (s != null) onChanged(s.value);
          },
        ),
      ),
    );
  }
}

/// The upload tile: idle prompt, in-flight spinner, or picked-file label.
class _RecordingDropzone extends StatelessWidget {
  const _RecordingDropzone({
    required this.phase,
    required this.fileName,
    required this.stageLabel,
    required this.onTap,
  });

  final _UploadPhase phase;
  final String? fileName;
  final String stageLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final busy =
        phase == _UploadPhase.uploading || phase == _UploadPhase.processing;
    final done = phase == _UploadPhase.done;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.pampas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.westar),
        ),
        child: Center(
          child: busy
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
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
                      'Keep this screen open',
                      style: AppText.caption11.copyWith(
                        color: AppColors.schooner,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      done ? Icons.check_circle : Icons.upload,
                      size: 28,
                      color: done ? AppColors.greenHaze : AppColors.schooner,
                    ),
                    const AppGap.xs(),
                    Text(
                      fileName ?? 'Upload previous call recording',
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
                          : '.mp3, .wav, .m4a, .ogg, .opus - max 100 MB',
                      style: AppText.caption11.copyWith(
                        color: AppColors.schooner,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Inline transcript + AI verdict shown after processing completes.
class _TranscriptResult extends StatelessWidget {
  const _TranscriptResult({
    required this.turns,
    required this.verdict,
    required this.keyPoints,
  });

  final List<TranscriptTurn> turns;
  final String? verdict;
  final List<String> keyPoints;

  @override
  Widget build(BuildContext context) {
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: turns.length,
              separatorBuilder: (_, _) => const AppGap.xs(),
              itemBuilder: (_, i) {
                final t = turns[i];
                final isAgent = t.speaker.toUpperCase() == 'AGENT';
                return Align(
                  alignment: isAgent
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 300),
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
                        Text(t.text, style: AppText.body14),
                      ],
                    ),
                  ),
                );
              },
            ),
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

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Retry',
    this.isTimeout = false,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  /// True for "still processing, just slow" — styled as a heads-up rather
  /// than a failure, since nothing actually broke. Mirrors
  /// UploadRecordingSheet's _ErrorRow.
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
