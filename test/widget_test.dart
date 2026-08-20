import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lead_pilot_telecaller/src/app.dart';
import 'package:lead_pilot_telecaller/src/screens/add_outbound_lead_screen.dart';

void main() {
  testWidgets('app boots without throwing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LeadPilotApp()));
    // A single frame is enough to confirm the widget tree builds.
    await tester.pump();
    expect(find.byType(MaterialApp), findsWidgets);
  });

  testWidgets('outbound sheet renders its required fields', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AddOutboundLeadScreen())),
      ),
    );
    await tester.pump();

    expect(find.text('Add Outbound Lead'), findsOneWidget);
    expect(find.text('Save & Call'), findsOneWidget);
    expect(find.text('Save Lead'), findsOneWidget);
  });
}
