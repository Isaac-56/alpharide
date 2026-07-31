import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'authentication/login_screen.dart';
import 'authentication/otp_screen.dart';
import 'authentication/signup_screen.dart';
import 'firebase_options.dart';
import 'home/home_screen.dart';
import 'theme_controller.dart';
import 'widgets/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
          themeAnimationDuration: const Duration(
            milliseconds: 600,
          ),
          themeAnimationCurve: Curves.easeInOutCubicEmphasized,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: Colors.white,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: const Color(0xFF101210),
          ),
          home: const AuthWrapper(),
          routes: {
            '/login': (_) => const LoginScreen(),
            '/home': (_) => const HomeScreen(),
          },
          onGenerateRoute: (
            RouteSettings settings,
          ) {
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

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (
        BuildContext context,
        AsyncSnapshot<User?> snapshot,
      ) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        if (snapshot.hasError) {
          return const LoginScreen();
        }

        final User? user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return const HomeScreen();
      },
    );
  }
}
