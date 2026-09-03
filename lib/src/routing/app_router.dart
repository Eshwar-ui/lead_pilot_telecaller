import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/add_outbound_lead_screen.dart';
import '../screens/call_detail_screen.dart';
import '../screens/change_password_screen.dart';
import '../screens/lead_detail_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_shell.dart';
import '../screens/notifications_screen.dart';
import '../screens/post_call_screen.dart';
import '../screens/pre_call_screen.dart';
import '../screens/recording_check_screen.dart';
import '../services/session_store.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: _SessionRefreshListenable(ref),
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loggedIn = session.isLoggedIn;
      final onLoginPage = state.matchedLocation == '/login';
      const changePasswordPath = '/change-password-required';
      final onChangePasswordPage = state.matchedLocation == changePasswordPath;
      if (!loggedIn && !onLoginPage) return '/login';
      if (loggedIn && onLoginPage) return '/home';
      // A temp password from an invite/reset must be changed before anything
      // else is reachable — blocks deep links and tab restoration too, not
      // just the initial post-login navigation.
      if (loggedIn && session.mustResetPassword && !onChangePasswordPage) {
        return changePasswordPath;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/change-password-required',
        builder: (context, state) => ChangePasswordScreen(
          forced: true,
          knownCurrentPassword:
              (state.extra as Map?)?['currentPassword'] as String?,
        ),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(forced: false),
      ),
      GoRoute(path: '/home', builder: (context, state) => const MainShell()),
      GoRoute(
        path: '/recording-check',
        builder: (context, state) => const RecordingCheckScreen(),
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
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/leads/:id/post-call',
        builder: (context, state) => PostCallScreen(
          leadId: state.pathParameters['id']!,
          // `extra` covers in-app `context.push(..., extra: true)` navigation.
          // The native call-overlay returns via a URI-only deep link (it can
          // never carry Dart `extra`), especially on a cold start after the
          // OS killed the app mid-call — so it flags the same intent with a
          // `?new=1` query param instead. Either source means "just finished
          // a call, go capture the recording".
          isNewCall:
              (state.extra as bool?) ??
              (state.uri.queryParameters['new'] == '1'),
          // Query-param navigation is the native overlay returning after the
          // call. In-app `extra: true` navigation happens while the dialler is
          // only starting, when scanning could select the previous recording.
          captureOnOpen: state.uri.queryParameters['new'] == '1',
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
