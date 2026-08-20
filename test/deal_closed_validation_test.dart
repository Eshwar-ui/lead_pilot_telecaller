import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/widgets/deal_closed_sheet.dart';

// validateDealClosedInputs is the discount-math + form-validation logic
// behind the "Closed Won" sheet — pulled out of _DealClosedSheetState so the
// boundary cases (listPrice == dealValue, listPrice < dealValue) called out
// as a test gap in the earlier audit can be checked directly.
void main() {
  test(
    'a valid deal value with no list price returns a result with no discount',
    () {
      final result = validateDealClosedInputs(
        dealValueText: '50000',
        listPriceText: '',
      );
      expect(result.error, isNull);
      expect(result.result!.dealValue, 50000);
      expect(result.result!.listPrice, isNull);
      expect(result.result!.discountPct, isNull);
    },
  );

  test('an empty deal value is rejected', () {
    final result = validateDealClosedInputs(
      dealValueText: '',
      listPriceText: '',
    );
    expect(result.error, 'Enter the final deal value');
    expect(result.result, isNull);
  });

  test('a zero or negative deal value is rejected', () {
    expect(
      validateDealClosedInputs(dealValueText: '0', listPriceText: '').error,
      isNotNull,
    );
    expect(
      validateDealClosedInputs(dealValueText: '-100', listPriceText: '').error,
      isNotNull,
    );
  });

  test('a non-numeric list price is rejected', () {
    final result = validateDealClosedInputs(
      dealValueText: '50000',
      listPriceText: 'abc',
    );
    expect(result.error, 'List price must be a number');
  });

  test(
    'list price below the deal value is rejected, not silently discounted negative',
    () {
      final result = validateDealClosedInputs(
        dealValueText: '60000',
        listPriceText: '50000',
      );
      expect(result.error, "List price can't be less than the deal value");
      expect(result.result, isNull);
    },
  );

  test(
    'list price equal to the deal value is a valid 0% discount (boundary)',
    () {
      final result = validateDealClosedInputs(
        dealValueText: '50000',
        listPriceText: '50000',
      );
      expect(result.error, isNull);
      expect(result.result!.discountPct, 0);
    },
  );

  test('a genuine discount computes the correct percentage', () {
    final result = validateDealClosedInputs(
      dealValueText: '80000',
      listPriceText: '100000',
    );
    expect(result.error, isNull);
    expect(result.result!.listPrice, 100000);
    expect(result.result!.discountPct, 20);
  });

  test('whitespace around both fields is trimmed', () {
    final result = validateDealClosedInputs(
      dealValueText: ' 50000 ',
      listPriceText: ' 60000 ',
    );
    expect(result.error, isNull);
    expect(result.result!.dealValue, 50000);
    expect(result.result!.listPrice, 60000);
  });
}
