import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lead_pilot_telecaller/src/screens/change_password_screen.dart';

// FormShell renders its label via a raw RichText (not Text/Text.rich), which
// find.text doesn't match — this finds it by plain-text content instead.
// required fields append " *" as a child TextSpan, hence startsWith not ==.
Finder findLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().startsWith(label),
);

void main() {
  testWidgets('forced mode hides the current-password field and shows the forced copy', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ChangePasswordScreen(forced: true, knownCurrentPassword: 'temp-pass-123'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Set a New Password'), findsOneWidget);
    expect(findLabel('Current Password'), findsNothing);
    expect(findLabel('New Password'), findsOneWidget);
    expect(findLabel('Confirm New Password'), findsOneWidget);
  });

  // Regression cover for the forced-mode dead end: a cold start or deep link
  // into `/change-password-required` loses `knownCurrentPassword` (the
  // router's redirect carries no `extra`), and forced mode used to hide the
  // current-password field unconditionally — leaving the user on a screen
  // with no way to enter their temp password and no back button.
  testWidgets('forced mode with no known current password falls back to asking for it',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ChangePasswordScreen(forced: true, knownCurrentPassword: null),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Set a New Password'), findsOneWidget);
    expect(findLabel('Current Password'), findsOneWidget);
  });

  testWidgets('voluntary mode shows the current-password field', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ChangePasswordScreen(forced: false)),
      ),
    );
    await tester.pump();

    expect(find.text('Set a New Password'), findsNothing);
    expect(findLabel('Current Password'), findsOneWidget);
  });

  testWidgets('mismatched new/confirm passwords are rejected before any network call', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ChangePasswordScreen(forced: true, knownCurrentPassword: 'temp-pass-123'),
        ),
      ),
    );
    await tester.pump();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2)); // new password, confirm password

    await tester.enterText(fields.at(0), 'NewPassword456!');
    await tester.enterText(fields.at(1), 'DoesNotMatch789!');
    await tester.tap(find.text('Set New Password'));
    await tester.pump();

    expect(find.text("New password and confirmation don't match"), findsOneWidget);
  });
}
