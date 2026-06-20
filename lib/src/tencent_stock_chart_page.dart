import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'models/candle_data.dart';
import 'models/line_point.dart';
import 'stock_candlestick_chart.dart';
import 'stock_chart_theme.dart';
import 'tencent_quote_data_source.dart';

part 'tencent_stock_chart_painters.dart';
part 'tencent_stock_chart_right_panel.dart';

const _intradayTotalSlots = 240;

enum _TimeAxisMode { intraday, multiDay }

enum _KPeriod { day, week, month }

class TencentStockChartPage extends StatefulWidget {
  const TencentStockChartPage({
    super.key,
    this.symbol = '',
    this.autoRefreshSeconds = 3,
  });

  final String symbol;
  final int autoRefreshSeconds;

  @override
  State<TencentStockChartPage> createState() => _TencentStockChartPageState();
}

class _TencentStockChartPageState extends State<TencentStockChartPage>
    with TickerProviderStateMixin {
  static const _tabs = ['分时', '日K', '周K', '月K', '五日'];
  static const _chartTheme = StockChartTheme(
    backgroundColor: Color(0xFFFFFFFF),
    gridColor: Color(0xFFE6EBF2),
    textColor: Color(0xFF6B7785),
    bullColor: Color(0xFFE53935),
    bearColor: Color(0xFF10B981),
    crosshairColor: Color(0x668AA0B8),
    lineColor: Color(0xFF1F6FFF),
    maColors: [
      Color(0xFFF4B400),
      Color(0xFF1F6FFF),
      Color(0xFF8B5CF6),
    ],
  );

  late final TabController _tabController;
  late final TencentQuoteDataSource _quoteDataSource;
  Timer? _intradayRefreshTimer;

  List<CandleData> _dayCandles = const [];
  List<CandleData> _weekCandles = const [];
  List<CandleData> _monthCandles = const [];
  List<LinePoint> _intradayLine = const [];
  List<LinePoint> _fiveDayLine = const [];
  double? _referencePrice;
  int? _intradayFocusIndex;
  int? _fiveDayFocusIndex;
  int? _dayKFocusIndex;
  int? _weekKFocusIndex;
  int? _monthKFocusIndex;

  int _intradayRightTab = 0;

  bool _isLoadingRemote = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _quoteDataSource = TencentQuoteDataSource();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_handleTabChanged);
    if (_hasSymbol) {
      _loadTencentData();
      _startIntradayAutoRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant TencentStockChartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.symbol != widget.symbol) {
      _intradayRefreshTimer?.cancel();
      _clearMarketData();
      if (_hasSymbol) {
        _loadTencentData();
        _startIntradayAutoRefresh();
      }
      return;
    }

    if (oldWidget.autoRefreshSeconds != widget.autoRefreshSeconds &&
        _hasSymbol) {
      _startIntradayAutoRefresh();
    }
  }

  @override
  void dispose() {
    _intradayRefreshTimer?.cancel();
    _quoteDataSource.close();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (mounted) {
      setState(() {
        if (_tabController.index != 0) {
          _intradayFocusIndex = null;
        }
        if (_tabController.index != 4) {
          _fiveDayFocusIndex = null;
        }
        if (_tabController.index != 1) {
          _dayKFocusIndex = null;
        }
        if (_tabController.index != 2) {
          _weekKFocusIndex = null;
        }
        if (_tabController.index != 3) {
          _monthKFocusIndex = null;
        }
      });
    }
    if (_tabController.index == 0) {
      _refreshIntradayOnly();
    }
  }

  bool get _hasSymbol => widget.symbol.trim().isNotEmpty;

  void _clearMarketData() {
    setState(() {
      _dayCandles = const [];
      _weekCandles = const [];
      _monthCandles = const [];
      _intradayLine = const [];
      _fiveDayLine = const [];
      _referencePrice = null;
      _intradayFocusIndex = null;
      _fiveDayFocusIndex = null;
      _dayKFocusIndex = null;
      _weekKFocusIndex = null;
      _monthKFocusIndex = null;
      _isLoadingRemote = false;
      _remoteError = null;
    });
  }

  void _startIntradayAutoRefresh() {
    _intradayRefreshTimer?.cancel();
    final refreshSeconds =
        widget.autoRefreshSeconds < 1 ? 1 : widget.autoRefreshSeconds;
    _intradayRefreshTimer = Timer.periodic(
      Duration(seconds: refreshSeconds),
      (_) => _refreshIntradayOnly(),
    );
  }

  Future<void> _refreshIntradayOnly() async {
    if (!mounted || !_hasSymbol) return;
    try {
      var intraday = await _quoteDataSource.fetchMinuteLine(widget.symbol);
      final fiveDay = await _quoteDataSource.fetchFiveDayLine(widget.symbol);
      final latestFromFiveDay = _pickLatestDayLine(fiveDay);
      if (latestFromFiveDay.isNotEmpty) {
        final intradayDate = _latestDateOf(intraday);
        final fiveDate = _latestDateOf(latestFromFiveDay);
        if (intraday.isEmpty ||
            (intradayDate != null &&
                fiveDate != null &&
                fiveDate.isAfter(intradayDate))) {
          intraday = latestFromFiveDay;
        }
      }
      if (!mounted || intraday.isEmpty) return;
      setState(() {
        _intradayLine = intraday;
        _referencePrice = _inferReferencePrice(_dayCandles, intraday);
      });
    } catch (_) {
      // Keep previous data when refresh request fails.
    }
  }

  void _updateIntradayFocus(
      Offset localPos, Size chartSize, List<LinePoint> points) {
    if (points.isEmpty) return;
    const leftPad = 7.0;
    const rightPad = 7.0;
    final usableWidth = mathMax(1.0, chartSize.width - leftPad - rightPad);
    final slot = (((localPos.dx - leftPad) / usableWidth).clamp(0.0, 1.0) *
            _intradayTotalSlots)
        .round();

    var idx = 0;
    var best = (_intradayTradingSlot(points.first.time) - slot).abs();
    for (var i = 1; i < points.length; i++) {
      final delta = (_intradayTradingSlot(points[i].time) - slot).abs();
      if (delta < best) {
        best = delta;
        idx = i;
      }
    }
    if (_intradayFocusIndex != idx) {
      setState(() => _intradayFocusIndex = idx);
    }
  }

  void _clearIntradayFocus() {
    if (_intradayFocusIndex != null) {
      setState(() => _intradayFocusIndex = null);
    }
  }

  void _updateFiveDayFocus(
      Offset localPos, Size chartSize, List<LinePoint> points) {
    final idx = _nearestLinePointIndex(
      localPos.dx,
      chartSize.width,
      points,
      mode: _TimeAxisMode.multiDay,
    );
    if (idx == null) return;
    if (_fiveDayFocusIndex != idx) {
      setState(() => _fiveDayFocusIndex = idx);
    }
  }

  void _clearFiveDayFocus() {
    if (_fiveDayFocusIndex != null) {
      setState(() => _fiveDayFocusIndex = null);
    }
  }

  int? _kFocusIndexOf(_KPeriod period) {
    switch (period) {
      case _KPeriod.day:
        return _dayKFocusIndex;
      case _KPeriod.week:
        return _weekKFocusIndex;
      case _KPeriod.month:
        return _monthKFocusIndex;
    }
  }

  void _setKFocusIndex(_KPeriod period, int? value) {
    switch (period) {
      case _KPeriod.day:
        _dayKFocusIndex = value;
      case _KPeriod.week:
        _weekKFocusIndex = value;
      case _KPeriod.month:
        _monthKFocusIndex = value;
    }
  }

  void _updateKFocus(
      Offset localPos, Size chartSize, List<CandleData> data, _KPeriod period) {
    if (data.isEmpty) return;
    const leftPad = 6.0;
    const rightPad = 42.0;
    final usableWidth = mathMax(1.0, chartSize.width - leftPad - rightPad);
    final t = ((localPos.dx - leftPad) / usableWidth).clamp(0.0, 1.0);
    final idx = (t * (data.length - 1)).round().clamp(0, data.length - 1);
    if (_kFocusIndexOf(period) != idx) {
      setState(() => _setKFocusIndex(period, idx));
    }
  }

  void _clearKFocus(_KPeriod period) {
    if (_kFocusIndexOf(period) != null) {
      setState(() => _setKFocusIndex(period, null));
    }
  }

  Future<void> _loadTencentData() async {
    if (!_hasSymbol) {
      _clearMarketData();
      return;
    }

    setState(() {
      _isLoadingRemote = true;
      _remoteError = null;
    });

    try {
      final intraday = await _quoteDataSource.fetchMinuteLine(widget.symbol);
      final fiveDay = await _quoteDataSource.fetchFiveDayLine(widget.symbol);
      final day = await _quoteDataSource.fetchKline(
        widget.symbol,
        period: 'day',
        count: 320,
      );
      final week = await _quoteDataSource.fetchKline(
        widget.symbol,
        period: 'week',
        count: 160,
      );
      final month = await _quoteDataSource.fetchKline(
        widget.symbol,
        period: 'month',
        count: 120,
      );

      if (!mounted) return;
      setState(() {
        if (intraday.isNotEmpty) _intradayLine = intraday;
        if (fiveDay.isNotEmpty) _fiveDayLine = fiveDay;
        if (day.isNotEmpty) _dayCandles = day;
        if (week.isNotEmpty) {
          _weekCandles = week;
        } else {
          _weekCandles = _aggregateByWeek(_dayCandles);
        }
        if (month.isNotEmpty) {
          _monthCandles = month;
        } else {
          _monthCandles = _aggregateByMonth(_dayCandles);
        }
        _referencePrice = _inferReferencePrice(
          day.isNotEmpty ? day : _dayCandles,
          intraday.isNotEmpty ? intraday : _intradayLine,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _remoteError = '腾讯数据加载失败，暂无可展示行情';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingRemote = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildPeriodTabs(),
          if (_isLoadingRemote)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 1),
          if (_remoteError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    _remoteError!,
                    style: const TextStyle(color: Color(0xFF6B7785)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = MediaQuery.of(context).size.width;
                final targetHeight = screenWidth * 1.06;
                final chartHeight = mathMax(
                  260.0,
                  mathMin(targetHeight, constraints.maxHeight),
                );
                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: chartHeight,
                    child: TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildIntradayReferenceChart(_intradayLine),
                        _buildKCompositeChart(_dayCandles, _KPeriod.day),
                        _buildKCompositeChart(_weekCandles, _KPeriod.week),
                        _buildKCompositeChart(_monthCandles, _KPeriod.month),
                        _buildFiveDayChart(_fiveDayLine),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodTabs() {
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => _tabController.animateTo(i),
                child: SizedBox(
                  height: 44,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _tabs[i],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: _tabController.index == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _tabController.index == i
                              ? const Color(0xFF222222)
                              : const Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        height: 3.5,
                        width: 22,
                        decoration: BoxDecoration(
                          color: _tabController.index == i
                              ? const Color(0xFFF44336)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFiveDayChart(List<LinePoint> data) {
    final avgLine = _buildAvgLine(data);
    final volumes = _buildVolumeSeries(data);
    final idx = _fiveDayFocusIndex;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chartSize = Size(
                constraints.maxWidth,
                constraints.maxHeight,
              );
              return MouseRegion(
                opaque: true,
                onExit: (_) => _clearFiveDayFocus(),
                child: Listener(
                  onPointerUp: (_) => _clearFiveDayFocus(),
                  onPointerCancel: (_) => _clearFiveDayFocus(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _updateFiveDayFocus(
                        details.localPosition, chartSize, data),
                    onPanStart: (details) => _updateFiveDayFocus(
                        details.localPosition, chartSize, data),
                    onPanUpdate: (details) => _updateFiveDayFocus(
                        details.localPosition, chartSize, data),
                    onPanEnd: (_) => _clearFiveDayFocus(),
                    onPanCancel: _clearFiveDayFocus,
                    onTapUp: (_) => _clearFiveDayFocus(),
                    onTapCancel: _clearFiveDayFocus,
                    child: Container(
                      color: const Color(0xFFF4F4F4),
                      child: Column(
                        children: [
                          Expanded(
                            flex: 4,
                            child: CustomPaint(
                              painter: _IntradayPricePainter(
                                points: data,
                                avgLine: avgLine,
                                gridColor: const Color(0xFFDDE2E8),
                                lineColor: const Color(0xFF111111),
                                avgColor: const Color(0xFFF59E0B),
                                referencePrice: _referencePrice,
                                axisMode: _TimeAxisMode.multiDay,
                                focusIndex: idx,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Expanded(
                            child: CustomPaint(
                              painter: _IntradayVolumePainter(
                                points: data,
                                volumes: volumes,
                                gridColor: const Color(0xFFDDE2E8),
                                upColor: const Color(0xFFE53935),
                                downColor: const Color(0xFF22A06B),
                                axisMode: _TimeAxisMode.multiDay,
                                focusIndex: idx,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKCompositeChart(List<CandleData> data, _KPeriod period) {
    final trend1 = _buildIndicatorSeries(data, seed: 1);
    final trend2 = _buildIndicatorSeries(data, seed: 2);
    final idx = _kFocusIndexOf(period);

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          opaque: true,
          onExit: (_) => _clearKFocus(period),
          child: Listener(
            onPointerUp: (_) => _clearKFocus(period),
            onPointerCancel: (_) => _clearKFocus(period),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _updateKFocus(details.localPosition, chartSize, data, period),
              onPanStart: (details) =>
                  _updateKFocus(details.localPosition, chartSize, data, period),
              onPanUpdate: (details) =>
                  _updateKFocus(details.localPosition, chartSize, data, period),
              onPanEnd: (_) => _clearKFocus(period),
              onPanCancel: () => _clearKFocus(period),
              onTapUp: (_) => _clearKFocus(period),
              onTapCancel: () => _clearKFocus(period),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        Expanded(
                          flex: 58,
                          child: StockCandlestickChart(
                            data: data,
                            theme: _chartTheme,
                            maPeriods: const [5, 10, 20, 30],
                            padding: const EdgeInsets.fromLTRB(6, 8, 42, 16),
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE6E6E6)),
                        Expanded(
                          flex: 18,
                          child: CustomPaint(
                            painter: _SimpleLinePairPainter(
                              a: trend1,
                              b: trend2,
                              aColor: const Color(0xFFE69500),
                              bColor: const Color(0xFF4285F4),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE6E6E6)),
                        Expanded(
                          flex: 24,
                          child: CustomPaint(
                            painter: _VolumeMALinePainter(
                              candles: data,
                              ma5Color: const Color(0xFF6A6A6A),
                              ma10Color: const Color(0xFF8B2CFF),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (idx != null && idx >= 0 && idx < data.length)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _KCompositeCrosshairOverlayPainter(
                            candles: data,
                            focusIndex: idx,
                            chartPadding:
                                const EdgeInsets.fromLTRB(6, 8, 42, 16),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIntradayReferenceChart(List<LinePoint> data) {
    final avgLine = _buildAvgLine(data);
    final volumes = _buildVolumeSeries(data);
    final orderBook = _buildOrderBookRows(data);
    final trades = _buildTradeRows(data);
    final referencePrice =
        _referencePrice ?? (data.isNotEmpty ? data.first.value : null);
    final limitUp = _referencePrice == null ? null : _referencePrice! * 1.10;
    final limitDown = _referencePrice == null ? null : _referencePrice! * 0.90;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    border: Border.all(color: const Color(0xFFE6EBF2)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isPhoneLike = constraints.maxWidth < 620;
                      final targetWidth =
                          constraints.maxWidth * (isPhoneLike ? 0.27 : 0.285);
                      final maxAllowed = constraints.maxWidth - 170;
                      final rightWidth = maxAllowed <= 120
                          ? (constraints.maxWidth * 0.42).clamp(100.0, 180.0)
                          : mathMin(targetWidth, maxAllowed)
                              .clamp(120.0, 240.0);
                      return Row(
                        children: [
                          Expanded(
                            child: Container(
                              color: const Color(0xFFF4F4F4),
                              child: LayoutBuilder(
                                builder: (context, chartConstraints) {
                                  final chartSize = Size(
                                    chartConstraints.maxWidth,
                                    chartConstraints.maxHeight,
                                  );
                                  final idx = _intradayFocusIndex;
                                  return MouseRegion(
                                    opaque: true,
                                    onExit: (_) => _clearIntradayFocus(),
                                    child: Listener(
                                      onPointerUp: (_) => _clearIntradayFocus(),
                                      onPointerCancel: (_) =>
                                          _clearIntradayFocus(),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: (details) =>
                                            _updateIntradayFocus(
                                          details.localPosition,
                                          chartSize,
                                          data,
                                        ),
                                        onPanStart: (details) =>
                                            _updateIntradayFocus(
                                          details.localPosition,
                                          chartSize,
                                          data,
                                        ),
                                        onPanUpdate: (details) =>
                                            _updateIntradayFocus(
                                          details.localPosition,
                                          chartSize,
                                          data,
                                        ),
                                        onPanEnd: (_) => _clearIntradayFocus(),
                                        onPanCancel: _clearIntradayFocus,
                                        onTapUp: (_) => _clearIntradayFocus(),
                                        onTapCancel: _clearIntradayFocus,
                                        child: Stack(
                                          children: [
                                            Column(
                                              children: [
                                                Expanded(
                                                  flex: 7,
                                                  child: CustomPaint(
                                                    painter:
                                                        _IntradayPricePainter(
                                                      points: data,
                                                      avgLine: avgLine,
                                                      gridColor: const Color(
                                                          0xFFE6EBF2),
                                                      lineColor: const Color(
                                                          0xFF111111),
                                                      avgColor: const Color(
                                                          0xFFF59E0B),
                                                      referencePrice:
                                                          referencePrice,
                                                      focusIndex: idx,
                                                    ),
                                                    child:
                                                        const SizedBox.expand(),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: CustomPaint(
                                                    painter:
                                                        _IntradayVolumePainter(
                                                      points: data,
                                                      volumes: volumes,
                                                      gridColor: const Color(
                                                          0xFFE6EBF2),
                                                      upColor:
                                                          _chartTheme.bullColor,
                                                      downColor:
                                                          _chartTheme.bearColor,
                                                      focusIndex: idx,
                                                    ),
                                                    child:
                                                        const SizedBox.expand(),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Container(width: 1, color: const Color(0xFFDADADA)),
                          SizedBox(
                            width: rightWidth,
                            child: Container(
                              color: const Color(0xFFFAFAFA),
                              child: _buildIntradayRightPanel(
                                orderBook: orderBook,
                                trades: trades,
                                referencePrice: referencePrice,
                                limitUp: limitUp,
                                limitDown: limitDown,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _priceColor(double price, double? referencePrice) {
    if (referencePrice == null) return const Color(0xFFE53935);
    if ((price - referencePrice).abs() < 1e-8) return const Color(0xFF6B7785);
    return price > referencePrice
        ? const Color(0xFFE53935)
        : const Color(0xFF22A06B);
  }

  void _setIntradayRightTab(int value) {
    setState(() => _intradayRightTab = value);
  }
}

List<double> _buildAvgLine(List<LinePoint> data) {
  final out = <double>[];
  var sum = 0.0;
  for (var i = 0; i < data.length; i++) {
    sum += data[i].value;
    out.add(sum / (i + 1));
  }
  return out;
}

List<double> _buildVolumeSeries(List<LinePoint> data) {
  if (data.isEmpty) return const [];
  final out = <double>[12000];
  for (var i = 1; i < data.length; i++) {
    final movement = (data[i].value - data[i - 1].value).abs();
    out.add(3000 + movement * 30000 + (i % 20) * 90);
  }
  return out;
}

List<double> _buildIndicatorSeries(List<CandleData> data, {required int seed}) {
  if (data.isEmpty) return const [];
  final out = <double>[];
  var acc = 0.0;
  for (var i = 0; i < data.length; i++) {
    final v = (data[i].close - data[i].open).abs() * (seed * 0.4 + 0.8);
    acc = acc * 0.86 + v;
    out.add(acc);
  }
  return out;
}

double? _inferReferencePrice(
  List<CandleData> dayCandles,
  List<LinePoint> intraday,
) {
  if (dayCandles.length > 1) {
    return dayCandles[dayCandles.length - 2].close;
  }
  if (dayCandles.isNotEmpty) {
    return dayCandles.last.open;
  }
  if (intraday.isNotEmpty) {
    return intraday.first.value;
  }
  return null;
}

List<_OrderLevelRow> _buildOrderBookRows(List<LinePoint> data) {
  if (data.isEmpty) return const [];
  final last = data.last.value;
  final rows = <_OrderLevelRow>[];
  for (var i = 5; i >= 1; i--) {
    final price = (last + (i * 0.01)).toStringAsFixed(2);
    rows.add(
        _OrderLevelRow('卖$i', double.parse(price), '${1200 + i * 260}', true));
  }
  for (var i = 1; i <= 5; i++) {
    final price = (last - (i * 0.01)).toStringAsFixed(2);
    rows.add(
        _OrderLevelRow('买$i', double.parse(price), '${1000 + i * 210}', false));
  }
  return rows;
}

List<_TradeRow> _buildTradeRows(List<LinePoint> data) {
  if (data.length < 2) return const [];
  final rows = <_TradeRow>[];
  final start = data.length > 16 ? data.length - 16 : 1;
  for (var i = start; i < data.length; i++) {
    final p = data[i];
    final prev = data[i - 1];
    rows.add(
      _TradeRow(
        '${p.time.hour.toString().padLeft(2, '0')}:${p.time.minute.toString().padLeft(2, '0')}',
        p.value,
        '${500 + (i % 9) * 130}',
        p.value >= prev.value,
      ),
    );
  }
  return rows.reversed.toList();
}

class _OrderLevelRow {
  const _OrderLevelRow(this.label, this.price, this.volumeText, this.isSell);

  final String label;
  final double price;
  final String volumeText;
  final bool isSell;
}

class _TradeRow {
  const _TradeRow(this.time, this.price, this.volumeText, this.isUp);

  final String time;
  final double price;
  final String volumeText;
  final bool isUp;
}

class _TradeStatRow extends StatelessWidget {
  const _TradeStatRow(this.label, this.value, this.ratio);

  final String label;
  final String value;
  final String ratio;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFD1D5DB), width: 0.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 24,
              child: Center(
                child: Text(
                  label,
                  style:
                      const TextStyle(fontSize: 10.5, color: Color(0xFF111827)),
                ),
              ),
            ),
            Container(width: 0.8, color: const Color(0xFFD1D5DB)),
            Expanded(
              flex: 52,
              child: Center(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 10.5, color: Color(0xFF111827)),
                ),
              ),
            ),
            Container(width: 0.8, color: const Color(0xFFD1D5DB)),
            Expanded(
              flex: 24,
              child: Center(
                child: Text(
                  ratio,
                  style:
                      const TextStyle(fontSize: 10.5, color: Color(0xFF111827)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int _intradayTradingSlot(DateTime t) {
  final minute = t.hour * 60 + t.minute;
  const morningStart = 9 * 60 + 30;
  const morningEnd = 11 * 60 + 30;
  const afternoonStart = 13 * 60;
  const afternoonEnd = 15 * 60;

  if (minute <= morningStart) return 0;
  if (minute <= morningEnd) return minute - morningStart;
  if (minute < afternoonStart) return 120;
  if (minute <= afternoonEnd) return 120 + (minute - afternoonStart);
  return _intradayTotalSlots;
}

int? _nearestLinePointIndex(
  double localDx,
  double chartWidth,
  List<LinePoint> points, {
  required _TimeAxisMode mode,
}) {
  if (points.isEmpty) return null;
  const leftPad = 7.0;
  const rightPad = 7.0;
  final usableWidth = mathMax(1.0, chartWidth - leftPad - rightPad);
  final totalSlots = _projectedTotalSlots(points, mode);
  final target =
      ((localDx - leftPad) / usableWidth).clamp(0.0, 1.0) * totalSlots;
  final slots = _projectedSlots(points, mode);
  var idx = 0;
  var best = (slots.first - target).abs();
  for (var i = 1; i < slots.length; i++) {
    final delta = (slots[i] - target).abs();
    if (delta < best) {
      best = delta;
      idx = i;
    }
  }
  return idx;
}

List<double> _projectedSlots(List<LinePoint> points, _TimeAxisMode mode) {
  if (points.isEmpty) return const [];
  if (mode == _TimeAxisMode.intraday) {
    return points
        .map((e) => _intradayTradingSlot(e.time).toDouble())
        .toList(growable: false);
  }
  final days = _uniqueDayKeys(points);
  final dayIndex = <int, int>{for (var i = 0; i < days.length; i++) days[i]: i};
  return points.map((e) {
    final key = e.time.year * 10000 + e.time.month * 100 + e.time.day;
    final idx = dayIndex[key] ?? 0;
    return idx * _intradayTotalSlots + _intradayTradingSlot(e.time).toDouble();
  }).toList(growable: false);
}

double _projectedTotalSlots(List<LinePoint> points, _TimeAxisMode mode) {
  if (points.isEmpty) return _intradayTotalSlots.toDouble();
  if (mode == _TimeAxisMode.intraday) return _intradayTotalSlots.toDouble();
  final dayCount = _uniqueDayKeys(points).length;
  final projectedDays = dayCount < 5 ? 5 : dayCount;
  return mathMax(1.0, projectedDays * _intradayTotalSlots.toDouble());
}

int _timeAxisSegmentCount(List<LinePoint> points, _TimeAxisMode mode) {
  if (mode == _TimeAxisMode.intraday) return 4;
  final dayCount = _uniqueDayKeys(points).length;
  return dayCount < 5 ? 5 : dayCount;
}

List<int> _uniqueDayKeys(List<LinePoint> points) {
  final set = <int>{};
  for (final p in points) {
    set.add(p.time.year * 10000 + p.time.month * 100 + p.time.day);
  }
  final out = set.toList()..sort();
  return out;
}

String _formatMonthDay(int dayKey) {
  final m = ((dayKey ~/ 100) % 100).toString().padLeft(2, '0');
  final d = (dayKey % 100).toString().padLeft(2, '0');
  return '$m/$d';
}

String _formatDateLabel(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime? _latestDateOf(List<LinePoint> points) {
  if (points.isEmpty) return null;
  var latest = points.first.time;
  for (final p in points) {
    if (p.time.isAfter(latest)) latest = p.time;
  }
  return DateTime(latest.year, latest.month, latest.day);
}

List<LinePoint> _pickLatestDayLine(List<LinePoint> points) {
  if (points.isEmpty) return const [];
  DateTime latest = points.first.time;
  for (final p in points) {
    if (p.time.isAfter(latest)) latest = p.time;
  }
  final target = DateTime(latest.year, latest.month, latest.day);
  final result = points.where((p) {
    final d = DateTime(p.time.year, p.time.month, p.time.day);
    return d == target;
  }).toList(growable: false);
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

List<CandleData> _aggregateByWeek(List<CandleData> dayCandles) {
  return _aggregateCandles(
    dayCandles,
    (dt) {
      final monday = dt.subtract(Duration(days: dt.weekday - 1));
      return DateTime(monday.year, monday.month, monday.day);
    },
  );
}

List<CandleData> _aggregateByMonth(List<CandleData> dayCandles) {
  return _aggregateCandles(
    dayCandles,
    (dt) => DateTime(dt.year, dt.month, 1),
  );
}

List<CandleData> _aggregateCandles(
  List<CandleData> source,
  DateTime Function(DateTime) bucketKey,
) {
  if (source.isEmpty) return const [];
  final out = <CandleData>[];

  var currentKey = bucketKey(source.first.time);
  var open = source.first.open;
  var high = source.first.high;
  var low = source.first.low;
  var close = source.first.close;
  var volume = source.first.volume ?? 0.0;

  for (var i = 1; i < source.length; i++) {
    final c = source[i];
    final key = bucketKey(c.time);
    if (key == currentKey) {
      high = mathMax(high, c.high);
      low = mathMin(low, c.low);
      close = c.close;
      volume += c.volume ?? 0.0;
      continue;
    }

    out.add(
      CandleData(
        time: currentKey,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ),
    );

    currentKey = key;
    open = c.open;
    high = c.high;
    low = c.low;
    close = c.close;
    volume = c.volume ?? 0.0;
  }

  out.add(
    CandleData(
      time: currentKey,
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
    ),
  );

  return out;
}

double mathMax(double a, double b) => a > b ? a : b;
double mathMin(double a, double b) => a < b ? a : b;
