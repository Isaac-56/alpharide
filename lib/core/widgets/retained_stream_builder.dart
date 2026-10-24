import 'package:flutter/widgets.dart';

/// Keeps one subscription while the page rebuilds. Change sourceKey whenever
/// the account, query, or service changes; the old snapshot is then discarded.
class RetainedStreamBuilder<T> extends StatefulWidget {
  const RetainedStreamBuilder({
    required this.sourceKey,
    required this.createStream,
    required this.builder,
    this.initialData,
    super.key,
  });

  final Object sourceKey;
  final Stream<T> Function() createStream;
  final AsyncWidgetBuilder<T> builder;
  final T? initialData;

  @override
  State<RetainedStreamBuilder<T>> createState() =>
      _RetainedStreamBuilderState<T>();
}

class _RetainedStreamBuilderState<T> extends State<RetainedStreamBuilder<T>> {
  late Stream<T> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.createStream();
  }

  @override
  void didUpdateWidget(covariant RetainedStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey) {
      _stream = widget.createStream();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    key: ValueKey<Object>(widget.sourceKey),
    stream: _stream,
    initialData: widget.initialData,
    builder: widget.builder,
  );
}
