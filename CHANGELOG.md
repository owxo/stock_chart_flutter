## 0.1.2

- Synchronized package metadata and README installation version.
- Updated package repository metadata to `owxo/stock_chart_flutter`.
- Declared supported platforms in `pubspec.yaml`: Android, iOS, Web, macOS, Windows and Linux.
- Added value equality, hash codes and readable `toString` output for chart data models.
- Added root package model tests and corrected the documented example test flow.
- Extracted Tencent quote fetching/parsing into a dedicated data source with request timeout support.
- Split Tencent quote screen painters and right-panel UI into focused part files.
- Removed the default Tencent quote symbol; the quote-style screen now stays empty until a `symbol` is provided.
- Added an example-app symbol input so demo users can load quotes explicitly.
- Added example-app support for initial quote loading from `?symbol=...` URLs.
- Optimized candlestick MA drawing with close-price prefix sums.
- Added chart edge-case widget tests for empty, single-point, flat-price and empty-MA-color scenarios.
- Fixed five-day chart handling for dashed Tencent dates, trading-session axis mapping, five-day grid segmentation and multi-day volume bar width.
- Added project documentation and development-log standards.
- Stopped tracking local `.dart_tool` generated files.
- Added desktop/web-friendly interactions:
  - mouse hover crosshair selection
  - click to select
  - mouse drag to pan
  - `Ctrl/Cmd + mouse wheel` zoom
- Added Flutter example platform runners for Android, iOS, Web, macOS, Windows, Linux.

## 0.1.0

- Initial release.
- Added candlestick chart with pinch zoom, pan, MA overlays and crosshair.
- Added line chart with pinch zoom, pan and crosshair.
