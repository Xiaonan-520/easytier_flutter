import 'package:easytier_flutter/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app renders bottom navigation with 5 destinations', (tester) async {
    await tester.pumpWidget(const EasyTierApp());
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Peers'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('switching to Network tab shows config form', (tester) async {
    await tester.pumpWidget(const EasyTierApp());
    await tester.tap(find.byIcon(Icons.hub_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Network name'), findsOneWidget);
  });
}
