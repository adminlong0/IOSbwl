import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_notes/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows seeded notes and opens editor', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const LiquidNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('备忘录'), findsOneWidget);
    expect(find.text('今天的灵感'), findsOneWidget);

    await tester.tap(find.text('今天的灵感'));
    await tester.pumpAndSettle();

    expect(find.text('完成'), findsOneWidget);
    expect(find.text('液态玻璃设计'), findsNothing);
  });
}
