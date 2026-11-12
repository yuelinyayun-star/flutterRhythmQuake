import 'dart:typed_data';

/// Original parsed JSON and independently owned derived numeric rows.
class PAlertWireResponse {
  const PAlertWireResponse(this.raw, PAlertWireValues? values)
    : _values = values;
  final dynamic raw;
  final PAlertWireValues? _values;
  bool get hasValues => _values != null;
  PAlertWireValues get values =>
      _values ??
      (throw StateError('Field extraction was skipped for this response'));
}

class PAlertWireValues {
  PAlertWireValues(Float64List rows, this.validPgaCount)
    : rows = rows.asUnmodifiableView();
  // Per directory station: [PGA present, PGA, PGV present, PGV].
  // Presence is separate because a supplied NaN is not a missing observation.
  final Float64List rows;
  final int validPgaCount;
  double? pga(int index) => rows[index * 4] == 0 ? null : rows[index * 4 + 1];
  double? pgv(int index) =>
      rows[index * 4 + 2] == 0 ? null : rows[index * 4 + 3];

  factory PAlertWireValues.fromJson(dynamic raw, List<String> ids) {
    dynamic data = raw is Map ? raw['data'] : null;
    dynamic pga = data is Map ? data['pga'] : null;
    dynamic pgv = data is Map ? data['pgv'] : null;
    Map<String, double> convert(dynamic value) {
      if (value is! Map) return const {};
      final result = <String, double>{};
      for (final entry in value.entries) {
        final v = entry.value;
        final number = v is num
            ? v.toDouble()
            : v is String
            ? double.tryParse(v.trim())
            : null;
        if (number != null) result[entry.key.toString()] = number;
      }
      return result;
    }

    final acceleration = convert(pga is Map ? pga['dataVals'] : null);
    final velocity = convert(pgv is Map ? pgv['dataVals'] : null);
    final rows = Float64List(ids.length * 4);
    for (var i = 0; i < ids.length; i++) {
      final a = acceleration[ids[i]], v = velocity[ids[i]];
      rows[i * 4] = a == null ? 0 : 1;
      rows[i * 4 + 1] = a ?? double.nan;
      rows[i * 4 + 2] = v == null ? 0 : 1;
      rows[i * 4 + 3] = v ?? double.nan;
    }
    return PAlertWireValues(rows, acceleration.length);
  }
}
