import 'package:flutter_test/flutter_test.dart';
import 'package:lead_pilot_telecaller/src/screens/main_shell.dart';

// decideBackPressAction is MainShell's "press back again to exit" logic —
// pulled out so this timing/tab decision can be tested without a widget
// pump (which would need all four heavyweight tab screens, each with real
// network-calling providers, to build successfully under test).
void main() {
  final now = DateTime(2026, 8, 20, 12, 0, 0);

  test(
    'any non-Inbox tab switches to Inbox, regardless of last back press',
    () {
      expect(
        decideBackPressAction(currentTab: 1, lastBackPress: null, now: now),
        BackPressAction.switchToInbox,
      );
      expect(
        decideBackPressAction(currentTab: 3, lastBackPress: now, now: now),
        BackPressAction.switchToInbox,
      );
    },
  );

  test('on Inbox with no prior back press, shows the exit prompt', () {
    expect(
      decideBackPressAction(currentTab: 0, lastBackPress: null, now: now),
      BackPressAction.showExitPrompt,
    );
  });

  test('on Inbox, a second press within 2 seconds exits the app', () {
    final secondPress = now.add(const Duration(seconds: 1));
    expect(
      decideBackPressAction(
        currentTab: 0,
        lastBackPress: now,
        now: secondPress,
      ),
      BackPressAction.exitApp,
    );
  });

  test('on Inbox, a press at exactly the 2-second boundary still exits '
      '(the window is ">2s re-prompts", so exactly 2s does not)', () {
    final boundary = now.add(const Duration(seconds: 2));
    expect(
      decideBackPressAction(currentTab: 0, lastBackPress: now, now: boundary),
      BackPressAction.exitApp,
    );
  });

  test(
    'on Inbox, a press after more than 2 seconds re-shows the prompt instead of exiting',
    () {
      final later = now.add(const Duration(seconds: 3));
      expect(
        decideBackPressAction(currentTab: 0, lastBackPress: now, now: later),
        BackPressAction.showExitPrompt,
      );
    },
  );
}
