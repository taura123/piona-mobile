import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:piona_mobile/screens/login_screen.dart';
import 'package:piona_mobile/theme/app_theme.dart';

void main() {
  testWidgets('LoginScreen shows welcome title', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );
    await tester.pump();
    expect(find.text('Selamat Datang'), findsOneWidget);
  });
}
