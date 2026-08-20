import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'services/session_store.dart';
import 'state/providers.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/leadpilot_widgets.dart';

class LeadPilotApp extends ConsumerWidget {
  const LeadPilotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session.restoring) {
      return MaterialApp(
        title: 'Asan Telecaller',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _StartupScreen(),
      );
    }

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Asan Telecaller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      // App-wide "can't reach server" banner, layered above whatever screen
      // is currently routed to — every screen gets it for free, none of them
      // need to check connectivity themselves.
      builder: (context, child) => _ConnectivityBanner(child: child),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.springWood,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Asan Innovators',
                image: true,
                child: Container(
                  width: 132,
                  height: 132,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.westar),
                  ),
                  child: Image.asset(
                    'assets/images/asan_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.blueRibbon,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Restoring your workspace…',
                style: AppText.body13.copyWith(color: AppColors.schooner),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectivityBanner extends ConsumerWidget {
  const _ConnectivityBanner({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable = ref.watch(serverReachableProvider);
    if (child == null) return const SizedBox.shrink();
    if (reachable) return child!;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          LpFallbackBanner(
            message: "Can't reach the server — retrying…",
            onRetry: () =>
                ref.read(serverReachableProvider.notifier).retryNow(),
          ),
          Expanded(child: child!),
        ],
      ),
    );
  }
}
