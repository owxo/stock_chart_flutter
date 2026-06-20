import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'package:stock_chart_flutter_example/main.dart';

void main() {
  testWidgets('Example app renders timeframe tabs',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const ExampleApp());

    expect(find.text('分时'), findsWidgets);
    expect(find.text('五日'), findsOneWidget);
    expect(find.text('日K'), findsWidgets);
    expect(find.text('周K'), findsWidgets);
    expect(find.text('月K'), findsWidgets);
    expect(find.text('sz001896 / sh600519 / 600519'), findsOneWidget);
    expect(find.text('卖5'), findsNothing);
    expect(find.text('买1'), findsNothing);
    expect(find.text('腾讯数据加载失败，暂无可展示行情'), findsNothing);

    await tester.tap(find.text('五日'));
    await tester.pumpAndSettle();

    expect(find.text('五日'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
