import '../../models/source_payload.dart';

List<double>? readStationJsonNumbers(
  List<dynamic> raw, {
  required double minimum,
  double maximum = double.infinity,
  bool allowStrings = true,
}) {
  if (raw is PackedJsonNumberList) {
    return raw.doublesInRange(minimum, maximum);
  }
  final values = <double>[];
  for (final item in raw) {
    final value = item is num
        ? item.toDouble()
        : allowStrings && item is String
        ? double.tryParse(item)
        : null;
    if (value == null ||
        !value.isFinite ||
        value < minimum ||
        value > maximum) {
      return null;
    }
    values.add(value);
  }
  return List.unmodifiable(values);
}
