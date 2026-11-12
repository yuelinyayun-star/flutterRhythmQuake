import 'dart:convert';
import 'package:archive/archive.dart';

/// CSV and named SSE used by the public ExpTech rts.v1 feed.
/// The decoded observation map is never rewritten into a legacy packet.
abstract final class TremProtocol {
  static const stationHosts = [
    'https://static.core-tnn1.exptech.dev',
    'https://static.core-tyo1.exptech.dev',
  ];
  static const stationPath = '/resource/station';
  static const rtsHosts = [
    'https://api.lb-tpe1.exptech.dev',
    'https://api.lb-khh1.exptech.dev',
  ];
  static const rtsPath = '/api/v1/trem/sse?topics=trem.rts.v1&mode=live';

  static List<
    ({String id, double lat, double lon, int code, String net, bool work})
  >
  catalogue(String csv) {
    final lines = const LineSplitter().convert(csv.replaceFirst('\uFEFF', ''));
    if (lines.isEmpty) return const [];
    final columns = lines.first.split(',').map((s) => s.trim()).toList();
    if (!['id', 'lat', 'lon', 'code'].every(columns.contains)) return const [];
    final result =
        <
          ({String id, double lat, double lon, int code, String net, bool work})
        >[];
    for (final line in lines.skip(1)) {
      final cells = line.split(',');
      String cell(String name) {
        final i = columns.indexOf(name);
        return i < 0 || i >= cells.length ? '' : cells[i].trim();
      }

      final id = cell('id');
      final lat = double.tryParse(cell('lat'));
      final lon = double.tryParse(cell('lon'));
      final code = int.tryParse(cell('code'));
      if (id.isEmpty ||
          lat == null ||
          lon == null ||
          code == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        continue;
      }
      result.add((
        id: id,
        lat: lat,
        lon: lon,
        code: code,
        net: cell('net'),
        work: cell('work') == '1',
      ));
    }
    return result;
  }

  static Map<String, dynamic>? payload(String data) {
    try {
      final compact = data.replaceAll(RegExp(r'\s+'), '');
      final Object? decoded;
      if (data.trimLeft().startsWith('{')) {
        decoded = jsonDecode(data);
      } else {
        final bytes = GZipDecoder().decodeBytes(base64Decode(compact));
        if (bytes.length > 8 * 1024 * 1024) return null;
        decoded = jsonDecode(utf8.decode(bytes));
      }
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static Stream<Map<String, dynamic>> decode(Stream<List<int>> bytes) async* {
    var event = '';
    final data = StringBuffer();
    await for (final line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (event.isEmpty || event == 'trem.rts.v1') {
          final frame = payload(data.toString());
          if (frame != null &&
              (frame['stations'] is Map || frame['station'] is Map)) {
            yield frame;
          }
        }
        event = '';
        data.clear();
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        if (data.isNotEmpty) data.write('\n');
        data.write(line.substring(5).replaceFirst(RegExp(r'^ '), ''));
        if (data.length > 8 * 1024 * 1024) {
          throw const FormatException('TREM SSE block too large');
        }
      }
    }
  }
}
