import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:map_culture/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PlaceFinderApp());

    // Verify that the app title appears
    expect(find.text('Explorador de Lugares'), findsOneWidget);

    // Verify the search field exists
    expect(find.byType(TextField), findsOneWidget);
  });
}
