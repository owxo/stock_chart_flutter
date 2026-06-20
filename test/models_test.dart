import 'package:flutter_test/flutter_test.dart';
import 'package:stock_chart_flutter/stock_chart_flutter.dart';

void main() {
  group('CandleData', () {
    test('reports bullish candles when close is greater than or equal to open',
        () {
      final bullish = CandleData(
        time: DateTime(2026, 1, 1),
        open: 10,
        high: 12,
        low: 9,
        close: 10,
      );
      final bearish = CandleData(
        time: DateTime(2026, 1, 2),
        open: 11,
        high: 12,
        low: 9,
        close: 10,
      );

      expect(bullish.isBullish, isTrue);
      expect(bearish.isBullish, isFalse);
    });

    test('compares by value', () {
      final a = CandleData(
        time: DateTime(2026, 1, 1),
        open: 10,
        high: 12,
        low: 9,
        close: 11,
        volume: 12000,
      );
      final b = CandleData(
        time: DateTime(2026, 1, 1),
        open: 10,
        high: 12,
        low: 9,
        close: 11,
        volume: 12000,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('CandleData'));
    });
  });

  group('LinePoint', () {
    test('compares by value', () {
      final a = LinePoint(time: DateTime(2026, 1, 1, 9, 30), value: 10.2);
      final b = LinePoint(time: DateTime(2026, 1, 1, 9, 30), value: 10.2);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('LinePoint'));
    });
  });
}
