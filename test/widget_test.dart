import 'package:flutter_test/flutter_test.dart';
import 'package:gazelgo/main.dart';

void main() {
  testWidgets('app boots to config screen when env is not set',
      (WidgetTester tester) async {
    await tester.pumpWidget(const GazelGoApp());
    // Env бапталмаған кезде түсіндірме экраны көрінуі керек.
    expect(find.text('Backend бапталмаған'), findsOneWidget);
  });
}
