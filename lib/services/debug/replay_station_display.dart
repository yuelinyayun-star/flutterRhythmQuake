import '../../models/station_history_frame.dart';
import '../../models/snet_station.dart';
import '../foreground_station_payload.dart';
import '../sources/nied_monitor.dart';
import '../sources/kma_monitor.dart';
import '../sources/cwa_station_service.dart';
import '../sources/palert_service.dart';
import '../sources/palert_detection_grid.dart';
import '../sources/seisjs_service.dart';
import '../sources/lpgm_monitor_service.dart';
import '../sources/shake_detection_service.dart';
import 'package:latlong2/latlong.dart';

/// Playback-only objects, never fed to live detectors, sockets or automation.
class ReplayStationDisplay {
  final _frames = <String, StationHistoryFrame>{};
  List<NiedStation> nied = const [];
  List<KmaStation> kma = const [];
  List<CwaStation> cwa = const [];
  List<SnetStation> snet = const [];
  List<SeisJsStation> seisjs = const [];
  List<PAlertStation> palert = const [];
  List<PAlertDetectionGridCell> palertGrid = const [];
  LpgmSnapshot? lpgm;
  ShakeDetectionSnapshot niedDetection = _idleDetection;
  static const _idleDetection = ShakeDetectionSnapshot(
    stage: ShakeDetectStage.idle,
    weakCount: 0,
    detectedCount: 0,
    strongCount: 0,
    maxShindo: -1,
  );

  void update(Map<String, StationHistoryFrame> frames) {
    if (frames.isEmpty) {
      _frames.clear();
      nied = const [];
      kma = const [];
      cwa = const [];
      snet = const [];
      seisjs = const [];
      palert = const [];
      palertGrid = const [];
      lpgm = null;
      niedDetection = _idleDetection;
      return;
    }
    for (final entry in frames.entries) {
      if (identical(_frames[entry.key], entry.value)) continue;
      _frames[entry.key] = entry.value;
      final snapshot = entry.value.snapshot;
      final stations = snapshot['stations'];
      switch (entry.key) {
        case 'nied':
          nied = ForegroundStationPayload.decodeNied(stations);
          final detection = snapshot['detection'];
          if (detection is Map) {
            final cells = detection['gridCells'] as Map? ?? const {};
            niedDetection = ShakeDetectionSnapshot(
              stage: ShakeDetectStage.values.firstWhere(
                (s) => s.name == detection['stage'],
                orElse: () => ShakeDetectStage.idle,
              ),
              weakCount: detection['weakCount'] as int,
              detectedCount: detection['detectedCount'] as int,
              strongCount: detection['strongCount'] as int,
              maxShindo: detection['maxShindo'] as int,
              gridCells: {
                for (final entry in cells.entries)
                  entry.key as String: NiedDetectionGridCell(
                    center: LatLng(
                      (entry.value['lat'] as num).toDouble(),
                      (entry.value['lng'] as num).toDouble(),
                    ),
                    level: entry.value['level'] as int,
                    shindo: (entry.value['shindo'] as num).toDouble(),
                  ),
              },
              detectedStations: [
                for (final station in detection['detectedStations'] as List)
                  DetectedStationEntry(
                    code: station['code'] as String,
                    prefecture: station['prefecture'] as String,
                    level: station['level'] as int,
                    jmaShindo: station['jmaShindo'] as int,
                    detectState: station['detectState'] as int,
                    detectReason: station['detectReason'] as String,
                  ),
              ],
            );
          } else {
            niedDetection = _idleDetection;
          }
        case 'kma':
          kma = ForegroundStationPayload.decodeKma(stations);
        case 'cwa':
          cwa = ForegroundStationPayload.decodeCwa(stations);
        case 'snet':
          snet = ForegroundStationPayload.decodeSnet(stations);
        case 'seisjs':
          seisjs = ForegroundStationPayload.decodeSeisJs(stations);
        case 'palert':
          palert = ForegroundStationPayload.decodePAlert(stations);
          palertGrid = ForegroundStationPayload.decodePAlertDetection(
            snapshot,
            now: entry.value.receivedAt,
          );
        case 'lpgm':
          lpgm = ForegroundStationPayload.decodeLpgm(snapshot);
      }
    }
  }
}
