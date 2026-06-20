part of 'tencent_stock_chart_page.dart';

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
    final verticalSegments = _timeAxisSegmentCount(points, axisMode);
    for (var i = 0; i <= verticalSegments; i++) {
      final x = rect.left + rect.width * i / verticalSegments;
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

    final pctBase = base.abs() < 1e-8 ? 1.0 : base;
    final topPct = (maxValue - base) / pctBase * 100;
    final bottomPct = (minValue - base) / pctBase * 100;
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
    final verticalSegments = _timeAxisSegmentCount(points, axisMode);
    for (var i = 0; i <= verticalSegments; i++) {
      final x = rect.left + rect.width * i / verticalSegments;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid);
    }

    final maxV = volumes.reduce(mathMax);
    if (maxV <= 0) return;
    final slots = _projectedSlots(points, axisMode);
    final totalSlots = _projectedTotalSlots(points, axisMode);
    final barW = mathMax(1.0, rect.width / (totalSlots + 1) * 0.92);
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
