# stock_chart_flutter

A Flutter stock chart package for financial apps.

## Features

- Candlestick (OHLC) chart
- Line chart (time series / intraday)
- Multi-platform support: Android, iOS, Web, macOS, Windows, Linux
- Pinch/trackpad zoom and mouse wheel zoom (`Ctrl/Cmd + wheel`)
- Horizontal pan (touch drag / mouse drag / wheel)
- Crosshair with selection callback (long press, click, hover)
- Simple moving averages (MA)

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  stock_chart_flutter: ^0.1.0
```

## Usage

```dart
import 'package:stock_chart_flutter/stock_chart_flutter.dart';

final candles = <CandleData>[
  CandleData(
    time: DateTime(2026, 1, 1),
    open: 10,
    high: 12,
    low: 9,
    close: 11,
    volume: 12000,
  ),
];

StockCandlestickChart(
  data: candles,
  maPeriods: const [5, 10, 20],
  onSelected: (item) {
    // handle selected candle
  },
)
```

Tencent quote-style screen:

```dart
TencentStockChartPage(
  symbol: 'sz001896',
  autoRefreshSeconds: 3,
)
```

Line chart:

```dart
final points = <LinePoint>[
  LinePoint(time: DateTime(2026, 1, 1, 9, 30), value: 10.2),
  LinePoint(time: DateTime(2026, 1, 1, 9, 31), value: 10.4),
];

StockLineChart(
  data: points,
  onSelected: (item) {
    // handle selected point
  },
)
```

## Notes For pub.dev

Before publishing:

1. Update `homepage`, `repository`, `issue_tracker` in `pubspec.yaml`.
2. Update `LICENSE` to match your project.
3. Run:

```bash
flutter pub get
flutter analyze
flutter test
flutter pub publish --dry-run
```

## License

MIT
