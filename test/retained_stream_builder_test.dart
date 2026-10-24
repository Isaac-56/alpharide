import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/core/widgets/retained_stream_builder.dart';

void main() {
  testWidgets(
    'rebuilds keep one live subscription, account changes discard old data',
    (tester) async {
      int opened = 0;
      int cancelled = 0;
      final first = StreamController<String>(onCancel: () => cancelled++);
      final second = StreamController<String>();
      Widget page(String account, bool dark) => MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: RetainedStreamBuilder<String>(
          sourceKey: account,
          createStream: () {
            opened++;
            return account == 'first' ? first.stream : second.stream;
          },
          builder: (context, snapshot) => Text(snapshot.data ?? 'Loading'),
        ),
      );
      await tester.pumpWidget(page('first', false));
      first.add('First account data');
      await tester.pump();
      await tester.pumpWidget(page('first', true));
      expect(opened, 1);
      expect(cancelled, 0);
      expect(find.text('First account data'), findsOneWidget);
      first.add('Live update');
      await tester.pump();
      expect(find.text('Live update'), findsOneWidget);
      await tester.pumpWidget(page('second', true));
      expect(opened, 2);
      expect(cancelled, 1);
      expect(find.text('Live update'), findsNothing);
      second.add('Second account data');
      await tester.pump();
      expect(find.text('Second account data'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await first.close();
      await second.close();
    },
  );
}
