import 'package:flutter_test/flutter_test.dart';

import 'package:v_call_me/main.dart';

void main() {
  testWidgets('Home screen shows start/join buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const VCallMeApp());

    expect(find.text('Start a call'), findsOneWidget);
    expect(find.text('Join a call'), findsOneWidget);
  });
}
