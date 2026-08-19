import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'authentication/login_screen.dart';
import 'authentication/otp_screen.dart';
import 'authentication/signup_screen.dart';
import 'firebase_options.dart';
import 'home/home_screen.dart';
import 'services/session_service.dart';
import 'theme_controller.dart';
import 'widgets/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AppThemeController.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color primaryColor = Color(0xFF39FF14);

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
          themeAnimationDuration: const Duration(milliseconds: 600),
          themeAnimationCurve: Curves.easeInOutCubicEmphasized,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.light,
              surface: const Color(0xFFFFFFFF),
            ),
            scaffoldBackgroundColor: Colors.white,
            fontFamily: 'Roboto',
            dividerColor: const Color(0xFFE8EBE8),
            splashFactory: InkSparkle.splashFactory,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF171A17),
              contentTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.dark,
              surface: const Color(0xFF101210),
            ),
            scaffoldBackgroundColor: const Color(0xFF101210),
            fontFamily: 'Roboto',
            dividerColor: const Color(0xFF292D29),
            splashFactory: InkSparkle.splashFactory,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFFF4F7F4),
              contentTextStyle: const TextStyle(
                color: Color(0xFF101210),
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          home: const AuthWrapper(),
          routes: {
            '/login': (_) => const LoginScreen(),
            '/home': (_) => const HomeScreen(),
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
  late final Future<void> _minimumSplashDuration;

  @override
  void initState() {
    super.initState();
    _authStateChanges = FirebaseAuth.instance.authStateChanges();
    _minimumSplashDuration = Future<void>.delayed(
      const Duration(milliseconds: 2450),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _minimumSplashDuration,
      builder: (
        BuildContext context,
        AsyncSnapshot<void> splashSnapshot,
      ) {
        return StreamBuilder<User?>(
          stream: _authStateChanges,
          builder: (
            BuildContext context,
            AsyncSnapshot<User?> authSnapshot,
          ) {
            final bool splashComplete =
                splashSnapshot.connectionState == ConnectionState.done;
            final bool authReady =
                authSnapshot.connectionState != ConnectionState.waiting;

            if (!splashComplete || !authReady) {
              return const LoadingScreen();
            }

            if (authSnapshot.hasError) {
              return const LoginScreen();
            }

            final User? user = authSnapshot.data;

            if (user == null) {
              return const LoginScreen();
            }

            return ActiveSessionGate(
              key: ValueKey<String>(user.uid),
              user: user,
            );
          },
        );
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

class _ActiveSessionGateState extends State<ActiveSessionGate> {
  late final Future<bool> _validation;
  bool _signOutScheduled = false;

  @override
  void initState() {
    super.initState();
    _validation = SessionService.instance.validateExistingSession(widget.user);
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

            return const HomeScreen();
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
