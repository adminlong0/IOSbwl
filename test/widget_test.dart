import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nlbus/app_store.dart';
import 'package:nlbus/main.dart';

void main() {
  testWidgets('renders the shared NLBUS navigation', (tester) async {
    final store = AppStore();
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const AppShell(),
        ),
      ),
    );
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('路线'), findsOneWidget);
    expect(find.text('地图'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
