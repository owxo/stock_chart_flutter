import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models/candle_data.dart';
import 'models/line_point.dart';

class TencentQuoteDataSource {
  TencentQuoteDataSource({
    http.Client? client,
    Random? random,
    this.timeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _random = random ?? Random(),
        _ownsClient = client == null;

  final http.Client _client;
  final Random _random;
  final bool _ownsClient;
  final Duration timeout;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  Future<List<LinePoint>> fetchMinuteLine(String symbol) async {
    final varName = 'min_data_$symbol';
    final uri = Uri.https(
      'web.ifzq.gtimg.cn',
      '/appstock/app/minute/query',
      {
        '_var': varName,
        'code': symbol,
        'r': _random.nextDouble().toString(),
      },
    );
    final json = await _getJson(uri);
    final data = json['data'];
    if (data is! Map) return const [];
    final symbolData = data[symbol];
    if (symbolData is! Map) return const [];
    final inner = symbolData['data'];
    if (inner is! Map) return const [];

    final dateRaw = (inner['date'] ?? '').toString();
    final dateDigits = dateRaw.replaceAll(RegExp(r'[^0-9]'), '');
    final ymd = dateDigits.length >= 8
        ? dateDigits.substring(0, 8)
        : _toYmd(DateTime.now());
    final list = inner['data'];
    if (list is! List) return const [];

    final result = <LinePoint>[];
    for (final item in list) {
      if (item is! String) continue;
      final parts = item.split(' ');
      if (parts.length < 2) continue;

      final hhmm = parts[0];
      final price = _toDouble(parts[1]);
      if (hhmm.length != 4 || price == null) continue;

      final time = _parseTencentDateTime(ymd, hhmm);
      if (time == null) continue;
      result.add(LinePoint(time: time, value: price));
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  Future<List<LinePoint>> fetchFiveDayLine(String symbol) async {
    final uri = Uri.https(
      'web.ifzq.gtimg.cn',
      '/appstock/app/day/query',
      {'code': symbol},
    );
    final json = await _getJson(uri);
    final data = json['data'];
    if (data is! Map) return const [];
    final symbolData = data[symbol];
    if (symbolData is! Map) return const [];
    final daily = symbolData['data'];
    if (daily is! List) return const [];

    final result = <LinePoint>[];
    for (final day in daily) {
      if (day is! Map) continue;
      final dateRaw = (day['date'] ?? '').toString();
      final ymd = _toYmdDigits(dateRaw);
      final lines = day['data'];
      if (lines is! List) continue;

      for (final item in lines) {
        if (item is! String) continue;
        final parts = item.split(' ');
        if (parts.length < 2) continue;

        final hhmm = parts[0];
        final price = _toDouble(parts[1]);
        if (hhmm.length != 4 || price == null) continue;

        final time = _parseTencentDateTime(ymd, hhmm);
        if (time == null) continue;
        result.add(LinePoint(time: time, value: price));
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  Future<List<CandleData>> fetchKline(
    String symbol, {
    required String period,
    required int count,
  }) async {
    final uri = Uri.https(
      'web.ifzq.gtimg.cn',
      '/appstock/app/fqkline/get',
      {'param': '$symbol,$period,,,$count,qfq'},
    );
    final json = await _getJson(uri);
    final data = json['data'];
    if (data is! Map) return const [];
    final symbolData = data[symbol];
    if (symbolData is! Map) return const [];

    final qfqKey = 'qfq$period';
    final rawList = symbolData[qfqKey] ?? symbolData[period];
    if (rawList is! List) return const [];

    final out = <CandleData>[];
    for (final row in rawList) {
      if (row is! List || row.length < 5) continue;

      final date = DateTime.tryParse(row[0].toString());
      final open = _toDouble(row[1]);
      final close = _toDouble(row[2]);
      final high = _toDouble(row[3]);
      final low = _toDouble(row[4]);
      final volume = row.length > 5 ? _toDouble(row[5]) : null;

      if (date == null ||
          open == null ||
          close == null ||
          high == null ||
          low == null) {
        continue;
      }

      out.add(
        CandleData(
          time: date,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: volume,
        ),
      );
    }

    return out;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = _decodeJsonOrJsonp(response.body.trim());
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response');
    }
    return decoded;
  }
}

dynamic _decodeJsonOrJsonp(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    final eq = body.indexOf('=');
    final start = eq >= 0 ? eq + 1 : 0;
    final end = body.endsWith(';') ? body.length - 1 : body.length;
    final payload = body.substring(start, end).trim();
    return jsonDecode(payload);
  }
}

String _toYmd(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

DateTime? _parseTencentDateTime(String yyyymmdd, String hhmm) {
  final ymd = _toYmdDigits(yyyymmdd);
  if (ymd.length != 8 || hhmm.length != 4) return null;
  final y = int.tryParse(ymd.substring(0, 4));
  final m = int.tryParse(ymd.substring(4, 6));
  final d = int.tryParse(ymd.substring(6, 8));
  final hh = int.tryParse(hhmm.substring(0, 2));
  final mm = int.tryParse(hhmm.substring(2, 4));
  if (y == null || m == null || d == null || hh == null || mm == null) {
    return null;
  }
  return DateTime(y, m, d, hh, mm);
}

double? _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _toYmdDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');
