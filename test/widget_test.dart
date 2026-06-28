import 'package:flutter_test/flutter_test.dart';
import 'package:eventzone_app/main.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EventzoneApp());

    // Verify that we are on the discovery screen (Global Events text)
    expect(find.text('GLOBAL EVENTS'), findsOneWidget);
  });
}
