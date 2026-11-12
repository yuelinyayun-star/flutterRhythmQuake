import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/jma_lpgm_bulletin.dart';
import 'nied_intensity_layer.dart' show NiedIntensityNumberMarker;

@immutable
class JmaLpgmStationLocation {
  const JmaLpgmStationLocation({
    required this.code,
    required this.name,
    required this.position,
    required this.network,
    this.aliases = const [],
    this.niedSiteCode,
  });

  /// Official JMA PointSeismicLgIntensity code (7 digits).
  final String code;
  final String name;
  final LatLng position;
  final String network;
  final List<String> aliases;
  final String? niedSiteCode;
}

/// Complete station directory from the JMA PointSeismicLgIntensity code table.
/// Coordinates cover all 703 entries: 672 JMA and 31 NIED K-NET stations.
@immutable
class JmaLpgmStationLocations {
  const JmaLpgmStationLocations._({
    required this.stations,
    required this.byCode,
    required this.byName,
  });

  static const empty = JmaLpgmStationLocations._(
    stations: [],
    byCode: {},
    byName: {},
  );

  static Future<JmaLpgmStationLocations>? _cached;

  final List<JmaLpgmStationLocation> stations;
  final Map<String, JmaLpgmStationLocation> byCode;
  final Map<String, JmaLpgmStationLocation> byName;

  static Future<JmaLpgmStationLocations> load() =>
      _cached ??= _read().catchError((Object error) {
        _cached = null;
        throw error;
      });

  static String normalizeName(String value) =>
      value.trim().replaceFirst(RegExp(r'[＊*]+$'), '').trim();

  static Future<JmaLpgmStationLocations> _read() async {
    final json =
        jsonDecode(
              await rootBundle.loadString(
                'assets/maps/jma_lpgm_station_locations.json',
              ),
            )
            as Map<String, dynamic>;
    final rawStations = json['stations'] as List;
    final expectedCount = json['stationCount'] as int;
    if (rawStations.length != expectedCount || expectedCount != 703) {
      throw StateError(
        'Incomplete JMA long-period station directory: '
        '${rawStations.length}/$expectedCount',
      );
    }

    final stations = <JmaLpgmStationLocation>[];
    final byCode = <String, JmaLpgmStationLocation>{};
    final byName = <String, JmaLpgmStationLocation>{};

    void addName(String value, JmaLpgmStationLocation location) {
      final key = normalizeName(value);
      if (key.isEmpty) return;
      final previous = byName[key];
      if (previous != null && previous.code != location.code) {
        throw StateError('Duplicate station name alias: $key');
      }
      byName[key] = location;
    }

    for (final raw in rawStations) {
      final data = raw as Map<String, dynamic>;
      final code = data['code']?.toString() ?? '';
      final name = data['name']?.toString() ?? '';
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();
      if (code.isEmpty ||
          name.isEmpty ||
          lat < 20 ||
          lat > 50 ||
          lng < 120 ||
          lng > 155) {
        throw StateError('Invalid JMA long-period station entry: $code $name');
      }
      final aliases = (data['aliases'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      final location = JmaLpgmStationLocation(
        code: code,
        name: name,
        position: LatLng(lat, lng),
        network: data['network']?.toString() ?? 'unknown',
        aliases: aliases,
        niedSiteCode: data['niedSiteCode']?.toString(),
      );
      if (byCode.containsKey(code)) {
        throw StateError('Duplicate JMA long-period station code: $code');
      }
      stations.add(location);
      byCode[code] = location;
      addName(name, location);
      for (final alias in aliases) {
        addName(alias, location);
      }
    }

    if (stations.where((station) => station.network == 'NIED K-NET').length !=
        31) {
      throw StateError('NIED long-period station coverage is incomplete');
    }
    return JmaLpgmStationLocations._(
      stations: List.unmodifiable(stations),
      byCode: Map.unmodifiable(byCode),
      byName: Map.unmodifiable(byName),
    );
  }

  static List<({JmaLpgmStation station, LatLng position})> located(
    JmaLpgmBulletin bulletin,
    JmaLpgmStationLocations locations,
  ) {
    final result = <({JmaLpgmStation station, LatLng position})>[];
    for (final station in bulletin.stations) {
      if (station.lgInt < 1 || station.lgInt > 4) continue;
      final matched =
          locations.byCode[station.code] ??
          locations.byName[normalizeName(station.name)];
      if (matched == null) continue;
      result.add((station: station, position: matched.position));
    }
    return result;
  }
}

/// Long-period grades use NIED's measured-value numeric icon,
/// never the NIED idle/dense-network tiny dot path.
class JmaLpgmMarkerStyle {
  JmaLpgmMarkerStyle._();

  static const double markerSize = NiedIntensityNumberMarker.markerSize;

  static Color colorForClass(int lgInt) => jmaLpgmClassColor(lgInt);

  static Color foregroundForClass(int lgInt) =>
      colorForClass(lgInt).computeLuminance() > 0.42
      ? Colors.black
      : Colors.white;
}

/// VXSE62 observation stations overlay ordinary intensity, no LPGM polygons.
/// Uses the exact NIED value marker widget without NIED's tiny-dot fallback.
class JmaLpgmStationLayer extends StatefulWidget {
  const JmaLpgmStationLayer({super.key, required this.bulletin});
  final JmaLpgmBulletin bulletin;

  @override
  State<JmaLpgmStationLayer> createState() => _JmaLpgmStationLayerState();
}

class _JmaLpgmStationLayerState extends State<JmaLpgmStationLayer> {
  JmaLpgmStationLocations _locations = JmaLpgmStationLocations.empty;

  @override
  void initState() {
    super.initState();
    JmaLpgmStationLocations.load().then((data) {
      if (mounted) setState(() => _locations = data);
    });
  }

  @override
  Widget build(BuildContext context) {
    final stations = JmaLpgmStationLocations.located(
      widget.bulletin,
      _locations,
    );
    if (stations.isEmpty) return const SizedBox.shrink();

    final markers = <Marker>[];
    for (final item in stations) {
      final level = item.station.lgInt;
      markers.add(
        Marker(
          point: item.position,
          width: JmaLpgmMarkerStyle.markerSize,
          height: JmaLpgmMarkerStyle.markerSize,
          child: NiedIntensityNumberMarker(
            key: ValueKey('jma_lpgm_station_${item.station.code}'),
            color: JmaLpgmMarkerStyle.colorForClass(level),
            label: level.toString(),
            level: level,
            highIntensity: false,
            foregroundColor: JmaLpgmMarkerStyle.foregroundForClass(level),
          ),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }
}
