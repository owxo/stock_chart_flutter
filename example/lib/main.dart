import 'package:flutter/material.dart';
import 'package:stock_chart_flutter/stock_chart_flutter.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key, this.initialSymbol});

  final String? initialSymbol;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final TextEditingController _symbolController = TextEditingController();
  String _symbol = '';

  @override
  void initState() {
    super.initState();
    final initialSymbol = _normalizeTencentSymbol(
      widget.initialSymbol ?? Uri.base.queryParameters['symbol'] ?? '',
    );
    if (initialSymbol.isNotEmpty) {
      _symbol = initialSymbol;
      _symbolController.text = initialSymbol;
    }
  }

  @override
  void dispose() {
    _symbolController.dispose();
    super.dispose();
  }

  void _loadSymbol() {
    setState(() {
      _symbol = _normalizeTencentSymbol(_symbolController.text);
      _symbolController.text = _symbol;
      _symbolController.selection = TextSelection.collapsed(
        offset: _symbolController.text.length,
      );
    });
  }

  void _clearSymbol() {
    setState(() {
      _symbol = '';
      _symbolController.clear();
    });
  }

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
      home: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _SymbolInputBar(
                controller: _symbolController,
                onLoad: _loadSymbol,
                onClear: _clearSymbol,
                hasSymbol: _symbol.isNotEmpty,
              ),
              Expanded(
                child: TencentStockChartPage(
                  symbol: _symbol,
                  autoRefreshSeconds: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SymbolInputBar extends StatelessWidget {
  const _SymbolInputBar({
    required this.controller,
    required this.onLoad,
    required this.onClear,
    required this.hasSymbol,
  });

  final TextEditingController controller;
  final VoidCallback onLoad;
  final VoidCallback onClear;
  final bool hasSymbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => onLoad(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'sz001896 / sh600519 / 600519',
                prefixIcon: Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: '加载行情',
            onPressed: onLoad,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          if (hasSymbol) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: '清空代码',
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

String _normalizeTencentSymbol(String input) {
  final cleaned = input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  if (RegExp(r'^\d{6}$').hasMatch(cleaned)) {
    return cleaned.startsWith('6') ? 'sh$cleaned' : 'sz$cleaned';
  }
  if (RegExp(r'^(sh|sz)\d{6}$').hasMatch(cleaned)) {
    return cleaned;
  }
  return cleaned;
}
