import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/line_point.dart';
import 'stock_chart_theme.dart';

class StockLineChart extends StatefulWidget {
  const StockLineChart({
    super.key,
    required this.data,
    this.height = 260,
    this.theme = const StockChartTheme(),
    this.padding = const EdgeInsets.fromLTRB(12, 16, 52, 24),
    this.minPointWidth = 2,
    this.maxPointWidth = 20,
    this.initialPointWidth = 6,
    this.onSelected,
  });

  final List<LinePoint> data;
  final double height;
  final StockChartTheme theme;
  final EdgeInsets padding;
  final double minPointWidth;
  final double maxPointWidth;
  final double initialPointWidth;
  final ValueChanged<LinePoint?>? onSelected;

  @override
  State<StockLineChart> createState() => _StockLineChartState();
}

class _StockLineChartState extends State<StockLineChart> {
  late double _pointWidth;
  double _scrollX = 0;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _pointWidth = widget.initialPointWidth;
  }

  double _contentWidth() => math.max(1, widget.data.length - 1) * _pointWidth;

  double _maxScroll(double viewportWidth) {
    return math.max(0, _contentWidth() - viewportWidth);
  }

  void _clampScroll(double viewportWidth) {
    _scrollX = _scrollX.clamp(0, _maxScroll(viewportWidth));
  }

  void _zoomAt({
    required double viewportWidth,
    required double focalX,
    required double scale,
  }) {
    final oldWidth = _pointWidth;
    final newWidth = (_pointWidth * scale).clamp(
      widget.minPointWidth,
      widget.maxPointWidth,
    );
    if (newWidth == oldWidth) return;

    final contentX = _scrollX + focalX;
    final ratio = contentX / oldWidth;
    _pointWidth = newWidth;
    _scrollX = ratio * _pointWidth - focalX;
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

  void _updateSelected(Offset local, double viewportWidth) {
    if (widget.data.isEmpty) return;
    _clampScroll(viewportWidth);
    final index = ((_scrollX + local.dx) / _pointWidth).round();
    final safeIndex = index.clamp(0, widget.data.length - 1);
    if (_selectedIndex != safeIndex) {
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
                width: double.infinity,
                height: widget.height,
                child: CustomPaint(
                  painter: _LinePainter(
                    data: widget.data,
                    chartTheme: widget.theme,
                    padding: widget.padding,
                    pointWidth: _pointWidth,
                    scrollX: _scrollX,
                    selectedIndex: _selectedIndex,
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

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.data,
    required this.chartTheme,
    required this.padding,
    required this.pointWidth,
    required this.scrollX,
    required this.selectedIndex,
  });

  final List<LinePoint> data;
  final StockChartTheme chartTheme;
  final EdgeInsets padding;
  final double pointWidth;
  final double scrollX;
  final int? selectedIndex;

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

    final gridPaint = Paint()
      ..color = chartTheme.gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = chartRect.top + chartRect.height * i / 4;
      canvas.drawLine(
          Offset(chartRect.left, y), Offset(chartRect.right, y), gridPaint);
    }

    final startIndex = math.max(0, (scrollX / pointWidth).floor() - 1);
    final endIndex = math.min(
      data.length - 1,
      ((scrollX + chartRect.width) / pointWidth).ceil() + 1,
    );

    var minValue = double.infinity;
    var maxValue = -double.infinity;
    for (var i = startIndex; i <= endIndex; i++) {
      minValue = math.min(minValue, data[i].value);
      maxValue = math.max(maxValue, data[i].value);
    }

    if ((maxValue - minValue).abs() < 1e-6) {
      maxValue += 1;
      minValue -= 1;
    }

    final pad = (maxValue - minValue) * 0.05;
    maxValue += pad;
    minValue -= pad;

    double yForValue(double value) {
      final t = (value - minValue) / (maxValue - minValue);
      return chartRect.bottom - t * chartRect.height;
    }

    final path = Path();
    var started = false;
    for (var i = startIndex; i <= endIndex; i++) {
      final x = chartRect.left + i * pointWidth - scrollX;
      final y = yForValue(data[i].value);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = chartTheme.lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, linePaint);

    final textStyle = TextStyle(color: chartTheme.textColor, fontSize: 10);
    final maxTp = TextPainter(
      text: TextSpan(text: maxValue.toStringAsFixed(2), style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    maxTp.paint(canvas, Offset(chartRect.right + 4, chartRect.top - 6));

    final minTp = TextPainter(
      text: TextSpan(text: minValue.toStringAsFixed(2), style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    minTp.paint(canvas, Offset(chartRect.right + 4, chartRect.bottom - 10));

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < data.length) {
      final x = chartRect.left + selectedIndex! * pointWidth - scrollX;
      final y = yForValue(data[selectedIndex!].value);
      if (chartRect.contains(Offset(x, y))) {
        final crossPaint = Paint()
          ..color = chartTheme.crosshairColor
          ..strokeWidth = 1;
        canvas.drawLine(
            Offset(x, chartRect.top), Offset(x, chartRect.bottom), crossPaint);
        canvas.drawLine(
            Offset(chartRect.left, y), Offset(chartRect.right, y), crossPaint);

        final valueTp = TextPainter(
          text: TextSpan(
            text: data[selectedIndex!].value.toStringAsFixed(2),
            style: textStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        valueTp.paint(canvas, Offset(chartRect.left, 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.chartTheme != chartTheme ||
        oldDelegate.padding != padding ||
        oldDelegate.pointWidth != pointWidth ||
        oldDelegate.scrollX != scrollX ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
