import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_notes/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows notes list and opens native editor', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const LiquidNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('备忘录'), findsWidgets);
    expect(find.text('今天的想法'), findsOneWidget);
    expect(find.byType(CupertinoSearchTextField), findsOneWidget);

    await tester.tap(find.text('今天的想法'));
    await tester.pumpAndSettle();

    expect(find.text('编辑备忘录'), findsOneWidget);
    expect(find.text('提醒时间'), findsOneWidget);
    expect(find.byType(CupertinoSwitch), findsNWidgets(2));
  });
}
