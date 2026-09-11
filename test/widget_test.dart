import 'package:flutter_test/flutter_test.dart';

import 'package:mapx/main.dart';

void main() {
  testWidgets('Home screen shows building name and destination CTA', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MapXApp());
    await tester.pumpAndSettle();

    expect(find.text('MapX'), findsOneWidget);
    expect(find.text('Dept. of IT, School of Engineering'), findsOneWidget);
    expect(find.text('Where do you want to go?'), findsOneWidget);

    await tester.tap(find.text('Where do you want to go?'));
    await tester.pumpAndSettle();

    expect(find.text('Select destination'), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);
  });
}
