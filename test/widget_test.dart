import 'package:easytier_flutter/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app renders bottom navigation and dashboard', (tester) async {
    await tester.pumpWidget(const EasyTierApp());
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Peers'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
