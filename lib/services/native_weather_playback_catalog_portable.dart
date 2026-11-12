import 'dart:convert';
import 'dart:typed_data';

/// Explicit backend for platforms where station-core is not supported.
abstract final class NativeWeatherPlaybackCatalog {
  static bool get supported => false;
  static DateTime? _time(String text, int offset) {
    if (!RegExp(r'^\d{14}$').hasMatch(text)) return null;
    final parts = [
      int.parse(text.substring(0, 4)),
      for (var i = 4; i < 14; i += 2) int.parse(text.substring(i, i + 2)),
    ];
    final date = DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
    );
    if (date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2] ||
        date.hour != parts[3] ||
        date.minute != parts[4] ||
        date.second != parts[5])
      return null;
    return date.subtract(Duration(hours: offset));
  }

  static List<Map<String, dynamic>> parse(int kind, Uint8List bytes) {
    var text = utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (kind < 2) {
      final callback = kind == 0 ? 'readRadarList' : 'getPreObs1h';
      final match = RegExp(
        '^$callback\\s*\\(([\\s\\S]*)\\)\\s*;?\$',
      ).firstMatch(text);
      if (match == null) throw const FormatException('Invalid weather JSONP');
      text = match[1]!;
    }
    final raw = jsonDecode(text);
    final rows = kind < 2 && raw is Map
        ? raw['datas']
        : kind < 4
        ? raw
        : raw is Map && raw['returnCode'] == 0
        ? raw['ds']
        : null;
    if (rows is! List)
      throw const FormatException('Missing weather frame catalog');
    final frames = <int, Map<String, dynamic>>{};
    for (final row in rows) {
      if (row is! Map) continue;
      DateTime? time;
      var result = <String, dynamic>{};
      if (kind < 2) {
        final dt = row['dt'];
        if (dt is! String ||
            !RegExp(kind == 0 ? r'^\d{14}$' : r'^\d{10}$').hasMatch(dt))
          continue;
        time = _time(kind == 0 ? dt : '${dt}0000', 8);
        final filename = kind == 0
            ? 'ACHN_QREF_${dt.substring(0, 8)}_${dt.substring(8)}.png'
            : 'prec_$dt.png';
        if (row[kind == 0 ? 'fn' : 'picPath'] != filename) continue;
        result = {
          'url':
              'https://d1.weather.com.cn/radar_channel/${kind == 0 ? 'radar/pic' : 'prec1h'}/$filename',
        };
      } else if (kind < 4) {
        final base = row['basetime'], valid = row['validtime'];
        if (base is! String ||
            valid is! String ||
            _time(base, 0) == null ||
            valid.compareTo(base) > 0)
          continue;
        if (kind == 2 &&
            row['elements'] is List &&
            !(row['elements'] as List).contains('hrpns'))
          continue;
        time = _time(valid, 0);
        result = {'basetime': base, 'validtime': valid};
      } else if (kind == 4) {
        time = _time('${row['dataDate']}${row['dataTime']}', 0);
      }
      if (time == null) continue;
      frames[time.millisecondsSinceEpoch] = {
        'epochMs': time.millisecondsSinceEpoch,
        ...result,
      };
    }
    final times = frames.keys.toList()..sort();
    return times
        .skip(times.length > 24 ? times.length - 24 : 0)
        .map((e) => frames[e]!)
        .toList();
  }
}
