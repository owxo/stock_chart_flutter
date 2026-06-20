part of 'tencent_stock_chart_page.dart';

extension _TencentStockChartRightPanel on _TencentStockChartPageState {
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
                      onTap: () => _setIntradayRightTab(0),
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
                      onTap: () => _setIntradayRightTab(1),
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
}
