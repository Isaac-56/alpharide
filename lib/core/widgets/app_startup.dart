import 'package:flutter/material.dart';

/// Paints a lightweight first frame before starting SDK initialization.
/// Protected app widgets are not constructed until initialization succeeds.
class AppStartup extends StatefulWidget {
  const AppStartup({required this.initialize, required this.builder, super.key});

  final Future<void> Function() initialize;
  final WidgetBuilder builder;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  bool _ready = false;
  bool _failed = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  Future<void> _initialize() async {
    try {
      await widget.initialize();
      if (mounted) {
        setState(() {
          _ready = true;
          _busy = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  void _retry() {
    if (_busy) return;
    setState(() {
      _failed = false;
      _busy = true;
    });
    _initialize();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (!_failed) const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(_failed ? 'Unable to start. Please try again.' : 'Opening Alpha…',
                    textAlign: TextAlign.center),
                if (_failed) TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
