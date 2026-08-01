import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/bookings/my_bookings_screen.dart';
import '../features/events/checkin_screen.dart';
import '../features/events/event_detail_screen.dart';
import '../features/events/event_form_screen.dart';
import '../features/events/events_list_screen.dart';
import '../features/shell/home_shell.dart';

/// Bridges Riverpod's [authControllerProvider] to go_router's
/// `refreshListenable` - go_router only re-evaluates `redirect` on
/// navigation or when this notifies, so a sign-in/sign-out that happens
/// without a navigation event (e.g. the splash-screen session bootstrap
/// resolving) still re-runs the redirect logic below.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (previous, next) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: RegisterScreen.routePath,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/events/new',
        builder: (context, state) => const EventFormScreen(),
      ),
      GoRoute(
        path: '/events/:id',
        builder: (context, state) =>
            EventDetailScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/events/:id/edit',
        builder: (context, state) =>
            EventFormScreen(eventId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/events/:id/checkin',
        builder: (context, state) =>
            CheckInScreen(eventId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                builder: (context, state) => const EventsListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/bookings',
                builder: (context, state) => const MyBookingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// This app has no anonymous/guest session - every screen requires a real,
/// signed-in account (organizer or attendee) - see
/// `plan/build-plan.md` "Auth Flow". `/register` is reachable from
/// `/login` without already being signed in.
String? _redirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authControllerProvider);
  final location = state.matchedLocation;
  final isAuthRoute =
      location == '/login' || location == RegisterScreen.routePath;

  if (authState.isLoading) {
    return location == '/splash' ? null : '/splash';
  }

  final user = authState.valueOrNull;
  if (user == null) {
    return isAuthRoute ? null : '/login';
  }

  if (isAuthRoute || location == '/splash') {
    return '/events';
  }

  return null;
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
