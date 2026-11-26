import 'dart:async';

import 'package:flutter/material.dart';

/// Updates only the visible waiting display, never a hidden tab or background app.
/// Wall-clock time remains authoritative when the display resumes.
class VisibleClock extends StatefulWidget {
  const VisibleClock({required this.builder, super.key});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<VisibleClock> createState() => _VisibleClockState();
}

class _VisibleClockState extends State<VisibleClock> with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context);
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncTimer();
    if (_resumed && _visible) setState(() {});
  }

  void _syncTimer() {
    if (!_visible || !_resumed) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}
