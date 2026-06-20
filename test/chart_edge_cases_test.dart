import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_chart_flutter/stock_chart_flutter.dart';

void main() {
  testWidgets('StockCandlestickChart handles empty data', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: StockCandlestickChart(data: []),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('StockCandlestickChart handles flat prices and empty MA colors',
      (tester) async {
    final data = [
      CandleData(
        time: DateTime(2026, 1, 1),
        open: 10,
        high: 10,
        low: 10,
        close: 10,
      ),
      CandleData(
        time: DateTime(2026, 1, 2),
        open: 10,
        high: 10,
        low: 10,
        close: 10,
      ),
    ];

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: StockCandlestickChart(
            data: data,
            maPeriods: const [2],
            theme: const StockChartTheme(maColors: []),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('StockLineChart handles empty, single and flat data updates',
      (tester) async {
    Widget build(List<LinePoint> data) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 320,
          height: 240,
          child: StockLineChart(data: data),
        ),
      );
    }

    await tester.pumpWidget(build(const []));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      build([LinePoint(time: DateTime(2026, 1, 1, 9, 30), value: 10)]),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      build([
        LinePoint(time: DateTime(2026, 1, 1, 9, 30), value: 10),
        LinePoint(time: DateTime(2026, 1, 1, 9, 31), value: 10),
      ]),
    );
    expect(tester.takeException(), isNull);
  });
}
