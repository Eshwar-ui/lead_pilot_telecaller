import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/add_outbound_lead_screen.dart';
import '../screens/caller_selector_screen.dart';
import '../screens/dialer_screen.dart';
import '../screens/lead_detail_screen.dart';
import '../screens/main_shell.dart';
import '../screens/onboarding_screen.dart';
import '../screens/post_call_screen.dart';
import '../screens/pre_call_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/onboarding',
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/leads/:id',
        builder: (context, state) =>
            LeadDetailScreen(leadId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/leads/:id/pre-call',
        builder: (context, state) =>
            PreCallScreen(leadId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/outbound/add',
        builder: (context, state) => const AddOutboundLeadScreen(),
      ),
      GoRoute(
        path: '/caller-selector/:id',
        builder: (context, state) =>
            CallerSelectorScreen(leadId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/dialer/:id',
        builder: (context, state) =>
            DialerScreen(leadId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/leads/:id/post-call',
        builder: (context, state) =>
            PostCallScreen(leadId: state.pathParameters['id']!),
      ),
    ],
  );
});
