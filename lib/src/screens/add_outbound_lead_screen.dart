import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../core/api/api_exception.dart';
import '../data/lead_repository.dart';
import '../models/lead.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/leadpilot_widgets.dart';
import 'call_detail_screen.dart';

/// Where the picked recording is in the upload → transcribe → analyse flow.
enum _UploadPhase { idle, uploading, processing, done, error }

class AddOutboundLeadScreen extends ConsumerStatefulWidget {
  const AddOutboundLeadScreen({super.key});

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

  Future<void> _pickAndUpload() async {
    if (_phase == _UploadPhase.uploading || _phase == _UploadPhase.processing) {
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
    if (path == null) return; // cancelled

    setState(() {
      _fileName = picked!.files.single.name;
      _phase = _UploadPhase.uploading;
      _stageLabel = 'Uploading…';
      _error = null;
      _turns = const [];
      _verdict = null;
      _keyPoints = const [];
    });

    final repo = ref.read(leadRepositoryProvider);
    final draft = ref.read(outboundLeadDraftProvider);
    try {
      final callId = await repo.uploadRecording(
        File(path),
        name: draft.name.trim(),
        phone: draft.phone.trim().isEmpty ? null : draft.phone.trim(),
        source: draft.source.trim().isEmpty ? null : draft.source.trim(),
        callDate: _callDate,
      );
      if (!mounted) return;
      setState(() {
        _callId = callId;
        _phase = _UploadPhase.processing;
        _stageLabel = 'Transcribing…';
      });

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
      // A call now exists for this contact — refresh the inbox.
      ref.read(leadsProvider.notifier).refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UploadPhase.error;
        _error = _describeUploadError(e);
      });
    }
  }

  static String _describeUploadError(Object e) {
    if (e is ApiException) {
      if (e.isNetworkError) {
        return 'Network error — check your connection and retry.';
      }
      if (e.isUnauthorized) return 'Session expired — please log in again.';
      if (e.isServerError) {
        return 'Server error while processing the recording. Please retry.';
      }
      return e.message;
    }
    return e.toString();
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
        context.go(
          '/leads/$key/calls/$_callId',
          extra: CallDetailArgs(
            leadName: name,
            calledAt: _callDate,
            initialTab: 1,
          ),
        );
      } else {
        context.pop();
      }
    }
  }

  Future<void> _saveAndCall() async {
    final key = await _createLead();
    if (key != null && mounted) context.go('/leads/$key');
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
                              : () => context.go(
                                  '/leads/${draft.dedupeContactKey}',
                                ),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.warningSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.warningBorder,
                              ),
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
                          onTap: busy ? null : _pickAndUpload,
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
                                Text(
                                  _fmtDate(_callDate),
                                  style: AppText.body14,
                                ),
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
                          onRetry: _pickAndUpload,
                        ),
                      ],
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
                        onTap: _saving ? null : () => context.pop(),
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
          ),
        ),
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
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.redSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.redBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.alizarin),
          const AppGap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              message,
              style: AppText.body14.copyWith(color: AppColors.alizarin),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
