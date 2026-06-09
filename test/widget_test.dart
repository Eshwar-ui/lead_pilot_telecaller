import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lead_pilot_telecaller/src/app.dart';
import 'package:lead_pilot_telecaller/src/screens/add_outbound_lead_screen.dart';
import 'package:lead_pilot_telecaller/src/screens/caller_selector_screen.dart';
import 'package:lead_pilot_telecaller/src/screens/pre_call_screen.dart';

void main() {
  testWidgets('boots into onboarding and navigates to queue', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LeadPilotApp()));
    await tester.pumpAndSettle();

    expect(find.text('LeadPilot'), findsOneWidget);
    expect(find.text('Open Queue'), findsOneWidget);

    await tester.tap(find.text('Open Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Outbound queue'), findsOneWidget);
    expect(find.text('PRIORITY LEADS'), findsOneWidget);
  });

  testWidgets('lead detail shows Figma-derived sections', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LeadPilotApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Queue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ravi Kumar').first);
    await tester.pumpAndSettle();

    expect(find.text('Lead Detail'), findsOneWidget);
    expect(find.text('Ravi Kumar'), findsWidgets);
    expect(find.text('MEMORY BUBBLE'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('CALL HISTORY (2)'), 300);
    expect(find.text('CALL HISTORY (2)'), findsOneWidget);
  });

  testWidgets('pre-call checklist toggles with Riverpod state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PreCallScreen(leadId: 'ravi-kumar')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('2 / 4'), 500);
    expect(find.text('2 / 4'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Offer site visit for Saturday'),
      200,
    );
    await tester.tap(find.text('Offer site visit for Saturday'));
    await tester.pumpAndSettle();

    expect(find.text('3 / 4'), findsOneWidget);
  });

  testWidgets('caller selector route shows call app options', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CallerSelectorScreen(leadId: 'ravi-kumar')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('complete action using'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('True Caller'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);
  });

  testWidgets('outbound drawer renders required fields', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AddOutboundLeadScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Outbound Lead'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.text('Save & Call'), findsOneWidget);
  });
}
