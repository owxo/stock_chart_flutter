import 'package:flutter/material.dart';
import 'package:stock_chart_flutter/stock_chart_flutter.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F6FFF),
          brightness: Brightness.light,
        ),
      ),
      home: const Scaffold(
        body: SafeArea(
          child: TencentStockChartPage(
            symbol: 'sz001896',
            autoRefreshSeconds: 3,
          ),
        ),
      ),
    );
  }
}
