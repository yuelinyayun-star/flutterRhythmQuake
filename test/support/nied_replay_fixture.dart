import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/nied_monitor.dart';

class NiedDecodedGifFrame {
  final List<int> packedRgb;
  final Uint8List gifBytes;

  const NiedDecodedGifFrame({required this.packedRgb, required this.gifBytes});
}

Directory workspaceDirectory(String relativePath) {
  return Directory.fromUri(
    Directory.current.uri.resolve(relativePath.replaceAll('\\', '/')),
  );
}

Future<NiedDecodedGifFrame?> decodeNiedGifFile(File file) async {
  if (!file.existsSync()) return null;
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    image.dispose();
    codec.dispose();
    return null;
  }

  final pixels = List<int>.filled(image.width * image.height, 0);
  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    final r = byteData.getUint8(offset);
    final g = byteData.getUint8(offset + 1);
    final b = byteData.getUint8(offset + 2);
    pixels[i] = (r << 16) | (g << 8) | b;
  }

  image.dispose();
  codec.dispose();
  return NiedDecodedGifFrame(
    packedRgb: pixels,
    gifBytes: Uint8List.fromList(bytes),
  );
}

String formatNiedTimeKey(DateTime jst) {
  final year = jst.year.toString().padLeft(4, '0');
  final month = jst.month.toString().padLeft(2, '0');
  final day = jst.day.toString().padLeft(2, '0');
  final hour = jst.hour.toString().padLeft(2, '0');
  final minute = jst.minute.toString().padLeft(2, '0');
  final second = jst.second.toString().padLeft(2, '0');
  return '$year$month$day$hour$minute$second';
}

Future<Map<String, dynamic>> readNiedJsonFile(File file) async {
  final bytes = await file.readAsBytes();
  List<int> decoded = bytes;
  if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    decoded = gzip.decode(bytes);
  }
  return jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
}

Future<List<NiedStation>> buildYahooReplayStations(
  File sitelistFile, {
  bool includeUnmatchedPlaceholders = false,
}) async {
  final data = await readNiedJsonFile(sitelistFile);
  final items = data['items'] as List<dynamic>? ?? const [];
  final database = NiedStationDb.stations;
  final stations = <NiedStation>[];
  var databaseCursor = -1;

  double roundTo1(double value) => (value * 10).roundToDouble() / 10;

  for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
    final item = items[itemIndex] as List<dynamic>;
    final targetLat = roundTo1((item[0] as num).toDouble());
    final targetLng = roundTo1((item[1] as num).toDouble());

    int? matchedIndex;
    for (
      var offset = 0;
      offset < 10 && databaseCursor + offset + 1 < database.length;
      offset++
    ) {
      final candidateIndex = databaseCursor + offset + 1;
      final candidate = database[candidateIndex];
      final lat = roundTo1((candidate['lat'] as num).toDouble());
      final lng = roundTo1((candidate['lng'] as num).toDouble());
      if (lat == targetLat && lng == targetLng) {
        matchedIndex = candidateIndex;
        break;
      }
    }

    if (matchedIndex == null) {
      if (includeUnmatchedPlaceholders) {
        stations.add(
          NiedStation(
            id: itemIndex,
            code: 'YAH$itemIndex',
            name: '',
            coordinate: LatLng(
              (item[0] as num).toDouble(),
              (item[1] as num).toDouble(),
            ),
            network: 'K-NET',
            prefecture: '',
            expireSeconds: NiedStation.kaExpireSeconds,
          ),
        );
      }
      continue;
    }
    databaseCursor = matchedIndex;
    final station = database[matchedIndex];
    stations.add(
      NiedStation(
        id: itemIndex,
        code: station['code'] as String,
        name: station['name'] as String,
        coordinate: LatLng(
          (station['lat'] as num).toDouble(),
          (station['lng'] as num).toDouble(),
        ),
        network: (station['network'] as String?) ?? 'K-NET',
        prefecture: (station['pref'] as String?) ?? '',
        expireSeconds: NiedStation.kaExpireSeconds,
      ),
    );
  }
  return stations;
}

bool applyYahooReplayFrame(
  List<NiedStation> stations,
  Map<String, dynamic> data,
  DateTime observedAt,
) {
  final realTimeData = data['realTimeData'] as Map<String, dynamic>?;
  final intensity = realTimeData?['intensity'] as String?;
  if (intensity == null) return false;

  for (
    var index = 0;
    index < stations.length && index < intensity.length;
    index++
  ) {
    final detectLevel = intensity.codeUnitAt(index) - 100;
    final station = stations[index];
    final previous = station.lastDataTime;
    if (previous != null) {
      final diffMs = observedAt.difference(previous).inMilliseconds;
      if (diffMs > 1000) {
        final missingFrames = ((diffMs / 1000).round() - 1)
            .clamp(0, NiedStation.maxExpireSeconds)
            .toInt();
        station.recentLevel.insertAll(0, List<int>.filled(missingFrames, -1));
        if (station.recentLevel.length > NiedStation.maxExpireSeconds) {
          station.recentLevel = station.recentLevel.sublist(
            0,
            NiedStation.maxExpireSeconds,
          );
        }
        if (diffMs > 10000) station.isActive = false;
      }
    }
    station.lastUpdate = observedAt;
    station.lastDataTime = observedAt;
    station.update(detectLevel);
  }
  return true;
}
