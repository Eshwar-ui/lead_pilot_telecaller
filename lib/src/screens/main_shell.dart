import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing;

import '../services/permission_bootstrap.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'calls_screen.dart';
import 'follow_ups_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
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
    // Onboarding no longer runs before this screen, so request phone +
    // notification access here instead, as soon as the dashboard opens.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PermissionBootstrap.requestStartup(),
    );
  }

  /// Handles the Android system back button while the tab shell is showing.
  /// Never lets a single back press drop straight out of the app:
  ///  - On any non-Inbox tab, back returns to the Inbox tab.
  ///  - On the Inbox tab, the first back shows "Press back again to exit" and
  ///    only a second press within 2s actually leaves the app.
  void _handleBack() {
    if (_tab != 0) {
      setState(() => _tab = 0);
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
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
