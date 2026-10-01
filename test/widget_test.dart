import 'package:easytier_flutter/app/app.dart';
import 'package:easytier_flutter/app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(EasyTierApp(themeController: ThemeController()));
    // Profile load resolves via the mocked shared_preferences; a plain pump
    // (not pumpAndSettle, which would hang on the spinner swap) suffices.
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('app renders bottom navigation with 4 destinations', (tester) async {
    await boot(tester);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Networks'), findsWidgets);
    expect(find.text('Peers'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('home shows the connection card with a Connect action', (tester) async {
    await boot(tester);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('networks tab shows empty state with add action', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Networks'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('No networks yet'), findsOneWidget);
    expect(find.text('Add Network'), findsOneWidget);
  });
}
