import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'authentication/login_screen.dart';
import 'authentication/otp_screen.dart';
import 'authentication/signup_screen.dart';
import 'home/home_screen.dart';
import 'widgets/loading_screen.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

 // await FirebaseAppCheck.instance.activate(
   // androidProvider: AndroidProvider.debug,
  //);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: "Alpha Passenger",

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF39FF14),
        ),
      ),

      home: const LoadingScreen(),

      routes: {
        "/login": (_) => const LoginScreen(),
        "/home": (_) => const HomeScreen(),
      },

      onGenerateRoute: (settings) {
        switch (settings.name) {
          case "/otp":
            final args = settings.arguments as Map<String, dynamic>;

            return MaterialPageRoute(
              builder: (_) => OTPScreen(
                phoneNumber: args["phone"],
                verificationId: args["verificationId"],
              ),
            );

          case "/signup":
            final phone = settings.arguments as String;
            return MaterialPageRoute(
              builder: (_) => SignUpScreen(phoneNumber: phone),
            );
        }

        return null;
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
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.active) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return const HomeScreen();
      },
    );
  }
}