import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'authentication/login_screen.dart';
import 'authentication/otp_screen.dart';
import 'authentication/signup_screen.dart';
import 'core/theme/alpha_theme.dart';
import 'firebase_options.dart';
import 'home/active_ride_gate.dart';
import 'services/session_service.dart';
import 'theme_controller.dart';
import 'widgets/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Future<void> themeInitialization = AppThemeController.initialize();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await themeInitialization;

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.themeMode,
      builder: (
        BuildContext context,
        ThemeMode themeMode,
        Widget? child,
      ) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Alpha Passenger',
          themeMode: themeMode,
          themeAnimationDuration: const Duration(milliseconds: 250),
          themeAnimationCurve: Curves.easeInOutCubicEmphasized,
          theme: AlphaTheme.light,
          darkTheme: AlphaTheme.dark,
          home: const AuthWrapper(),
          routes: {
            '/login': (_) => const LoginScreen(),
          },
          onGenerateRoute: (RouteSettings settings) {
            switch (settings.name) {
              case '/otp':
                final Map<String, dynamic> arguments =
                    settings.arguments as Map<String, dynamic>;

                return MaterialPageRoute<void>(
                  builder: (_) => OTPScreen(
                    phoneNumber: arguments['phone'] as String,
                    verificationId: arguments['verificationId'] as String,
                  ),
                );

              case '/signup':
                final String phoneNumber = settings.arguments as String;

                return MaterialPageRoute<void>(
                  builder: (_) => SignUpScreen(
                    phoneNumber: phoneNumber,
                  ),
                );

              default:
                return null;
            }
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final Stream<User?> _authStateChanges;

  @override
  void initState() {
    super.initState();
    _authStateChanges = FirebaseAuth.instance.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStateChanges,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (BuildContext context, AsyncSnapshot<User?> authSnapshot) {
        if (authSnapshot.hasError) return const LoginScreen();
        final User? user = authSnapshot.data;
        if (user == null) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen();
          }
          return const LoginScreen();
        }
        return ActiveSessionGate(key: ValueKey<String>(user.uid), user: user);
      },
    );
  }
}

class ActiveSessionGate extends StatefulWidget {
  final User user;

  const ActiveSessionGate({
    required this.user,
    super.key,
  });

  @override
  State<ActiveSessionGate> createState() => _ActiveSessionGateState();
}

class _ActiveSessionGateState extends State<ActiveSessionGate>
    with WidgetsBindingObserver {
  late final Future<bool> _validation;
  bool _signOutScheduled = false;
  bool _resumeCheckInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _validation = SessionService.instance.validateExistingSession(widget.user);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_validateAfterResume());
    }
  }

  Future<void> _validateAfterResume() async {
    if (_resumeCheckInProgress || _signOutScheduled) return;

    _resumeCheckInProgress = true;

    try {
      final bool isValid = await SessionService.instance
          .validateExistingSession(widget.user, forceServer: true);

      if (!isValid && mounted) {
        _scheduleForcedSignOut();
      }
    } finally {
      _resumeCheckInProgress = false;
    }
  }

  void _scheduleForcedSignOut() {
    if (_signOutScheduled) return;
    _signOutScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await SessionService.instance.forceLocalSignOut(widget.user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _validation,
      builder: (
        BuildContext context,
        AsyncSnapshot<bool> validationSnapshot,
      ) {
        if (validationSnapshot.connectionState != ConnectionState.done) {
          return const _SessionCheckingScreen();
        }

        if (validationSnapshot.data != true) {
          _scheduleForcedSignOut();
          return const _SessionCheckingScreen(
            message: 'This account was opened on another device.',
          );
        }

        return StreamBuilder<bool>(
          stream: SessionService.instance.watchSession(widget.user),
          builder: (
            BuildContext context,
            AsyncSnapshot<bool> sessionSnapshot,
          ) {
            if (sessionSnapshot.hasData && sessionSnapshot.data == false) {
              _scheduleForcedSignOut();
              return const _SessionCheckingScreen(
                message: 'Signing out this older session…',
              );
            }

            return const ActiveRideGate();
          },
        );
      },
    );
  }
}

class _SessionCheckingScreen extends StatelessWidget {
  final String? message;

  const _SessionCheckingScreen({
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: colors.primary,
              ),
              if (message != null) ...[
                const SizedBox(height: 18),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
