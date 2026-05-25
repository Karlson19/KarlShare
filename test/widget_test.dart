import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karlshare/core/theme/app_theme.dart';
import 'package:karlshare/core/widgets/karlshare_button.dart';

/// Lightweight smoke test — booting the full router/app tree from a unit
/// test tries to register Flutter plugins (photo_manager, hive, the native
/// MethodChannels) that don't exist in the unit-test environment and hangs.
/// Real coverage of the full boot path needs an integration test on hardware.
/// Here we just verify the theme + a flagship widget render in both modes.
void main() {
  testWidgets('Primary button renders in dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: KarlshareButton(
              label: 'Send',
              icon: Icons.arrow_upward_rounded,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('Primary button renders in light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: KarlshareButton(
              label: 'Send',
              icon: Icons.arrow_upward_rounded,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Send'), findsOneWidget);
  });
}
