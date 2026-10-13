import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:smartdose/main.dart';

void main() {
  testWidgets('App renders role selection screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SmartDoseApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
