import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keenon_control/app_state.dart';
import 'package:keenon_control/main.dart';

void main() {
  testWidgets('데모 모드: 매장 목록이 표시된다', (tester) async {
    final controller = AppController(const AppSettings(demoMode: true));
    await tester.pumpWidget(KeenonControlApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('매장 목록'), findsOneWidget);
    expect(find.text('데모 레스토랑 1호점'), findsOneWidget);

    await tester.tap(find.text('데모 레스토랑 1호점'));
    await tester.pumpAndSettle();
    expect(find.text('서빙 1호'), findsOneWidget);
  });

  testWidgets('미설정 상태: 설정 화면이 먼저 표시된다', (tester) async {
    final controller = AppController(const AppSettings());
    await tester.pumpWidget(KeenonControlApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Keenon 관제 PoC 설정'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });
}
