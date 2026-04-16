extension IntListExtensions on List<int> {
  String toHexString() => map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

extension DateTimeExtensions on DateTime {
  int toEpoch() => (toUtc().millisecondsSinceEpoch / 1000).floor();
}
