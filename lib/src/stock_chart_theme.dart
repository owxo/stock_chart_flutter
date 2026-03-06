import 'package:flutter/material.dart';

class StockChartTheme {
  const StockChartTheme({
    this.backgroundColor = const Color(0xFF111418),
    this.gridColor = const Color(0x223A4552),
    this.textColor = const Color(0xFFB0BCCB),
    this.bullColor = const Color(0xFF24C78E),
    this.bearColor = const Color(0xFFE25252),
    this.crosshairColor = const Color(0x66E8EEF8),
    this.lineColor = const Color(0xFF4DA3FF),
    this.maColors = const [
      Color(0xFFF2C94C),
      Color(0xFF56CCF2),
      Color(0xFFBB6BD9),
    ],
  });

  final Color backgroundColor;
  final Color gridColor;
  final Color textColor;
  final Color bullColor;
  final Color bearColor;
  final Color crosshairColor;
  final Color lineColor;
  final List<Color> maColors;
}
