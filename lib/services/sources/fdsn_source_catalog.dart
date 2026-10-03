/// Shared native/Android/UI source configuration. Never alias a new provider
/// to EarthScope: waveform provenance and instrument metadata must agree.
class FdsnSourceConfig {
  const FdsnSourceConfig({
    required this.name,
    required this.overlayKey,
    required this.host,
    required this.stationUrl,
    this.port = 18000,
    this.secure = false,
    this.priority = 0,
    this.batchSubscribe = false,
    this.routeMetadata = false,
  });

  final String name;
  final String overlayKey;
  final String host;
  final String stationUrl;
  final int port;
  final bool secure;
  final int priority;
  final bool batchSubscribe;
  final bool routeMetadata;
  String get preferenceKey => 'map_overlay_$overlayKey';
  bool get inheritsExistingSelection =>
      name != 'EarthScope' && name != 'GEOFON';

  bool readEnabled(bool? Function(String) read) =>
      read(preferenceKey) ??
      (name != 'ORFEUS' &&
          inheritsExistingSelection &&
          ((read('map_overlay_fdsnEarthScope') ?? false) ||
              (read('map_overlay_fdsnGeofon') ?? false)));
}

class FdsnSourceCatalog {
  static Future<void> initializePreferences(
    bool? Function(String) read,
    Future<bool> Function(String, bool) write,
  ) async {
    for (final source in sources) {
      if (source.inheritsExistingSelection &&
          read(source.preferenceKey) == null) {
        await write(source.preferenceKey, source.readEnabled(read));
      }
    }
  }

  static const sources = [
    FdsnSourceConfig(
      name: 'EarthScope',
      overlayKey: 'fdsnEarthScope',
      host: 'rtserve.earthscope.org',
      port: 18500,
      secure: true,
      stationUrl: 'https://service.earthscope.org/fdsnws/station/1/query',
      priority: 2,
    ),
    FdsnSourceConfig(
      name: 'GEOFON',
      routeMetadata: true,
      overlayKey: 'fdsnGeofon',
      host: 'geofon.gfz.de',
      stationUrl: 'https://geofon.gfz-potsdam.de/fdsnws/station/1/query',
      priority: 1,
    ),
    FdsnSourceConfig(
      name: 'GeoNet',
      overlayKey: 'fdsnGeoNet',
      host: 'link.geonet.org.nz',
      stationUrl: 'https://service.geonet.org.nz/fdsnws/station/1/query',
    ),
    FdsnSourceConfig(
      name: 'RESIF',
      overlayKey: 'fdsnResif',
      host: 'rtserve.resif.fr',
      stationUrl: 'https://ws.resif.fr/fdsnws/station/1/query',
    ),
    FdsnSourceConfig(
      name: 'IPGP',
      batchSubscribe: true,
      overlayKey: 'fdsnIpgp',
      host: 'rtserver.ipgp.fr',
      stationUrl: 'https://ws.ipgp.fr/fdsnws/station/1/query',
      priority: -1,
    ),
    FdsnSourceConfig(
      name: 'ORFEUS',
      routeMetadata: true,
      batchSubscribe: true,
      overlayKey: 'fdsnOrfeus',
      host: 'eida.orfeus-eu.org',
      stationUrl: 'https://www.orfeus-eu.org/fdsnws/station/1/query',
    ),
    FdsnSourceConfig(
      name: 'BGR',
      routeMetadata: true,
      batchSubscribe: true,
      overlayKey: 'fdsnBgr',
      host: 'eida.bgr.de',
      stationUrl: 'https://eida.bgr.de/fdsnws/station/1/query',
      priority: -1,
    ),
  ];

  static const names = {
    'EarthScope',
    'GEOFON',
    'GeoNet',
    'RESIF',
    'IPGP',
    'ORFEUS',
    'BGR',
  };

  static FdsnSourceConfig? find(String name) {
    for (final source in sources) {
      if (source.name == name) return source;
    }
    return null;
  }

  static Set<String> enabledSources(bool Function(String) isOverlayEnabled) => {
    for (final source in sources)
      if (isOverlayEnabled(source.overlayKey)) source.name,
  };
}
