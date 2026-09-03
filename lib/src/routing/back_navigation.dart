import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Pops [context] if there's a route to pop to, otherwise navigates to
/// [fallback].
///
/// Several routes in this app (Pre-Call, Post-Call, Call Detail, Lead Detail)
/// can end up as the sole entry in go_router's stack — either because they
/// were reached via `context.go(...)` (which replaces the whole stack, e.g.
/// the "Call Again" button) or because the native call-overlay brought the
/// app back via an OS-delivered deep link after a real call, which go_router
/// also treats as a full stack reset. `context.pop()` alone would then have
/// nothing to do, so every back control on those screens needs this fallback.
void goBackOr(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Wraps [child] so a hardware/gesture back press applies [goBackOr] the same
/// way an on-screen back button already does — without this, Android's
/// default back handling finds nothing left to pop on a stack-reset screen
/// (see [goBackOr]) and just exits the app instead of navigating anywhere.
///
/// `canPop` is read from `context.canPop()` on every build rather than
/// hardcoded, so Android's predictive-back preview still animates a normal
/// pop correctly whenever one is actually possible; the fallback only fires
/// for the genuine "nothing to pop" case.
class BackOrFallback extends StatelessWidget {
  const BackOrFallback({
    super.key,
    required this.fallback,
    required this.child,
  });

  /// Route to go to when there's nothing left on the stack to pop to.
  final String fallback;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(fallback);
      },
      child: child,
    );
  }
}
