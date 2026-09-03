import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart'
    hide AppSpacing;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auto_capture_settings.dart';
import '../services/call_actions.dart';
import '../services/call_detection_bridge.dart';
import '../services/permission_bootstrap.dart';
import '../state/call_capture.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'calls_screen.dart';
import 'follow_ups_screen.dart';
import 'profile_screen.dart';

/// What the Android back button should do while the tab shell is showing.
enum BackPressAction { switchToInbox, showExitPrompt, exitApp }

/// Pure decision behind [_MainShellState._handleBack]'s "press back again to
/// exit" behaviour, pulled out so the timing logic can be tested without a
/// widget pump:
///  - Any non-Inbox tab -> switch to Inbox.
///  - Inbox tab, first press (or >2s since the last one) -> show the prompt.
///  - Inbox tab, a second press within 2s of the first -> actually exit.
BackPressAction decideBackPressAction({
  required int currentTab,
  required DateTime? lastBackPress,
  required DateTime now,
}) {
  if (currentTab != 0) return BackPressAction.switchToInbox;
  if (lastBackPress == null ||
      now.difference(lastBackPress) > const Duration(seconds: 2)) {
    return BackPressAction.showExitPrompt;
  }
  return BackPressAction.exitApp;
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int _tab = 0;

  /// Timestamp of the last "back" press while on the Inbox tab — used to
  /// implement the "press again to exit" double-tap-to-exit behaviour.
  DateTime? _lastBackPress;

  static const _screens = [
    HomeScreen(),
    CallsScreen(),
    FollowUpsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Onboarding no longer runs before this screen, so request phone +
    // notification access here instead, as soon as the dashboard opens.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PermissionBootstrap.requestStartup(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // PostCallScreen already retries its own outbox drain on resume, but that
    // only fires while a PostCallScreen happens to be mounted. A telecaller
    // who backgrounds the app mid-upload (e.g. switches to WhatsApp) and
    // later reopens straight to the Inbox/Calls tab — never revisiting
    // post-call — would otherwise leave that recording stuck in the outbox
    // until they happen to open some call's post-call screen again. This
    // shell wraps every screen for the app's whole lifetime, so draining here
    // catches every resume regardless of which tab is showing.
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(callCaptureProvider.notifier).drainOutbox());
      // The founder may have changed the organisation name/logo in the web
      // portal while this app was backgrounded. Refresh it so the signed-in
      // headers update without requiring the telecaller to log out or restart.
      ref.invalidate(orgProfileProvider);
    }
  }

  /// Handles the Android system back button while the tab shell is showing.
  /// Never lets a single back press drop straight out of the app:
  ///  - On any non-Inbox tab, back returns to the Inbox tab.
  ///  - On the Inbox tab, the first back shows "Press back again to exit" and
  ///    only a second press within 2s actually leaves the app.
  void _handleBack() {
    final now = DateTime.now();
    switch (decideBackPressAction(
      currentTab: _tab,
      lastBackPress: _lastBackPress,
      now: now,
    )) {
      case BackPressAction.switchToInbox:
        setState(() => _tab = 0);
      case BackPressAction.showExitPrompt:
        _lastBackPress = now;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
      case BackPressAction.exitApp:
        SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The native detector's lifetime follows the consent toggle. No
    // fireImmediately needed: the setting always starts false and flips to its
    // stored value once SharedPreferences loads, so an already-enabled setting
    // arrives here as a change on every app start.
    ref.listen<bool>(autoCaptureEnabledProvider, (previous, next) {
      if (next) {
        unawaited(startCallDetection());
      } else if (previous == true) {
        unawaited(stopCallDetection());
      }
    });

    // A call ended somewhere on this phone. If it was to or from a lead, it
    // gets captured and analysed silently — no navigation, no interruption.
    ref.listen(callDetectionEventsProvider, (previous, next) {
      next.whenData((call) {
        if (!ref.read(autoCaptureEnabledProvider)) return;
        unawaited(
          ref.read(callCaptureProvider.notifier).handleDetectedCall(call),
        );
      });
    });

    return PopScope(
      // We handle back ourselves (tab switch / exit prompt) rather than letting
      // the framework pop the route, which would exit the app immediately.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.springWood,
        resizeToAvoidBottomInset: false,
        body: IndexedStack(index: _tab, children: _screens),
        bottomNavigationBar: _BottomNav(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (icon: Icons.inbox_outlined, label: 'Inbox'),
    (icon: Icons.call_outlined, label: 'Calls'),
    (icon: Icons.bookmark_border_outlined, label: 'Follow-ups'),
    (icon: Icons.person_outline, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.westar)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: TapScale(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _items[i].icon,
                          size: 21,
                          color: currentIndex == i
                              ? AppColors.blueRibbon
                              : AppColors.schooner,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].label,
                          style: AppText.caption11.copyWith(
                            color: currentIndex == i
                                ? AppColors.blueRibbon
                                : AppColors.schooner,
                            fontWeight: currentIndex == i
                                ? FontWeight.w700
                                : FontWeight.w400,
                            fontSize: 10,
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
    );
  }
}
