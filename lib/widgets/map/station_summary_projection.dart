import '../../services/sources/native_station_summary.dart';
import '../../services/sources/native_ka_history.dart';
import '../../services/sources/nied_monitor.dart';
import '../../services/sources/kma_monitor.dart';
import '../../services/sources/cwa_station_service.dart';
import '../../services/sources/palert_service.dart';
import '../../services/sources/seisjs_service.dart';
import '../../services/sources/shake_detection_service.dart';
import '../../services/sources/lpgm_monitor_service.dart';
import '../../models/snet_station.dart';
import '../ui/station_dashboard.dart';

/// Binds native sidebar selections to existing UI station views. This bridge
/// serializes inputs; it does not choose maxima, rank stations, assign regions
/// or sort. The native owner retains summaries of unchanged networks.
class StationSummaryProjection {
  static bool get supported => NativeStationSummary.supported;
  final _native = NativeStationSummary();
  List<NiedDetectVisualArea> _areas = const [];
  List<NiedStation> _niedCatalogueViews = const [];

  StationSummaryData project({
    required List<NiedStation> nied,
    required List<KmaStation> kma,
    required List<CwaStation> cwa,
    required List<PAlertStation> palert,
    required List<SeisJsStation> seisjs,
    required List<SnetStation> snet,
    required ShakeDetectionSnapshot detection,
    required LpgmSnapshot? lpgm,
    required DateTime windowEnd,
    NativeKaHistorySession? niedProducer,
    SeisJsPreparedSummary? seisjsSummary,
    PAlertPreparedSummary? palertSummary,
    Set<String>? changed,
  }) {
    bool update(String kind) => changed == null || changed.contains(kind);
    if (update('seisjs') && seisjsSummary == null) {
      _native.update(0, seisjs.length, (rows) {
        for (var i = 0; i < seisjs.length; i++) {
          rows[i * 5] = seisjs[i].intensity;
        }
      }, regions: [for (final s in seisjs) s.region]);
    }
    if (update('nied') || update('detection')) {
      // FFI catalogue lifecycle only; these are existing UI views, not a
      // second set of station/detection state. Final metadata is sent once.
      var sameCatalogue = nied.length == _niedCatalogueViews.length;
      if (sameCatalogue) {
        for (var i = 0; i < nied.length; i++) {
          final s = nied[i], old = _niedCatalogueViews[i];
          if (identical(s, old)) continue;
          if (s.code != old.code ||
              s.prefecture != old.prefecture ||
              s.coordinate.latitude != old.coordinate.latitude ||
              s.coordinate.longitude != old.coordinate.longitude) {
            sameCatalogue = false;
            break;
          }
        }
      }
      if (sameCatalogue) {
        if (niedProducer != null) {
          if (niedProducer.count != nied.length) {
            throw StateError('NIED producer directory changed');
          }
          _native.niedKaResults(niedProducer, (active) {
            for (var i = 0; i < nied.length; i++) {
              active[i] = nied[i].isActive ? 1 : 0;
            }
          });
        } else {
          _native.niedLevels(nied.length, (rows) {
            for (var i = 0; i < nied.length; i++) {
              rows[i * 2] = nied[i].level;
              rows[i * 2 + 1] = nied[i].isActive ? 1 : 0;
            }
          });
        }
      } else {
        _niedCatalogueViews = List.of(nied);
        _native.update(
          1,
          nied.length,
          (rows) {
            for (var i = 0; i < nied.length; i++) {
              final s = nied[i];
              final p = i * 5;
              rows[p] = s.level.toDouble();
              rows[p + 1] = s.level.toDouble();
              rows[p + 2] = s.isActive ? 1 : 0;
              rows[p + 3] = s.coordinate.latitude;
              rows[p + 4] = s.coordinate.longitude;
            }
          },
          codes: [for (final s in nied) s.code],
          regions: [for (final s in nied) s.prefecture],
        );
      }
    }
    if (update('cwa')) {
      _native.update(2, cwa.length, (rows) {
        for (var i = 0; i < cwa.length; i++) {
          rows[i * 5] = cwa[i].intensity;
          rows[i * 5 + 1] = cwa[i].alertIntensity;
          rows[i * 5 + 2] = cwa[i].hasAlert ? 1 : 0;
        }
      }, reuseText: true);
    }
    if (update('kma')) {
      _native.update(3, kma.length, (rows) {
        for (var i = 0; i < kma.length; i++) {
          rows[i * 5] = kma[i].holdLevel.toDouble();
        }
      }, reuseText: true);
    }
    if (update('palert') && palertSummary == null) {
      _native.update(4, palert.length, (rows) {
        for (var i = 0; i < palert.length; i++) {
          final s = palert[i];
          final p = i * 5;
          rows[p] = s.heldLevel?.toDouble() ?? double.nan;
          rows[p + 1] = s.pgaGal ?? double.nan;
          rows[p + 2] = s.pgvCms ?? double.nan;
          rows[p + 3] = s.sampledLevel?.toDouble() ?? double.nan;
        }
      }, reuseText: true);
    }
    if (update('snet')) {
      _native.update(5, snet.length, (rows) {
        for (var i = 0; i < snet.length; i++) {
          final s = snet[i];
          final p = i * 5;
          rows[p] = s.shindo;
          rows[p + 1] = s.level.toDouble();
          rows[p + 2] = s.isActive ? 1 : 0;
        }
      }, codes: [for (final s in snet) s.code]);
    }
    if (update('nied') || update('detection')) {
      _native.cells(detection.gridCells.length, (rows) {
        var i = 0;
        for (final cell in detection.gridCells.values) {
          rows[i++] = cell.center.latitude;
          rows[i++] = cell.center.longitude;
          rows[i++] = cell.level.toDouble();
        }
      });
    }
    if (update('nied') || update('detection')) {
      _areas = [
        for (final area in _native.areas)
          NiedDetectVisualArea(name: area.$1, jmaShindo: area.$2),
      ];
    }
    T? selected<T>(List<T> list, int index) => index < 0 ? null : list[index];
    return _native.readIndices(
      (indices) => StationSummaryData()
        ..seisJsStation = seisjsSummary == null
            ? selected(seisjs, indices[0])
            : seisjsSummary.selected
        ..seisJsMaxStation = seisjsSummary == null
            ? selected(seisjs, indices[1])
            : seisjsSummary.maximum
        ..niedMaxStation = selected(nied, indices[2])
        ..treaMaxStation = selected(cwa, indices[3])
        ..kmaMaxStation = selected(kma, indices[4])
        ..pAlertMaxStation = palertSummary == null
            ? selected(palert, indices[5])
            : palertSummary.maximum
        ..snetTopStations = [
          for (var i = 0; i < indices[6]; i++)
            SnetTopStation(
              code: snet[indices[7 + i]].code,
              shindo: snet[indices[7 + i]].shindo,
              jmaIndex: indices[12 + i],
            ),
        ]
        ..snetWindowEnd = indices[6] == 0 ? null : windowEnd
        ..snetWindowStart = indices[6] == 0
            ? null
            : windowEnd.subtract(const Duration(minutes: 10))
        ..niedDetect = NiedDetectSummary(
          stage: detection.stage.name,
          weakCount: detection.weakCount,
          detectedCount: detection.detectedCount,
          strongCount: detection.strongCount,
          maxShindo: detection.maxShindo,
          visualGridCount: detection.gridCells.length,
          detectedStations: detection.detectedStations,
          visualAreas: _areas,
        )
        ..lpgmTime = lpgm?.dataTime
        ..lpgmMaxSva = lpgm?.maxSva
        ..lpgmMaxClass = lpgm?.maxClass
        ..lpgmTopStations = [
          for (final s in lpgm?.topStations ?? const <LpgmStationReading>[])
            LpgmTopStation(code: s.code, sva: s.sva, lpgmClass: s.lpgmClass),
        ],
    );
  }

  void dispose() {
    _native.dispose();
    _niedCatalogueViews = const [];
    _areas = const [];
  }
}
