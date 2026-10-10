import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passengerapp/core/theme/alpha_theme.dart';

void main() {
  test('AlphaRide supports matching light and dark design systems', () {
    expect(AlphaTheme.light.brightness, Brightness.light);
    expect(AlphaTheme.dark.brightness, Brightness.dark);
    expect(AlphaTheme.light.scaffoldBackgroundColor, Colors.white);
    expect(
      AlphaTheme.light.colorScheme.surface,
      isNot(AlphaTheme.dark.colorScheme.surface),
    );
    expect(AlphaTheme.light.navigationBarTheme.height, 68);
    expect(
      AlphaTheme.dark.bottomSheetTheme.dragHandleSize,
      const Size(48, 5),
    );
  });
}
