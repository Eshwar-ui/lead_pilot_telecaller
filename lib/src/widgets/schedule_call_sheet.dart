import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/lead.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'leadpilot_widgets.dart';

/// Pure: builds the [FollowUpTask] and its overdue/due-today classification
/// from the picked date/time and note, given [now] explicitly rather than
/// reading `DateTime.now()` internally — pulled out of
/// [_ScheduleCallSheetState._save] so this date/time math (and the
/// overdue -> "skip the device notification" branch it feeds) can be unit
/// tested deterministically instead of only through a widget pump.
({FollowUpTask task, bool isOverdue, DateTime scheduledAt}) buildFollowUpTask({
  required DateTime date,
  required TimeOfDay time,
  required String noteText,
  required Lead lead,
  required String id,
  required DateTime now,
}) {
  final scheduledAt = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  final isToday =
      scheduledAt.year == now.year &&
      scheduledAt.month == now.month &&
      scheduledAt.day == now.day;
  final isOverdue = scheduledAt.isBefore(now);
  final trimmedNote = noteText.trim();
  final task = FollowUpTask(
    id: id,
    taskText: trimmedNote.isEmpty
        ? 'Follow-up call with ${lead.name}'
        : trimmedNote,
    leadName: lead.name,
    phone: lead.phone,
    leadId: lead.id,
    status: isOverdue ? FollowUpStatus.overdue : FollowUpStatus.pending,
    dueLabel: DateFormat('dd MMM · hh:mm a').format(scheduledAt),
    dueToday: isToday,
    scheduledAt: scheduledAt,
    note: trimmedNote.isEmpty ? null : trimmedNote,
  );
  return (task: task, isOverdue: isOverdue, scheduledAt: scheduledAt);
}

class ScheduleCallSheet extends ConsumerStatefulWidget {
  const ScheduleCallSheet({
    super.key,
    required this.lead,
    this.defaultDaysAhead = 1,
    this.initialNote,
  });

  final Lead lead;
  final int defaultDaysAhead;

  /// Pre-fills the note field — e.g. a call's "next step" text, so acting on
  /// it from Call Detail doesn't require retyping it as a follow-up note.
  final String? initialNote;

  static Future<void> show(
    BuildContext context,
    Lead lead, {
    int daysAhead = 1,
    String? initialNote,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ScheduleCallSheet(
      lead: lead,
      defaultDaysAhead: daysAhead,
      initialNote: initialNote,
    ),
  );

  @override
  ConsumerState<ScheduleCallSheet> createState() => _ScheduleCallSheetState();
}

class _ScheduleCallSheetState extends ConsumerState<ScheduleCallSheet> {
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now().add(Duration(days: widget.defaultDaysAhead));
    if (widget.initialNote != null) _noteController.text = widget.initialNote!;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final id =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      final built = buildFollowUpTask(
        date: _date,
        time: _time,
        noteText: _noteController.text,
        lead: widget.lead,
        id: id,
        now: DateTime.now(),
      );

      await ref.read(followUpsProvider.notifier).schedule(built.task);

      // Schedule a device notification at the chosen time.
      if (!built.isOverdue) {
        await NotificationService.instance.scheduleFollowUp(
          notifId: NotificationService.notifIdFor(id),
          title: 'Follow-up: ${widget.lead.name}',
          body: built.task.taskText,
          scheduledAt: built.scheduledAt,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE, dd MMM yyyy');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
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
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.westar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Schedule Call',
            style: AppText.display20.copyWith(fontSize: 18),
          ),
          Text(
            widget.lead.name,
            style: AppText.body13.copyWith(color: AppColors.schooner),
          ),
          const AppGap.lg(),
          Row(
            children: [
              Expanded(
                child: ScheduleCallPickerTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: dateFmt.format(_date),
                  onTap: _pickDate,
                ),
              ),
              const AppGap.sm(axis: Axis.horizontal),
              Expanded(
                child: ScheduleCallPickerTile(
                  icon: Icons.access_time_outlined,
                  label: 'Time',
                  value: _time.format(context),
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const AppGap.md(),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add a note (optional)',
              hintStyle: AppText.body13.copyWith(color: AppColors.tide),
              filled: true,
              fillColor: AppColors.pampas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.westar),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.westar),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const AppGap.lg(),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Schedule Call',
              icon: Icons.calendar_today_outlined,
              onTap: _save,
              loading: _saving,
            ),
          ),
        ],
      ),
    );
  }
}

class ScheduleCallPickerTile extends StatelessWidget {
  const ScheduleCallPickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.pampas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.westar),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.blueRibbon),
            const AppGap.xs(axis: Axis.horizontal),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.label11),
                  Text(
                    value,
                    style: AppText.body13.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
