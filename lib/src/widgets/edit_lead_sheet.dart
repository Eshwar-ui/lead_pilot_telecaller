import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lead.dart';
import '../services/local_lead_override_store.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'leadpilot_widgets.dart';

/// Bottom sheet to edit a lead's core details. Edits are saved as a local
/// override (via [LeadsController.updateLead]) so they persist and show
/// everywhere the lead appears.
class EditLeadSheet extends ConsumerStatefulWidget {
  const EditLeadSheet({super.key, required this.lead});

  final Lead lead;

  static Future<void> show(BuildContext context, Lead lead) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => EditLeadSheet(lead: lead),
      );

  @override
  ConsumerState<EditLeadSheet> createState() => _EditLeadSheetState();
}

class _EditLeadSheetState extends ConsumerState<EditLeadSheet> {
  /// Canonical lead statuses — must match the labels [LeadRepository]
  /// produces from `intent_bucket` (High Intent / Follow-up / Cold / New Lead)
  /// so a chosen status round-trips instead of being overwritten on refresh.
  static const List<String> _statusOptions = [
    'New Lead',
    'High Intent',
    'Follow-up',
    'Cold',
  ];

  late final TextEditingController _name;
  late final TextEditingController _phone;
  String? _status;
  late LeadSource _source;
  late LeadTemperature _temperature;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.lead.name);
    _phone = TextEditingController(text: localPhoneDigits(widget.lead.phone));
    // Only preselect when the lead's current intent is one of the known
    // options; an empty/legacy value leaves the dropdown on its hint.
    _status = _statusOptions.contains(widget.lead.intent)
        ? widget.lead.intent
        : null;
    _source = widget.lead.source;
    _temperature = widget.lead.temperature;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    final localDigits = _phone.text.trim();
    if (localDigits.length != 10) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Enter a valid 10-digit phone number')),
        );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(leadsProvider.notifier)
          .updateLead(
            widget.lead.id,
            LeadOverride(
              name: _name.text.trim(),
              phone: '+91$localDigits',
              intent: _status,
              source: _source,
              temperature: _temperature,
            ),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Could not save changes. Try again.')),
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
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.westar,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Edit lead', style: AppText.display20.copyWith(fontSize: 18)),
            const SizedBox(height: AppSpacing.md),
            _Field(label: 'Name', controller: _name),
            const SizedBox(height: AppSpacing.md),
            Text('Phone', style: _labelStyle),
            const SizedBox(height: AppSpacing.xs),
            LpPhoneField(controller: _phone, enabled: !_saving),
            const SizedBox(height: AppSpacing.md),
            Text('Status', style: _labelStyle),
            const SizedBox(height: AppSpacing.xs),
            _StatusField(
              value: _status,
              options: _statusOptions,
              onChanged: (s) => setState(() => _status = s),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Source', style: _labelStyle),
            const SizedBox(height: AppSpacing.xs),
            _SourceField(
              value: _source,
              onChanged: (s) => setState(() => _source = s),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Temperature', style: _labelStyle),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                for (final t in LeadTemperature.values) ...[
                  Expanded(
                    child: _TempChip(
                      temperature: t,
                      selected: t == _temperature,
                      onTap: () => setState(() => _temperature = t),
                    ),
                  ),
                  if (t != LeadTemperature.values.last)
                    const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Save changes',
                icon: Icons.check,
                onTap: _save,
                loading: _saving,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static final _labelStyle = AppText.body14.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.merlin,
  );
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
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controller,
          style: AppText.body14.copyWith(fontSize: 15, color: AppColors.zeus),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.pampas,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.westar),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.blueRibbon),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusField extends StatelessWidget {
  const _StatusField({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.westar),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            'Select status',
            style: AppText.body14.copyWith(color: AppColors.schooner),
          ),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.schooner,
          ),
          style: AppText.body14.copyWith(color: AppColors.zeus),
          borderRadius: BorderRadius.circular(AppRadius.md),
          items: [
            for (final status in options)
              DropdownMenuItem(value: status, child: Text(status)),
          ],
          onChanged: (s) {
            if (s != null) onChanged(s);
          },
        ),
      ),
    );
  }
}

class _SourceField extends StatelessWidget {
  const _SourceField({required this.value, required this.onChanged});

  final LeadSource value;
  final ValueChanged<LeadSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.pampas,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.westar),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LeadSource>(
          value: value,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.schooner,
          ),
          style: AppText.body14.copyWith(color: AppColors.zeus),
          borderRadius: BorderRadius.circular(AppRadius.md),
          items: [
            for (final source in LeadSource.values)
              DropdownMenuItem(value: source, child: Text(source.displayName)),
          ],
          onChanged: (s) {
            if (s != null) onChanged(s);
          },
        ),
      ),
    );
  }
}

class _TempChip extends StatelessWidget {
  const _TempChip({
    required this.temperature,
    required this.selected,
    required this.onTap,
  });

  final LeadTemperature temperature;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = switch (temperature) {
      LeadTemperature.hot => (
        AppColors.alizarin,
        AppColors.redSurface,
        AppColors.redBorder,
      ),
      LeadTemperature.warm => (
        AppColors.tahitiGold,
        AppColors.warningSurface,
        AppColors.warningBorder,
      ),
      LeadTemperature.cold => (
        AppColors.schooner,
        AppColors.pampas,
        AppColors.westar,
      ),
    };
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? bg : AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? fg : border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          temperature.name,
          style: AppText.body13.copyWith(
            fontWeight: FontWeight.w700,
            color: selected ? fg : AppColors.schooner,
          ),
        ),
      ),
    );
  }
}
