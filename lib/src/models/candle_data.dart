class CandleData {
  const CandleData({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;

  bool get isBullish => close >= open;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CandleData &&
            other.time == time &&
            other.open == open &&
            other.high == high &&
            other.low == low &&
            other.close == close &&
            other.volume == volume;
  }

  @override
  int get hashCode => Object.hash(time, open, high, low, close, volume);

  @override
  String toString() {
    return 'CandleData(time: $time, open: $open, high: $high, low: $low, close: $close, volume: $volume)';
  }
}
