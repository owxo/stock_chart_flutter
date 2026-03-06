import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/candle_data.dart';
import 'stock_chart_theme.dart';

class StockCandlestickChart extends StatefulWidget {
  const StockCandlestickChart({
    super.key,
    required this.data,
    this.height = 320,
    this.theme = const StockChartTheme(),
    this.padding = const EdgeInsets.fromLTRB(12, 16, 52, 24),
    this.minCandleWidth = 4,
    this.maxCandleWidth = 28,
    this.initialCandleWidth = 10,
    this.candleGap = 2,
    this.maPeriods = const [5, 10, 20],
    this.onSelected,
  });

  final List<CandleData> data;
  final double height;
  final StockChartTheme theme;
  final EdgeInsets padding;
  final double minCandleWidth;
  final double maxCandleWidth;
  final double initialCandleWidth;
  final double candleGap;
  final List<int> maPeriods;
  final ValueChanged<CandleData?>? onSelected;

  @override
  State<StockCandlestickChart> createState() => _StockCandlestickChartState();
}

class _StockCandlestickChartState extends State<StockCandlestickChart> {
  late double _candleWidth;
  double _scrollX = 0;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _candleWidth = widget.initialCandleWidth;
  }

  @override
  void didUpdateWidget(covariant StockCandlestickChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.length != oldWidget.data.length) {
      _selectedIndex = null;
    }
  }

  double _step() => _candleWidth + widget.candleGap;

  double _contentWidth() => widget.data.length * _step();

  double _maxScroll(double viewportWidth) {
    final maxScroll = _contentWidth() - viewportWidth;
    return math.max(0, maxScroll);
  }

  void _clampScroll(double viewportWidth) {
    _scrollX = _scrollX.clamp(0, _maxScroll(viewportWidth));
  }

  void _zoomAt({
    required double viewportWidth,
    required double focalX,
    required double scale,
  }) {
    final oldWidth = _candleWidth;
    final newWidth = (_candleWidth * scale).clamp(
      widget.minCandleWidth,
      widget.maxCandleWidth,
    );
    if (newWidth == oldWidth) return;

    final contentX = _scrollX + focalX;
    final indexFloat = contentX / (oldWidth + widget.candleGap);
    _candleWidth = newWidth;
    _scrollX = indexFloat * _step() - focalX;
    _clampScroll(viewportWidth);
    setState(() {});
  }

  void _panBy(double dx, double viewportWidth) {
    if (widget.data.isEmpty) return;
    _scrollX -= dx;
    _clampScroll(viewportWidth);
    setState(() {});
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double viewportWidth) {
    if (widget.data.isEmpty) return;

    final focalX = details.localFocalPoint.dx;
    if (details.scale != 1.0) {
      _zoomAt(
        viewportWidth: viewportWidth,
        focalX: focalX,
        scale: details.scale,
      );
    } else {
      _panBy(details.focalPointDelta.dx, viewportWidth);
    }
  }

  void _updateSelected(Offset localPosition, double viewportWidth) {
    if (widget.data.isEmpty) return;
    _clampScroll(viewportWidth);

    final index = ((_scrollX + localPosition.dx) / _step()).floor();
    final safeIndex = index.clamp(0, widget.data.length - 1);
    if (safeIndex != _selectedIndex) {
      setState(() => _selectedIndex = safeIndex);
      widget.onSelected?.call(widget.data[safeIndex]);
    }
  }

  void _clearSelected() {
    if (_selectedIndex != null) {
      setState(() => _selectedIndex = null);
      widget.onSelected?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        _clampScroll(viewportWidth);

        return Listener(
          onPointerMove: (event) {
            if (event.kind == PointerDeviceKind.mouse &&
                event.buttons == kPrimaryMouseButton) {
              _panBy(event.delta.dx, viewportWidth);
            }
          },
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent || widget.data.isEmpty) return;
            final ctrlPressed = HardwareKeyboard.instance.logicalKeysPressed
                    .contains(LogicalKeyboardKey.controlLeft) ||
                HardwareKeyboard.instance.logicalKeysPressed
                    .contains(LogicalKeyboardKey.controlRight) ||
                HardwareKeyboard.instance.logicalKeysPressed
                    .contains(LogicalKeyboardKey.metaLeft) ||
                HardwareKeyboard.instance.logicalKeysPressed
                    .contains(LogicalKeyboardKey.metaRight);

            if (ctrlPressed) {
              final zoomScale = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
              _zoomAt(
                viewportWidth: viewportWidth,
                focalX: event.localPosition.dx,
                scale: zoomScale,
              );
            } else {
              _panBy(
                  event.scrollDelta.dx + event.scrollDelta.dy, viewportWidth);
            }
          },
          child: MouseRegion(
            onHover: (event) =>
                _updateSelected(event.localPosition, viewportWidth),
            onExit: (_) => _clearSelected(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _updateSelected(d.localPosition, viewportWidth),
              onScaleUpdate: (d) => _onScaleUpdate(d, viewportWidth),
              onLongPressStart: (d) =>
                  _updateSelected(d.localPosition, viewportWidth),
              onLongPressMoveUpdate: (d) =>
                  _updateSelected(d.localPosition, viewportWidth),
              onLongPressEnd: (_) => _clearSelected(),
              child: SizedBox(
                height: widget.height,
                width: double.infinity,
                child: CustomPaint(
                  painter: _CandlestickPainter(
                    data: widget.data,
                    chartTheme: widget.theme,
                    padding: widget.padding,
                    candleWidth: _candleWidth,
                    candleGap: widget.candleGap,
                    scrollX: _scrollX,
                    selectedIndex: _selectedIndex,
                    maPeriods: widget.maPeriods,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  _CandlestickPainter({
    required this.data,
    required this.chartTheme,
    required this.padding,
    required this.candleWidth,
    required this.candleGap,
    required this.scrollX,
    required this.selectedIndex,
    required this.maPeriods,
  });

  final List<CandleData> data;
  final StockChartTheme chartTheme;
  final EdgeInsets padding;
  final double candleWidth;
  final double candleGap;
  final double scrollX;
  final int? selectedIndex;
  final List<int> maPeriods;

  double get _step => candleWidth + candleGap;

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = chartTheme.backgroundColor;
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final chartRect = Rect.fromLTWH(
      padding.left,
      padding.top,
      size.width - padding.left - padding.right,
      size.height - padding.top - padding.bottom,
    );

    if (chartRect.width <= 0 || chartRect.height <= 0 || data.isEmpty) {
      return;
    }

    _drawGrid(canvas, chartRect);

    final startIndex = math.max(0, (scrollX / _step).floor() - 1);
    final endIndex = math.min(
      data.length - 1,
      ((scrollX + chartRect.width) / _step).ceil() + 1,
    );

    double minPrice = double.infinity;
    double maxPrice = -double.infinity;
    for (var i = startIndex; i <= endIndex; i++) {
      minPrice = math.min(minPrice, data[i].low);
      maxPrice = math.max(maxPrice, data[i].high);
    }

    if (minPrice == double.infinity || maxPrice == -double.infinity) return;

    if ((maxPrice - minPrice).abs() < 1e-6) {
      maxPrice += 1;
      minPrice -= 1;
    }

    final pad = (maxPrice - minPrice) * 0.05;
    maxPrice += pad;
    minPrice -= pad;

    double yForPrice(double p) {
      final t = (p - minPrice) / (maxPrice - minPrice);
      return chartRect.bottom - t * chartRect.height;
    }

    final wickPaint = Paint()..strokeWidth = 1;

    for (var i = startIndex; i <= endIndex; i++) {
      final candle = data[i];
      final centerX = chartRect.left + i * _step - scrollX + candleWidth / 2;

      if (centerX < chartRect.left - candleWidth ||
          centerX > chartRect.right + candleWidth) {
        continue;
      }

      final openY = yForPrice(candle.open);
      final closeY = yForPrice(candle.close);
      final highY = yForPrice(candle.high);
      final lowY = yForPrice(candle.low);

      final bullish = candle.isBullish;
      final color = bullish ? chartTheme.bullColor : chartTheme.bearColor;

      wickPaint.color = color;
      canvas.drawLine(Offset(centerX, highY), Offset(centerX, lowY), wickPaint);

      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final bodyRect = Rect.fromLTRB(
        centerX - candleWidth / 2,
        bodyTop,
        centerX + candleWidth / 2,
        math.max(bodyBottom, bodyTop + 1),
      );

      final bodyPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRect(bodyRect, bodyPaint);
    }

    _drawMAs(canvas, chartRect, yForPrice, startIndex, endIndex);
    _drawAxisLabels(canvas, chartRect, minPrice, maxPrice);
    _drawCrosshair(canvas, chartRect, yForPrice);
  }

  void _drawGrid(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = chartTheme.gridColor
      ..strokeWidth = 1;

    const horizontal = 4;
    const vertical = 4;

    for (var i = 0; i <= horizontal; i++) {
      final y = rect.top + rect.height * i / horizontal;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }

    for (var i = 0; i <= vertical; i++) {
      final x = rect.left + rect.width * i / vertical;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
  }

  void _drawMAs(
    Canvas canvas,
    Rect chartRect,
    double Function(double) yForPrice,
    int startIndex,
    int endIndex,
  ) {
    for (var maIdx = 0; maIdx < maPeriods.length; maIdx++) {
      final period = maPeriods[maIdx];
      if (period <= 1) continue;

      final path = Path();
      var hasStarted = false;

      for (var i = math.max(period - 1, startIndex); i <= endIndex; i++) {
        double sum = 0;
        for (var j = i - period + 1; j <= i; j++) {
          sum += data[j].close;
        }
        final ma = sum / period;

        final x = chartRect.left + i * _step - scrollX + candleWidth / 2;
        final y = yForPrice(ma);

        if (!hasStarted) {
          path.moveTo(x, y);
          hasStarted = true;
        } else {
          path.lineTo(x, y);
        }
      }

      if (!hasStarted) continue;
      final paint = Paint()
        ..color = chartTheme.maColors[maIdx % chartTheme.maColors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(path, paint);
    }
  }

  void _drawAxisLabels(
    Canvas canvas,
    Rect chartRect,
    double minPrice,
    double maxPrice,
  ) {
    final textStyle = TextStyle(color: chartTheme.textColor, fontSize: 10);

    void drawText(String text, Offset offset) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, offset);
    }

    drawText(maxPrice.toStringAsFixed(2),
        Offset(chartRect.right + 4, chartRect.top - 6));
    drawText(minPrice.toStringAsFixed(2),
        Offset(chartRect.right + 4, chartRect.bottom - 10));

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < data.length) {
      final c = data[selectedIndex!];
      final text =
          'O:${c.open.toStringAsFixed(2)} H:${c.high.toStringAsFixed(2)} L:${c.low.toStringAsFixed(2)} C:${c.close.toStringAsFixed(2)}';
      drawText(text, Offset(chartRect.left, 2));
    }
  }

  void _drawCrosshair(
    Canvas canvas,
    Rect chartRect,
    double Function(double) yForPrice,
  ) {
    if (selectedIndex == null ||
        selectedIndex! < 0 ||
        selectedIndex! >= data.length) {
      return;
    }

    final candle = data[selectedIndex!];
    final x =
        chartRect.left + selectedIndex! * _step - scrollX + candleWidth / 2;
    final y = yForPrice(candle.close);

    if (!chartRect.contains(Offset(x, y))) return;

    final paint = Paint()
      ..color = chartTheme.crosshairColor
      ..strokeWidth = 1;

    canvas.drawLine(
        Offset(x, chartRect.top), Offset(x, chartRect.bottom), paint);
    canvas.drawLine(
        Offset(chartRect.left, y), Offset(chartRect.right, y), paint);
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.candleWidth != candleWidth ||
        oldDelegate.candleGap != candleGap ||
        oldDelegate.scrollX != scrollX ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.chartTheme != chartTheme ||
        oldDelegate.padding != padding ||
        oldDelegate.maPeriods != maPeriods;
  }
}
