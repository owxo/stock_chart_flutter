import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stock_chart_flutter/src/tencent_quote_data_source.dart';
import 'package:stock_chart_flutter/stock_chart_flutter.dart';

void main() {
  test('fetchMinuteLine parses Tencent JSONP minute data', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'web.ifzq.gtimg.cn');
      expect(request.url.path, '/appstock/app/minute/query');
      expect(request.url.queryParameters['code'], 'sz000001');

      return http.Response(
        'min_data_sz000001={"data":{"sz000001":{"data":{"date":"20260620","data":["0930 10.20","0931 10.25"]}}}};',
        200,
      );
    });
    final source = TencentQuoteDataSource(client: client);

    final points = await source.fetchMinuteLine('sz000001');

    expect(
      points,
      equals([
        LinePoint(time: DateTime(2026, 6, 20, 9, 30), value: 10.20),
        LinePoint(time: DateTime(2026, 6, 20, 9, 31), value: 10.25),
      ]),
    );
  });

  test('fetchFiveDayLine parses Tencent day query data', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/appstock/app/day/query');

      return http.Response(
        jsonEncode({
          'data': {
            'sz000001': {
              'data': [
                {
                  'date': '2026-06-19',
                  'data': ['1459 10.10', '1500 10.15'],
                },
                {
                  'date': '20260620',
                  'data': ['0930 10.20'],
                },
              ],
            },
          },
        }),
        200,
      );
    });
    final source = TencentQuoteDataSource(client: client);

    final points = await source.fetchFiveDayLine('sz000001');

    expect(points.length, 3);
    expect(points.first,
        LinePoint(time: DateTime(2026, 6, 19, 14, 59), value: 10.10));
    expect(points.last,
        LinePoint(time: DateTime(2026, 6, 20, 9, 30), value: 10.20));
  });

  test('fetchKline parses Tencent kline data', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/appstock/app/fqkline/get');
      expect(request.url.queryParameters['param'], 'sz000001,day,,,2,qfq');

      return http.Response(
        jsonEncode({
          'data': {
            'sz000001': {
              'qfqday': [
                ['2026-06-19', '10', '11', '12', '9', '1000'],
                ['2026-06-20', '11', '10', '12', '9.5', '1200'],
              ],
            },
          },
        }),
        200,
      );
    });
    final source = TencentQuoteDataSource(client: client);

    final candles = await source.fetchKline(
      'sz000001',
      period: 'day',
      count: 2,
    );

    expect(
      candles,
      equals([
        CandleData(
          time: DateTime(2026, 6, 19),
          open: 10,
          high: 12,
          low: 9,
          close: 11,
          volume: 1000,
        ),
        CandleData(
          time: DateTime(2026, 6, 20),
          open: 11,
          high: 12,
          low: 9.5,
          close: 10,
          volume: 1200,
        ),
      ]),
    );
  });

  test('throws for non-success HTTP status', () async {
    final client = MockClient((_) async => http.Response('not found', 404));
    final source = TencentQuoteDataSource(client: client);

    expect(
      () => source.fetchMinuteLine('sz000001'),
      throwsA(isA<Exception>()),
    );
  });
}
