/// Fixed-size circular (ring) buffer — no dart:collection dependency.
class CircularBuffer<T extends num> {
  final int capacity;
  final List<T?> _buf;
  int _head = 0;
  int _count = 0;

  CircularBuffer(this.capacity) : _buf = List<T?>.filled(capacity, null);

  void add(T value) {
    _buf[_head] = value;
    _head = (_head + 1) % capacity;
    if (_count < capacity) _count++;
  }

  int get length => _count;
  bool get isFull => _count == capacity;
  bool get isEmpty => _count == 0;

  T operator [](int index) {
    assert(index >= 0 && index < _count);
    final i = (_head - _count + index + capacity) % capacity;
    return _buf[i] as T;
  }

  List<T> toList() {
    final result = <T>[];
    for (int i = 0; i < _count; i++) {
      result.add(this[i]);
    }
    return result;
  }

  double mean() {
    if (_count == 0) return 0.0;
    double sum = 0;
    for (int i = 0; i < _count; i++) {
      sum += (this[i] as num).toDouble();
    }
    return sum / _count;
  }

  double std() {
    if (_count < 2) return 0.0;
    final m = mean();
    double variance = 0;
    for (int i = 0; i < _count; i++) {
      final diff = (this[i] as num).toDouble() - m;
      variance += diff * diff;
    }
    return _sqrt(variance / (_count - 1));
  }

  void clear() {
    _head = 0;
    _count = 0;
    for (int i = 0; i < capacity; i++) {
      _buf[i] = null;
    }
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}
