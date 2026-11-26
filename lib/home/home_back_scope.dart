import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Installed only on home. Pushed pages retain their own Navigator back stack.
class HomeBackScope extends StatefulWidget {
  const HomeBackScope({super.key, required this.child, required this.onBackStep,
    this.onExit});
  final Widget child;
  final bool Function() onBackStep;
  final VoidCallback? onExit;

  @override
  State<HomeBackScope> createState() => _HomeBackScopeState();
}

class _HomeBackScopeState extends State<HomeBackScope> {
  Timer? _exitWindow;

  void _back() {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (widget.onBackStep()) {
      _exitWindow?.cancel();
      return;
    }
    if (_exitWindow?.isActive == true) {
      _exitWindow?.cancel();
      if (widget.onExit != null) {
        widget.onExit!();
      } else {
        SystemNavigator.pop();
      }
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Press back again to exit'),
        duration: Duration(seconds: 2),
      ));
    _exitWindow = Timer(const Duration(seconds: 2), () {});
  }

  @override
  void dispose() {
    _exitWindow?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: widget.child,
  );
}
