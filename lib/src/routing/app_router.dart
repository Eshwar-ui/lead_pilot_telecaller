import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/add_outbound_lead_screen.dart';
import '../screens/call_detail_screen.dart';
import '../screens/dialer_screen.dart';
import '../screens/lead_detail_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_shell.dart';
import '../screens/notifications_screen.dart';
import '../screens/post_call_screen.dart';
import '../screens/pre_call_screen.dart';
import '../services/session_store.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _SessionRefreshListenable(ref),
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider).isLoggedIn;
      final onLoginPage = state.matchedLocation == '/login';
      if (!loggedIn && !onLoginPage) return '/login';
      if (loggedIn && onLoginPage) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/home', builder: (context, state) => const MainShell()),
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
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/dialer/:id',
        builder: (context, state) =>
            DialerScreen(leadId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/leads/:id/post-call',
        builder: (context, state) => PostCallScreen(
          leadId: state.pathParameters['id']!,
          isNewCall: state.extra as bool? ?? false,
        ),
      ),
      GoRoute(
        path: '/leads/:id/calls/:callId',
        builder: (context, state) => CallDetailScreen(
          leadId: state.pathParameters['id']!,
          callId: state.pathParameters['callId']!,
          args: state.extra as CallDetailArgs?,
        ),
      ),
    ],
  );
});

/// Bridges Riverpod's [sessionProvider] to GoRouter's [Listenable]-based
/// refresh mechanism, so login/logout immediately re-run the redirect above
/// instead of only taking effect on the next manual navigation.
class _SessionRefreshListenable extends ChangeNotifier {
  _SessionRefreshListenable(Ref ref) {
    ref.listen(sessionProvider, (previous, next) => notifyListeners());
  }
}
