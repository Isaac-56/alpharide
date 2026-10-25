import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/core/widgets/account_avatar.dart';

void main() {
  testWidgets(
    'private photo reloads when its storage path changes, not on ordinary rebuilds',
    (WidgetTester tester) async {
      final List<String> reads = <String>[];
      final Uint8List bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgaGD4DwAChAGA+gVWHQAAAABJRU5ErkJggg==',
      );
      Future<Uint8List?> load(String path) async {
        reads.add(path);
        return bytes;
      }

      Widget page(String path) => MaterialApp(
        home: AccountAvatar(photo: path, loadBytes: load),
      );
      await tester.pumpWidget(page('users/u1/profile/first.jpg'));
      await tester.pump();
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
        isNotNull,
      );
      await tester.pumpWidget(page('users/u1/profile/first.jpg'));
      expect(reads, hasLength(1));
      await tester.pumpWidget(page('users/u1/profile/new.jpg'));
      await tester.pump();
      expect(reads, <String>[
        'users/u1/profile/first.jpg',
        'users/u1/profile/new.jpg',
      ]);
      await tester.pumpWidget(page(''));
      await tester.pump();
      expect(
        tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
        isNull,
      );
    },
  );

  testWidgets(
    'a failed download can be retried without reopening the account',
    (WidgetTester tester) async {
      int attempts = 0;
      Future<Uint8List?> load(String path) async {
        attempts++;
        throw StateError('offline');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: AccountAvatar(
            photo: 'users/u1/profile/photo.jpg',
            loadBytes: load,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(CircleAvatar));
      await tester.pump();
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
