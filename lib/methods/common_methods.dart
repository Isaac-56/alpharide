import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class CommonMethods {
  Future<void> checkConnectivity(BuildContext context) async {
    final List<ConnectivityResult> connectionResults =
        await Connectivity().checkConnectivity();

    final bool isConnected = connectionResults.any(
      (ConnectivityResult result) => result != ConnectivityResult.none,
    );

    if (!isConnected && context.mounted) {
      displaySnackbar(
        'No internet connection',
        context,
      );
    }
  }

  void displaySnackbar(
    String messageText,
    BuildContext context,
  ) {
    final SnackBar snackBar = SnackBar(
      content: Text(messageText),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
