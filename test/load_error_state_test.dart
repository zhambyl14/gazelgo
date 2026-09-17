import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasu/shared/widgets.dart';

void main() {
  testWidgets('LoadErrorState қайта жүктеу әрекетін шақырады', (tester) async {
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoadErrorState(onRetry: () => retryCount++),
        ),
      ),
    );

    expect(find.text('Деректерді жүктеу мүмкін болмады'), findsOneWidget);
    await tester.tap(find.text('Қайталау'));
    expect(retryCount, 1);
  });
}
