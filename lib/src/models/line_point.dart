class LinePoint {
  const LinePoint({
    required this.time,
    required this.value,
  });

  final DateTime time;
  final double value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LinePoint && other.time == time && other.value == value;
  }

  @override
  int get hashCode => Object.hash(time, value);

  @override
  String toString() => 'LinePoint(time: $time, value: $value)';
}
