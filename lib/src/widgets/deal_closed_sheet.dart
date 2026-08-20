import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'leadpilot_widgets.dart';

/// Result of confirming a Closed Won deal — deal value is required (it's
/// already what the web Kanban's own deal-value modal collects); list price
/// is optional and only present when the telecaller actually discounted off a
/// quoted price, letting margin (list_price - deal_value) be tracked at all
/// (PRD Layer 4-C, previously not captured anywhere in this app).
class DealClosedResult {
  const DealClosedResult({
    required this.dealValue,
    this.listPrice,
    this.discountPct,
  });

  final int dealValue;
  final int? listPrice;
  final double? discountPct;
}

/// Either a validation [error] to show the user, or the [result] to return
/// from the sheet — never both.
class DealClosedValidation {
  const DealClosedValidation.error(this.error) : result = null;
  const DealClosedValidation.ok(this.result) : error = null;

  final String? error;
  final DealClosedResult? result;
}

/// Pure form-validation + discount-math logic, pulled out of
/// [_DealClosedSheetState] so it can be unit tested directly instead of only
/// through a widget pump.
DealClosedValidation validateDealClosedInputs({
  required String dealValueText,
  required String listPriceText,
}) {
  final dealValue = int.tryParse(dealValueText.trim());
  if (dealValue == null || dealValue <= 0) {
    return const DealClosedValidation.error('Enter the final deal value');
  }
  final trimmedListPrice = listPriceText.trim();
  if (trimmedListPrice.isEmpty) {
    return DealClosedValidation.ok(DealClosedResult(dealValue: dealValue));
  }
  final listPrice = int.tryParse(trimmedListPrice);
  if (listPrice == null || listPrice <= 0) {
    return const DealClosedValidation.error('List price must be a number');
  }
  if (listPrice < dealValue) {
    return const DealClosedValidation.error(
      "List price can't be less than the deal value",
    );
  }
  final discountPct = ((listPrice - dealValue) / listPrice) * 100;
  return DealClosedValidation.ok(
    DealClosedResult(
      dealValue: dealValue,
      listPrice: listPrice,
      discountPct: discountPct,
    ),
  );
}

/// Shown when a telecaller taps the "Closed Won" pipeline stage chip.
Future<DealClosedResult?> showDealClosedSheet(BuildContext context) {
  return showModalBottomSheet<DealClosedResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _DealClosedSheet(),
  );
}

class _DealClosedSheet extends StatefulWidget {
  const _DealClosedSheet();

  @override
  State<_DealClosedSheet> createState() => _DealClosedSheetState();
}

class _DealClosedSheetState extends State<_DealClosedSheet> {
  final _dealValueController = TextEditingController();
  final _listPriceController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _dealValueController.dispose();
    _listPriceController.dispose();
    super.dispose();
  }

  void _confirm() {
    final validation = validateDealClosedInputs(
      dealValueText: _dealValueController.text,
      listPriceText: _listPriceController.text,
    );
    if (validation.error != null) {
      setState(() => _error = validation.error);
      return;
    }
    Navigator.of(context).pop(validation.result);
  }

  @override
  Widget build(BuildContext context) {
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
            'Deal Closed 🎉',
            style: AppText.display20.copyWith(fontSize: 18),
          ),
          Text(
            'Record the final value — and the list price if you discounted to close.',
            style: AppText.body13.copyWith(color: AppColors.schooner),
          ),
          const AppGap.lg(),
          TextField(
            controller: _dealValueController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Deal value (₹)',
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
          const AppGap.md(),
          TextField(
            controller: _listPriceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'List price before discount (optional)',
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
          if (_error != null) ...[
            const AppGap.xs(),
            Text(
              _error!,
              style: AppText.body13.copyWith(color: AppColors.alizarin),
            ),
          ],
          const AppGap.lg(),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: 'Confirm Closed Won',
              icon: Icons.check_circle_outline,
              onTap: _confirm,
            ),
          ),
        ],
      ),
    );
  }
}
