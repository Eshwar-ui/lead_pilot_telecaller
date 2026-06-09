import 'package:flutter/material.dart';
import 'package:flutter_app_utilities/flutter_app_utilities.dart' hide AppSpacing;

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

  static const _screens = [
    HomeScreen(),
    CallsScreen(),
    FollowUpsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: _BottomNav(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
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
