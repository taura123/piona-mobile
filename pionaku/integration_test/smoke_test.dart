// Run on a device/emulator: flutter test integration_test/smoke_test.dart
// (VM-only CI can use test/login_screen_build_test.dart instead.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:piona_mobile/screens/login_screen.dart';
import 'package:piona_mobile/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LoginScreen builds without backend', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selamat Datang'), findsOneWidget);
  });
}
