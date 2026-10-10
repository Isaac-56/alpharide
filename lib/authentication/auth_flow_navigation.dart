import 'package:flutter/material.dart';

/// Keeps authentication transitions on the original MaterialApp root route.
///
/// The root route owns the authentication wrapper, which reacts to Firebase
/// authentication changes. Replacing that route with a standalone login
/// screen would remove
/// the listener and leave a later successful sign-in with nowhere to advance.
abstract final class AuthFlowNavigation {
  static Future<void> signOutAndReturnToRoot(
    BuildContext context,
    Future<void> Function() signOut,
  ) async {
    await signOut();
    if (!context.mounted) return;
    returnToRoot(context);
  }

  static void returnToRoot(BuildContext context) {
    Navigator.of(context, rootNavigator: true).popUntil(
      (Route<dynamic> route) => route.isFirst,
    );
  }
}
