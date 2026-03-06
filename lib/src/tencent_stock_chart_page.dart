import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'models/candle_data.dart';
import 'models/line_point.dart';
import 'stock_candlestick_chart.dart';
import 'stock_chart_theme.dart';

const _intradayTotalSlots = 240;

enum _TimeAxisMode { intraday, multiDay }

enum _KPeriod { day, week, month }

class TencentStockChartPage extends StatefulWidget {
  const TencentStockChartPage({
    super.key,
    this.symbol = 'sz001896',
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
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _loadMockData();
    _loadTencentData();
    _startIntradayAutoRefresh();
  }

  @override
  void dispose() {
    _intradayRefreshTimer?.cancel();
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
    if (!mounted) return;
    try {
      var intraday = await _fetchMinuteLine(widget.symbol);
      final fiveDay = await _fetchFiveDayLine(widget.symbol);
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

  void _loadMockData() {
    final day = _mockDayCandles(240);
    final intraday = _mockIntradayLine(days: 1, pointsPerDay: 240);
    setState(() {
      _dayCandles = day;
      _weekCandles = _aggregateByWeek(day);
      _monthCandles = _aggregateByMonth(day);
      _intradayLine = intraday;
      _fiveDayLine = _mockIntradayLine(days: 5, pointsPerDay: 240);
      _referencePrice = _inferReferencePrice(day, intraday);
    });
  }

  Future<void> _loadTencentData() async {
    setState(() {
      _isLoadingRemote = true;
      _remoteError = null;
    });

    try {
      final intraday = await _fetchMinuteLine(widget.symbol);
      final fiveDay = await _fetchFiveDayLine(widget.symbol);
      final day = await _fetchKline(widget.symbol, period: 'day', count: 320);
      final week = await _fetchKline(widget.symbol, period: 'week', count: 160);
      final month =
          await _fetchKline(widget.symbol, period: 'month', count: 120);

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
        _remoteError = '腾讯数据加载失败，已回退为本地模拟数据';
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

  Widget _buildIntradayRightPanel({
    required List<_OrderLevelRow> orderBook,
    required List<_TradeRow> trades,
    required double? referencePrice,
    required double? limitUp,
    required double? limitDown,
  }) {
    const baseStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFF6B7785),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 40) {
          return _intradayRightTab == 0
              ? _buildOrderBookList(
                  orderBook,
                  trades,
                  referencePrice,
                  limitUp: limitUp,
                  limitDown: limitDown,
                )
              : _buildTradesList(trades, referencePrice);
        }

        return Column(
          children: [
            Container(
              height: 31,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE6EBF2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _intradayRightTab = 0),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 1),
                          decoration: BoxDecoration(
                            color: _intradayRightTab == 0
                                ? const Color(0xFFFFECEC)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '五档',
                            style: baseStyle.copyWith(
                              color: _intradayRightTab == 0
                                  ? const Color(0xFFE53935)
                                  : baseStyle.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _intradayRightTab = 1),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 1),
                          decoration: BoxDecoration(
                            color: _intradayRightTab == 1
                                ? const Color(0xFFFFECEC)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '成交',
                            style: baseStyle.copyWith(
                              color: _intradayRightTab == 1
                                  ? const Color(0xFFE53935)
                                  : baseStyle.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 1.5,
              width: double.infinity,
              color: const Color(0xFFF5F5F5),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      color: _intradayRightTab == 0
                          ? const Color(0xFFE53935)
                          : Colors.transparent,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: _intradayRightTab == 1
                          ? const Color(0xFFE53935)
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _intradayRightTab == 0
                  ? _buildOrderBookList(
                      orderBook,
                      trades,
                      referencePrice,
                      limitUp: limitUp,
                      limitDown: limitDown,
                    )
                  : _buildTradesList(trades, referencePrice),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrderBookList(
    List<_OrderLevelRow> rows,
    List<_TradeRow> trades,
    double? referencePrice, {
    required double? limitUp,
    required double? limitDown,
  }) {
    final sells = rows.where((e) => e.isSell).toList();
    final buys = rows.where((e) => !e.isSell).toList();
    final topBig = sells.isEmpty
        ? null
        : sells.reduce((a, b) =>
            _parseVolumeValue(a.volumeText) >= _parseVolumeValue(b.volumeText)
                ? a
                : b);
    final bottomBig = buys.isEmpty
        ? null
        : buys.reduce((a, b) =>
            _parseVolumeValue(a.volumeText) >= _parseVolumeValue(b.volumeText)
                ? a
                : b);
    final maxVolume = rows.isEmpty
        ? 1.0
        : rows.map((e) => _parseVolumeValue(e.volumeText)).reduce(mathMax);
    final sellTotal = sells.fold<double>(
      0,
      (sum, row) => sum + _parseVolumeValue(row.volumeText),
    );
    final buyTotal = buys.fold<double>(
      0,
      (sum, row) => sum + _parseVolumeValue(row.volumeText),
    );
    final total = sellTotal + buyTotal;
    final sellRatio = total <= 0 ? 0.5 : (sellTotal / total).clamp(0.05, 0.95);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 120;
        if (compact) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 2),
            children: [
              for (final row in sells.take(3))
                _buildOrderRow(
                  row,
                  maxVolume,
                  referencePrice,
                  limitUp: limitUp,
                  limitDown: limitDown,
                ),
              Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1.2),
                height: 2,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(color: const Color(0xFF16A34A)),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: sellRatio,
                          child: Container(color: const Color(0xFFE53935)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              for (final row in buys.take(3))
                _buildOrderRow(
                  row,
                  maxVolume,
                  referencePrice,
                  limitUp: limitUp,
                  limitDown: limitDown,
                ),
              const SizedBox(height: 4),
              _buildTradeDetailHeader(),
              for (final row in trades.take(3))
                _buildTradeDetailRow(
                  row,
                  referencePrice,
                  emphasizeVolumeColor: true,
                ),
            ],
          );
        }

        return Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFEEF9F1),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  const Text(
                    '大单',
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      topBig == null
                          ? '--'
                          : '${topBig.price.toStringAsFixed(2)}  *${topBig.volumeText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 6,
              child: Column(
                children: [
                  for (final row in sells)
                    Expanded(
                      child: _buildOrderRowFill(
                        row,
                        maxVolume,
                        referencePrice,
                        limitUp: limitUp,
                        limitDown: limitDown,
                      ),
                    ),
                  Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1.2),
                    height: 2,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(1),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(color: const Color(0xFF16A34A)),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: sellRatio,
                              child: Container(color: const Color(0xFFE53935)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final row in buys)
                    Expanded(
                      child: _buildOrderRowFill(
                        row,
                        maxVolume,
                        referencePrice,
                        limitUp: limitUp,
                        limitDown: limitDown,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF0F0),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  const Text(
                    '大单',
                    style: TextStyle(
                      color: Color(0xFFE53935),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      bottomBig == null
                          ? '--'
                          : '${bottomBig.price.toStringAsFixed(2)}  *${bottomBig.volumeText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildTradeDetailHeader(),
            Expanded(
              flex: 2,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: trades.length < 4 ? trades.length : 4,
                itemBuilder: (context, index) {
                  return _buildTradeDetailRow(
                    trades[index],
                    referencePrice,
                    emphasizeVolumeColor: true,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrderRowFill(
    _OrderLevelRow row,
    double maxVolume,
    double? referencePrice, {
    required double? limitUp,
    required double? limitDown,
  }) {
    final volume = _parseVolumeValue(row.volumeText);
    final ratio = maxVolume <= 0 ? 0.2 : (volume / maxVolume).clamp(0.12, 1.0);
    final outOfLimit = (limitUp != null && row.price > limitUp) ||
        (limitDown != null && row.price < limitDown);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0.2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final compact = available < 112;
          final labelW = compact ? 18.0 : 26.0;
          final priceW = compact ? 34.0 : 46.0;
          final gap = compact ? 2.0 : 3.0;
          final volW = mathMax(18.0, available - labelW - priceW - gap);

          return Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFF0F2F5)),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: labelW,
                  child: Text(
                    row.label,
                    style: TextStyle(
                      fontSize: compact ? 10 : 10.5,
                      color: const Color(0xFF6B7785),
                      height: 1.2,
                    ),
                  ),
                ),
                SizedBox(
                  width: priceW,
                  child: Text(
                    row.price.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: compact ? 11 : 11.5,
                      fontWeight: FontWeight.w600,
                      color: outOfLimit
                          ? const Color(0xFF9AA5B1)
                          : _priceColor(row.price, referencePrice),
                      height: 1.1,
                    ),
                  ),
                ),
                SizedBox(width: gap),
                SizedBox(
                  width: volW,
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      Container(
                        width: volW * ratio,
                        height: compact ? 14 : 16,
                        color: outOfLimit
                            ? const Color(0xFFEEF1F5)
                            : row.isSell
                                ? const Color(0xFFEAF8EE)
                                : const Color(0xFFFFECEC),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 1.5, horizontal: 1),
                        child: Text(
                          row.volumeText,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: compact ? 10 : 10.5,
                            color: const Color(0xFF111827),
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderRow(
    _OrderLevelRow row,
    double maxVolume,
    double? referencePrice, {
    required double? limitUp,
    required double? limitDown,
  }) {
    final volume = _parseVolumeValue(row.volumeText);
    final ratio = maxVolume <= 0 ? 0.2 : (volume / maxVolume).clamp(0.12, 1.0);
    final outOfLimit = (limitUp != null && row.price > limitUp) ||
        (limitDown != null && row.price < limitDown);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0.4),
      child: SizedBox(
        height: 22.5,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final compact = available < 112;
            final labelW = compact ? 18.0 : 26.0;
            final priceW = compact ? 34.0 : 46.0;
            final gap = compact ? 2.0 : 3.0;
            final volW = mathMax(18.0, available - labelW - priceW - gap);

            return Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF0F2F5)),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: labelW,
                    child: Text(
                      row.label,
                      style: TextStyle(
                        fontSize: compact ? 10 : 10.5,
                        color: const Color(0xFF6B7785),
                        height: 1.2,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: priceW,
                    child: Text(
                      row.price.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: compact ? 11 : 11.5,
                        fontWeight: FontWeight.w600,
                        color: outOfLimit
                            ? const Color(0xFF9AA5B1)
                            : _priceColor(row.price, referencePrice),
                        height: 1.1,
                      ),
                    ),
                  ),
                  SizedBox(width: gap),
                  SizedBox(
                    width: volW,
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        Container(
                          width: volW * ratio,
                          height: compact ? 15 : 16.5,
                          color: outOfLimit
                              ? const Color(0xFFEEF1F5)
                              : row.isSell
                                  ? const Color(0xFFEAF8EE)
                                  : const Color(0xFFFFECEC),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 1.5, horizontal: 1),
                          child: Text(
                            row.volumeText,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: compact ? 10 : 10.5,
                              color: const Color(0xFF111827),
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  double _parseVolumeValue(String text) {
    final t = text.trim();
    if (t.endsWith('万')) {
      final raw = double.tryParse(t.substring(0, t.length - 1)) ?? 0.0;
      return raw * 10000;
    }
    return double.tryParse(t.replaceAll(',', '')) ?? 0.0;
  }

  Widget _buildTradesList(List<_TradeRow> trades, double? referencePrice) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        if (compact) {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 2),
            itemCount: trades.length < 4 ? trades.length : 4,
            itemBuilder: (context, index) {
              final row = trades[index];
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0.5),
                child: SizedBox(
                  height: 22,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 32,
                            child: Text(
                              row.time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6B7785),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 28,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  row.price.toStringAsFixed(2),
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: referencePrice == null
                                        ? (row.isUp
                                            ? const Color(0xFFE53935)
                                            : const Color(0xFF22A06B))
                                        : _priceColor(
                                            row.price, referencePrice),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 40,
                            child: Text(
                              row.volumeText,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              );
            },
          );
        }

        final panelHeight = constraints.maxHeight;
        final pieHeight = (panelHeight * 0.16).clamp(56.0, 78.0);
        final statsHeight = (panelHeight * 0.34).clamp(104.0, 186.0);
        final shouldUseScrollable = panelHeight < 290;

        if (shouldUseScrollable) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildTradeSummary(
                  pieHeight: pieHeight, statsHeight: statsHeight),
              _buildTradeDetailHeader(),
              const Divider(height: 1, color: Color(0xFFE6EBF2)),
              for (final row in trades.take(20))
                _buildTradeDetailRow(
                  row,
                  referencePrice,
                  emphasizeVolumeColor: true,
                ),
            ],
          );
        }

        return Column(
          children: [
            _buildTradeSummary(pieHeight: pieHeight, statsHeight: statsHeight),
            _buildTradeDetailHeader(),
            const Divider(height: 1, color: Color(0xFFE6EBF2)),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: trades.length,
                itemBuilder: (context, index) {
                  return _buildTradeDetailRow(
                    trades[index],
                    referencePrice,
                    emphasizeVolumeColor: true,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTradeSummary({
    required double pieHeight,
    required double statsHeight,
  }) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          child: const Text(
            '成交统计',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF4B5563),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: pieHeight,
          child: Row(
            children: [
              const Expanded(
                child: Center(
                  child: Text(
                    '主\n动\n卖',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 82,
                child: CustomPaint(
                  painter: _TradePiePainter(),
                  child: const SizedBox.expand(),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    '主\n动\n买',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE53935),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: statsHeight,
          margin: const EdgeInsets.fromLTRB(2, 2, 2, 4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: statsHeight / 2,
                child: Container(width: 2, color: const Color(0xFFE53935)),
              ),
              Positioned(
                left: 0,
                top: statsHeight / 2,
                bottom: 0,
                child: Container(width: 2, color: const Color(0xFF16A34A)),
              ),
              const Column(
                children: [
                  _TradeStatRow('特大', '11.05万', '7%'),
                  _TradeStatRow('大单', '16.68万', '10%'),
                  _TradeStatRow('中单', '29.09万', '18%'),
                  _TradeStatRow('小单', '30.89万', '19%'),
                  _TradeStatRow('特大', '82024', '5%'),
                  _TradeStatRow('大单', '10.69万', '7%'),
                  _TradeStatRow('中单', '25.48万', '16%'),
                  _TradeStatRow('小单', '28.37万', '18%'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTradeDetailHeader() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF1F1F1),
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: const Text(
        '明细  ▴',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10.5,
          color: Color(0xFF6B7280),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTradeDetailRow(
    _TradeRow row,
    double? referencePrice, {
    required bool emphasizeVolumeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0.5),
      child: SizedBox(
        height: 22.5,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 112;
            return Row(
              children: [
                Expanded(
                  flex: 32,
                  child: Text(
                    row.time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 9.5 : 10,
                      color: const Color(0xFF6B7785),
                    ),
                  ),
                ),
                Expanded(
                  flex: 28,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        row.price.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontSize: compact ? 10.5 : 11,
                          fontWeight: FontWeight.w600,
                          color: referencePrice == null
                              ? (row.isUp
                                  ? const Color(0xFFE53935)
                                  : const Color(0xFF22A06B))
                              : _priceColor(row.price, referencePrice),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 40,
                  child: Text(
                    row.volumeText,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      color: emphasizeVolumeColor
                          ? (row.isUp
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFE53935))
                          : const Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
}

class _SimpleLinePairPainter extends CustomPainter {
  _SimpleLinePairPainter({
    required this.a,
    required this.b,
    required this.aColor,
    required this.bColor,
  });

  final List<double> a;
  final List<double> b;
  final Color aColor;
  final Color bColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF5F5F5));
    if (a.isEmpty || b.isEmpty) return;
    var minV = a.first;
    var maxV = a.first;
    for (final v in [...a, ...b]) {
      minV = mathMin(minV, v);
      maxV = mathMax(maxV, v);
    }
    if ((maxV - minV).abs() < 1e-6) {
      maxV += 1;
      minV -= 1;
    }
    double yFor(double v) =>
        rect.bottom - (v - minV) / (maxV - minV) * rect.height;
    double xFor(int i, int len) => len <= 1 ? 0 : i * rect.width / (len - 1);
    Path pathOf(List<double> data) {
      final p = Path();
      for (var i = 0; i < data.length; i++) {
        final x = xFor(i, data.length);
        final y = yFor(data[i]);
        if (i == 0) {
          p.moveTo(x, y);
        } else {
          p.lineTo(x, y);
        }
      }
      return p;
    }

    canvas.drawPath(
      pathOf(a),
      Paint()
        ..color = aColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawPath(
      pathOf(b),
      Paint()
        ..color = bColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _SimpleLinePairPainter oldDelegate) {
    return oldDelegate.a != a || oldDelegate.b != b;
  }
}

class _VolumeMALinePainter extends CustomPainter {
  _VolumeMALinePainter({
    required this.candles,
    required this.ma5Color,
    required this.ma10Color,
  });

  final List<CandleData> candles;
  final Color ma5Color;
  final Color ma10Color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF5F5F5));
    if (candles.isEmpty) return;

    final vols = candles.map((e) => (e.volume ?? 0)).toList(growable: false);
    final maxVol = vols.reduce(mathMax);
    if (maxVol <= 0) return;
    final barW = mathMax(1.0, rect.width / vols.length);
    for (var i = 0; i < vols.length; i++) {
      final h = vols[i] / maxVol * rect.height;
      final left = i * barW;
      final top = rect.bottom - h;
      final up = candles[i].close >= candles[i].open;
      canvas.drawRect(
        Rect.fromLTWH(left, top, mathMax(1.0, barW - 0.8), h),
        Paint()..color = up ? const Color(0xFFE53935) : const Color(0xFF0E8E2F),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VolumeMALinePainter oldDelegate) {
    return oldDelegate.candles != candles;
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

class _TradePiePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = mathMin(size.width, size.height) * 0.48;
    const slices = <double>[0.20, 0.18, 0.12, 0.09, 0.24, 0.17];
    const colors = <Color>[
      Color(0xFF7C0000),
      Color(0xFFB00000),
      Color(0xFFD10000),
      Color(0xFFFF1212),
      Color(0xFF009A00),
      Color(0xFF00C000),
    ];
    var start = -pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i] * pi * 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        true,
        Paint()..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IntradayPricePainter extends CustomPainter {
  _IntradayPricePainter({
    required this.points,
    required this.avgLine,
    required this.gridColor,
    required this.lineColor,
    required this.avgColor,
    this.referencePrice,
    this.axisMode = _TimeAxisMode.intraday,
    this.focusIndex,
  });

  final List<LinePoint> points;
  final List<double> avgLine;
  final Color gridColor;
  final Color lineColor;
  final Color avgColor;
  final double? referencePrice;
  final _TimeAxisMode axisMode;
  final int? focusIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFF5F5F5));

    const padding = EdgeInsets.fromLTRB(7, 8, 7, 18);
    final rect = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.left - padding.right,
      size.height - padding.top - padding.bottom,
    );
    if (rect.width <= 0 || rect.height <= 0 || points.isEmpty) return;

    // Right-edge quote lane, similar to mobile trading apps.
    final laneRect = Rect.fromLTWH(rect.right - 2, rect.top, 2, rect.height);
    canvas.drawRect(laneRect, Paint()..color = const Color(0xFFE8EAEE));

    final grid = Paint()
      ..color = const Color(0xFFE1E5EB)
      ..strokeWidth = 0.8;
    for (var i = 0; i <= 4; i++) {
      final y = rect.top + rect.height * i / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
    for (var i = 0; i <= 4; i++) {
      final x = rect.left + rect.width * i / 4;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
    }

    var minValue = points.first.value;
    var maxValue = points.first.value;
    for (final p in points) {
      minValue = mathMin(minValue, p.value);
      maxValue = mathMax(maxValue, p.value);
    }
    for (final p in avgLine) {
      minValue = mathMin(minValue, p);
      maxValue = mathMax(maxValue, p);
    }
    final base = referencePrice ?? points.first.value;
    var upSpan = maxValue - base;
    var downSpan = base - minValue;
    if (upSpan < 0) upSpan = 0;
    if (downSpan < 0) downSpan = 0;
    var halfRange = mathMax(upSpan, downSpan);
    if (halfRange < 1e-6) {
      halfRange = mathMax(base.abs() * 0.01, 0.01);
    }
    halfRange *= 1.06;
    maxValue = base + halfRange;
    minValue = base - halfRange;

    double yFor(double value) {
      final t = (value - minValue) / (maxValue - minValue);
      return rect.bottom - t * rect.height;
    }

    final slots = _projectedSlots(points, axisMode);
    final totalSlots = _projectedTotalSlots(points, axisMode);
    double xFor(int i) => rect.left + slots[i] / totalSlots * rect.width;

    final midY = yFor(base);
    final dash = Paint()
      ..color = const Color(0xFFB8C0CC)
      ..strokeWidth = 0.8;
    for (var x = rect.left; x < rect.right; x += 4) {
      canvas.drawLine(
          Offset(x, midY), Offset(mathMin(x + 1.6, rect.right), midY), dash);
    }

    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      final x = xFor(i);
      final y = yFor(points[i].value);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 0.9
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke,
    );

    if (avgLine.length == points.length && avgLine.isNotEmpty) {
      final avgPath = Path();
      for (var i = 0; i < avgLine.length; i++) {
        final x = xFor(i);
        final y = yFor(avgLine[i]);
        if (i == 0) {
          avgPath.moveTo(x, y);
        } else {
          avgPath.lineTo(x, y);
        }
      }
      canvas.drawPath(
        avgPath,
        Paint()
          ..color = avgColor
          ..strokeWidth = 1.0
          ..style = PaintingStyle.stroke,
      );
    }

    if (focusIndex != null &&
        focusIndex! >= 0 &&
        focusIndex! < points.length &&
        points.length > 1) {
      final fx = xFor(focusIndex!);
      final fy = yFor(points[focusIndex!].value);
      final focusPoint = points[focusIndex!];
      final cross = Paint()
        ..color = const Color(0xFF7A7A7A)
        ..strokeWidth = 0.8;
      canvas.drawLine(Offset(fx, rect.top), Offset(fx, rect.bottom), cross);
      canvas.drawLine(Offset(rect.left, fy), Offset(rect.right, fy), cross);
      canvas.drawCircle(
        Offset(fx, fy),
        2.2,
        Paint()..color = const Color(0xFF111111),
      );

      final hh = focusPoint.time.hour.toString().padLeft(2, '0');
      final mm = focusPoint.time.minute.toString().padLeft(2, '0');
      _drawBubbleLabel(
        canvas,
        text: '$hh:$mm',
        centerX: fx,
        top: rect.bottom + 2,
      );
      _drawBubbleLabel(
        canvas,
        text: focusPoint.value.toStringAsFixed(2),
        right: rect.right - 2,
        centerY: fy,
      );
    }

    final topPct = (maxValue - base) / base * 100;
    final bottomPct = (minValue - base) / base * 100;
    _drawText(canvas, maxValue.toStringAsFixed(2), const Offset(4, 1),
        const Color(0xFFE53935));
    _drawTextRight(
      canvas,
      '${topPct.toStringAsFixed(2)}%',
      Offset(rect.right - 2, 1),
      const Color(0xFFE53935),
    );
    _drawText(
      canvas,
      base.toStringAsFixed(2),
      Offset(4, midY - 7.5),
      const Color(0xFF9AA5B1),
    );
    _drawTextRight(
      canvas,
      '0.00%',
      Offset(rect.right - 2, midY - 7.5),
      const Color(0xFF9AA5B1),
    );
    _drawText(
      canvas,
      minValue.toStringAsFixed(2),
      Offset(4, rect.bottom - 10),
      const Color(0xFF16A34A),
    );
    _drawTextRight(
      canvas,
      '${bottomPct.toStringAsFixed(2)}%',
      Offset(rect.right - 2, rect.bottom - 10),
      const Color(0xFF16A34A),
    );

    if (axisMode == _TimeAxisMode.intraday) {
      _drawText(canvas, '09:30', Offset(rect.left - 1, rect.bottom + 3),
          const Color(0xFF9AA5B1));
      _drawText(
        canvas,
        '11:30',
        Offset(rect.left + rect.width / 2 - 18, rect.bottom + 3),
        const Color(0xFF9AA5B1),
      );
      _drawText(canvas, '15:00', Offset(rect.right - 34, rect.bottom + 3),
          const Color(0xFF9AA5B1));
    } else {
      final days = _uniqueDayKeys(points);
      for (var i = 0; i < days.length; i++) {
        final x = rect.left +
            ((i + 0.5) * _intradayTotalSlots) / totalSlots * rect.width;
        _drawText(
          canvas,
          _formatMonthDay(days[i]),
          Offset((x - 18).clamp(rect.left, rect.right - 36), rect.bottom + 3),
          const Color(0xFF9AA5B1),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IntradayPricePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.avgLine != avgLine ||
        oldDelegate.referencePrice != referencePrice ||
        oldDelegate.axisMode != axisMode ||
        oldDelegate.focusIndex != focusIndex;
  }
}

class _IntradayVolumePainter extends CustomPainter {
  _IntradayVolumePainter({
    required this.points,
    required this.volumes,
    required this.gridColor,
    required this.upColor,
    required this.downColor,
    this.axisMode = _TimeAxisMode.intraday,
    this.focusIndex,
  });

  final List<LinePoint> points;
  final List<double> volumes;
  final Color gridColor;
  final Color upColor;
  final Color downColor;
  final _TimeAxisMode axisMode;
  final int? focusIndex;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFF3F3F3));
    final rect = Rect.fromLTWH(7, 1, size.width - 14, size.height - 6);
    if (rect.width <= 0 ||
        rect.height <= 0 ||
        points.isEmpty ||
        volumes.isEmpty) {
      return;
    }

    final laneRect = Rect.fromLTWH(rect.right - 2, rect.top, 2, rect.height);
    canvas.drawRect(laneRect, Paint()..color = const Color(0xFFE8EAEE));

    final grid = Paint()
      ..color = const Color(0xFFE1E5EB)
      ..strokeWidth = 0.8;
    canvas.drawLine(
        Offset(rect.left, rect.top), Offset(rect.right, rect.top), grid);
    canvas.drawLine(
      Offset(rect.left + rect.width / 2, rect.top),
      Offset(rect.left + rect.width / 2, rect.bottom),
      grid,
    );

    final maxV = volumes.reduce(mathMax);
    if (maxV <= 0) return;
    final slots = _projectedSlots(points, axisMode);
    final totalSlots = _projectedTotalSlots(points, axisMode);
    final barW = mathMax(1.0, rect.width / (_intradayTotalSlots + 1) * 0.92);
    for (var i = 0; i < volumes.length; i++) {
      final h = volumes[i] / maxV * rect.height;
      final x = rect.left + slots[i] / totalSlots * rect.width;
      final left = x - barW / 2;
      final top = rect.bottom - h;
      final color = i == 0 || points[i].value >= points[i - 1].value
          ? upColor
          : downColor;
      canvas.drawRect(
        Rect.fromLTWH(left, top, mathMax(1.0, barW - 0.4), h),
        Paint()..color = color.withValues(alpha: 0.9),
      );
    }

    _drawText(canvas, '成交量', Offset(rect.left, rect.top + 2),
        const Color(0xFF6B7785));
    _drawTextRight(
      canvas,
      _formatVolumeCompact(maxV),
      Offset(rect.right - 1, rect.top + 2),
      const Color(0xFF9AA5B1),
    );
    _drawTextRight(
      canvas,
      _formatVolumeCompact(maxV / 2),
      Offset(rect.right - 1, rect.top + rect.height / 2 - 5),
      const Color(0xFF9AA5B1),
    );

    if (focusIndex != null &&
        focusIndex! >= 0 &&
        focusIndex! < points.length &&
        points.length > 1) {
      final x = rect.left + slots[focusIndex!] / totalSlots * rect.width;
      final cross = Paint()
        ..color = const Color(0xFF8FA0B3)
        ..strokeWidth = 0.8;
      for (var y = rect.top; y < rect.bottom; y += 4) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x, mathMin(y + 2, rect.bottom)),
          cross,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IntradayVolumePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.volumes != volumes ||
        oldDelegate.axisMode != axisMode ||
        oldDelegate.focusIndex != focusIndex;
  }
}

class _KCompositeCrosshairOverlayPainter extends CustomPainter {
  _KCompositeCrosshairOverlayPainter({
    required this.candles,
    required this.focusIndex,
    required this.chartPadding,
  });

  final List<CandleData> candles;
  final int focusIndex;
  final EdgeInsets chartPadding;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || focusIndex < 0 || focusIndex >= candles.length) {
      return;
    }

    const topFlex = 58;
    const dividerTotal = 2.0;
    const allFlex = 100.0;
    final usableHeight = mathMax(1.0, size.height - dividerTotal);
    final topPaneHeight = usableHeight * topFlex / allFlex;

    final rect = Rect.fromLTWH(
      chartPadding.left,
      chartPadding.top,
      size.width - chartPadding.left - chartPadding.right,
      topPaneHeight - chartPadding.top - chartPadding.bottom,
    );
    if (rect.width <= 0 || rect.height <= 0) return;

    var minPrice = candles.first.low;
    var maxPrice = candles.first.high;
    for (final c in candles) {
      minPrice = mathMin(minPrice, c.low);
      maxPrice = mathMax(maxPrice, c.high);
    }
    if ((maxPrice - minPrice).abs() < 1e-6) {
      final eps = mathMax(maxPrice.abs() * 0.01, 0.01);
      maxPrice += eps;
      minPrice -= eps;
    }

    final pad = (maxPrice - minPrice) * 0.08;
    maxPrice += pad;
    minPrice -= pad;

    double xFor(int i) {
      if (candles.length == 1) return rect.left;
      return rect.left + i * rect.width / (candles.length - 1);
    }

    double yFor(double price) {
      final t = (price - minPrice) / (maxPrice - minPrice);
      return rect.bottom - t * rect.height;
    }

    final candle = candles[focusIndex];
    final x = xFor(focusIndex);
    final y = yFor(candle.close);

    final cross = Paint()
      ..color = const Color(0xFF7A7A7A)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), cross);
    canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), cross);

    _drawBubbleLabel(
      canvas,
      text: _formatDateLabel(candle.time),
      centerX: x,
      top: rect.bottom + 2,
    );
    _drawBubbleLabel(
      canvas,
      text: candle.close.toStringAsFixed(2),
      right: rect.right - 2,
      centerY: y,
    );
  }

  @override
  bool shouldRepaint(covariant _KCompositeCrosshairOverlayPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.focusIndex != focusIndex ||
        oldDelegate.chartPadding != chartPadding;
  }
}

void _drawText(Canvas canvas, String text, Offset offset, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style:
          TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w500),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, offset);
}

void _drawTextRight(Canvas canvas, String text, Offset rightTop, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style:
          TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w500),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(rightTop.dx - tp.width, rightTop.dy));
}

void _drawBubbleLabel(
  Canvas canvas, {
  required String text,
  double? centerX,
  double? top,
  double? right,
  double? centerY,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  const hPad = 7.0;
  const vPad = 3.0;
  final w = tp.width + hPad * 2;
  final h = tp.height + vPad * 2;

  final left = right != null ? right - w : ((centerX ?? 0) - w / 2);
  final topPos = centerY != null ? (centerY - h / 2) : (top ?? 0);

  final rect = Rect.fromLTWH(left, topPos, w, h);
  final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
  canvas.drawRRect(rrect, Paint()..color = const Color(0xFF4E8FE7));
  tp.paint(canvas, Offset(rect.left + hPad, rect.top + vPad));
}

String _formatVolumeCompact(double value) {
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(2)}万';
  }
  return value.toStringAsFixed(0);
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
  return mathMax(1.0, dayCount * _intradayTotalSlots.toDouble());
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

Future<Map<String, dynamic>> _getJson(Uri uri) async {
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }
  final body = response.body.trim();
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    // JSONP fallback, e.g. min_data_xxx={...};
    final eq = body.indexOf('=');
    final start = eq >= 0 ? eq + 1 : 0;
    final end = body.endsWith(';') ? body.length - 1 : body.length;
    final payload = body.substring(start, end).trim();
    decoded = jsonDecode(payload);
  }
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Invalid response');
  }
  return decoded;
}

Future<List<LinePoint>> _fetchMinuteLine(String symbol) async {
  final varName = 'min_data_$symbol';
  final uri = Uri.parse(
    'https://web.ifzq.gtimg.cn/appstock/app/minute/query'
    '?_var=$varName&code=$symbol&r=${Random().nextDouble()}',
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

String _toYmd(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

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

Future<List<LinePoint>> _fetchFiveDayLine(String symbol) async {
  final uri = Uri.parse(
    'https://web.ifzq.gtimg.cn/appstock/app/day/query?code=$symbol',
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
    final lines = day['data'];
    if (lines is! List) continue;

    for (final item in lines) {
      if (item is! String) continue;
      final parts = item.split(' ');
      if (parts.length < 2) continue;

      final hhmm = parts[0];
      final price = _toDouble(parts[1]);
      if (hhmm.length != 4 || price == null) continue;

      final time = _parseTencentDateTime(dateRaw, hhmm);
      if (time == null) continue;
      result.add(LinePoint(time: time, value: price));
    }
  }

  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

Future<List<CandleData>> _fetchKline(
  String symbol, {
  required String period,
  required int count,
}) async {
  final uri = Uri.parse(
    'https://web.ifzq.gtimg.cn/appstock/app/fqkline/get'
    '?param=$symbol,$period,,,$count,qfq',
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

DateTime? _parseTencentDateTime(String yyyymmdd, String hhmm) {
  if (yyyymmdd.length != 8 || hhmm.length != 4) return null;
  final y = int.tryParse(yyyymmdd.substring(0, 4));
  final m = int.tryParse(yyyymmdd.substring(4, 6));
  final d = int.tryParse(yyyymmdd.substring(6, 8));
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

List<LinePoint> _mockIntradayLine({
  required int days,
  required int pointsPerDay,
}) {
  final random = Random(11 + days + pointsPerDay);
  final points = <LinePoint>[];
  var last = 100.0;
  final start = DateTime(2026, 2, 2, 9, 30);

  for (var d = 0; d < days; d++) {
    var t = start.add(Duration(days: d));
    for (var i = 0; i < pointsPerDay; i++) {
      final step = (random.nextDouble() - 0.5) * 0.9;
      last = (last + step).clamp(20.0, 300.0).toDouble();
      points.add(LinePoint(time: t, value: last));
      t = t.add(const Duration(minutes: 1));
    }
  }

  return points;
}

List<CandleData> _mockDayCandles(int count) {
  final random = Random(7);
  final list = <CandleData>[];

  var lastClose = 100.0;
  final start = DateTime(2025, 1, 1);

  for (var i = 0; i < count; i++) {
    final open = lastClose;
    final delta = (random.nextDouble() - 0.5) * 4;
    final close = (open + delta).clamp(20.0, 300.0).toDouble();
    final high = mathMax(open, close) + random.nextDouble() * 2;
    final low = mathMin(open, close) - random.nextDouble() * 2;
    final volume = 1000 + random.nextInt(9000);

    list.add(
      CandleData(
        time: start.add(Duration(days: i)),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume.toDouble(),
      ),
    );

    lastClose = close;
  }

  return list;
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
