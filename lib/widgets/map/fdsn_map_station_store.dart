import '../../services/sources/fdsn_station_service.dart';

/// Metadata is indexed once. Motion updates replace one immutable station, not
/// an entire catalogue; the map only scans stations with recent observations.
class FdsnMapStationStore {
  final _catalogues = <String, Map<String, FdsnStation>>{};
  final _active = <String, Map<int, FdsnStation>>{};
  final _ranks = <String, Map<String, int>>{};
  final _orderedRanks = <String, List<int>>{};
  List<FdsnStation>? _snapshot;
  List<String> _snapshotSources = const [];
  int? _expires;

  bool get isNotEmpty => _catalogues.isNotEmpty;

  void setSource(String source, List<FdsnStation> stations) {
    _snapshot = null;
    _catalogues[source] = {for (final s in stations) s.code: s};
    _ranks[source] = {
      for (var i = 0; i < stations.length; i++) stations[i].code: i,
    };
    final now = DateTime.now().microsecondsSinceEpoch;
    _active[source] = {
      for (var i = 0; i < stations.length; i++)
        if (_recent(stations[i], now)) i: stations[i],
    };
    _orderedRanks[source] = _active[source]!.keys.toList();
  }

  FdsnStation? find(String source, String code) => _catalogues[source]?[code];

  void update(FdsnStation station) {
    final catalogue = _catalogues[station.source];
    final code = station.code;
    if (catalogue == null || !catalogue.containsKey(code)) return;
    catalogue[code] = station;
    final rank = _ranks[station.source]![code]!;
    final active = _active[station.source]!;
    if (!active.containsKey(rank)) _orderedRanks.remove(station.source);
    active[rank] = station;
    _snapshot = null;
  }

  List<FdsnStation> displayStations(Set<String> sources) {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_snapshot != null &&
        (_expires == null || now <= _expires!) &&
        sources.length == _snapshotSources.length) {
      var index = 0;
      var sameSources = true;
      for (final source in sources) {
        if (source != _snapshotSources[index++]) {
          sameSources = false;
          break;
        }
      }
      if (sameSources) return _snapshot!;
    }
    _expires = null;
    final ordered = <FdsnStation>[];
    for (final source in sources) {
      final active = _active[source];
      if (active == null) continue;
      // Preserve catalogue order for same-level overlap, even when packets arrive
      // in a different order. Ranks are independent of the motion values.
      final ranks = _orderedRanks.putIfAbsent(
        source,
        () => active.keys.toList()..sort(),
      );
      for (final rank in ranks) {
        final station = active[rank]!;
        if (!_recent(station, now)) {
          active.remove(rank);
          _orderedRanks.remove(source);
          continue;
        }
        final end =
            station.lastMotionUpdate!.microsecondsSinceEpoch +
            FdsnStation.motionRetention.inMicroseconds;
        if (_expires == null || end < _expires!) _expires = end;
        ordered.add(station);
      }
    }
    _snapshotSources = sources.toList();
    return _snapshot = List.unmodifiable(deduplicateFdsnStations(ordered));
  }

  bool removeSource(String source) {
    _snapshot = null;
    _active.remove(source);
    _orderedRanks.remove(source);
    _ranks.remove(source);
    return _catalogues.remove(source) != null;
  }

  void clear() {
    _catalogues.clear();
    _active.clear();
    _ranks.clear();
    _orderedRanks.clear();
    _snapshot = null;
    _snapshotSources = const [];
    _expires = null;
  }

  bool _recent(FdsnStation station, int now) =>
      station.lastMotionUpdate != null &&
      now - station.lastMotionUpdate!.microsecondsSinceEpoch <=
          FdsnStation.motionRetention.inMicroseconds;
}
