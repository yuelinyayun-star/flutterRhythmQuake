import 'dart:convert';

/// Immutable request description for J-SHIS surface-structure ARV queries.
///
/// The official V4 API accepts an exact WGS84 coordinate and returns the
/// corresponding 250 m mesh. This type intentionally only models the public
/// transport contract; it does not associate a mesh value with a production
/// NIED observation.
class JshisSurfaceStructureRequest {
  const JshisSurfaceStructureRequest({
    required this.latitude,
    required this.longitude,
    this.version = 'V4',
  }) : assert(latitude >= 20 && latitude <= 47),
       assert(longitude >= 122 && longitude <= 154),
       assert(
         version == 'V1' ||
             version == 'V2' ||
             version == 'V3' ||
             version == 'V4',
       );

  static const String host = 'www.j-shis.bosai.go.jp';
  static const String apiDocumentationUrl =
      'https://www.j-shis.bosai.go.jp/api-sstruct-meshinfo';

  final double latitude;
  final double longitude;
  final String version;

  Uri get uri => Uri.https(host, '/map/api/sstrct/$version/meshinfo.geojson', {
    'position': '${longitude.toString()},${latitude.toString()}',
    'epsg': '4326',
    'attr': 'ARV',
    'lang': 'en',
  });
}

/// Parsed subset of one raw J-SHIS GeoJSON response.
///
/// [rawResponse] remains the authoritative stored measurement. The parsed
/// values are only a transparent index for later diagnostic replay work.
class JshisSurfaceStructureArvResponse {
  const JshisSurfaceStructureArvResponse({
    required this.version,
    required this.meshCode,
    required this.arv,
  });

  final String version;
  final String meshCode;
  final double arv;

  static JshisSurfaceStructureArvResponse? tryParse(String rawResponse) {
    final decoded = jsonDecode(rawResponse);
    if (decoded is! Map) return null;
    if (decoded['status'] != 'Success') return null;

    final features = decoded['features'];
    if (features is! List || features.length != 1) return null;
    final feature = features.single;
    if (feature is! Map) return null;
    final properties = feature['properties'];
    if (properties is! Map) return null;
    final metadata = decoded['metaData'];
    if (metadata is! Map) return null;

    final version = metadata['version'];
    final meshCode = properties['meshcode'];
    final arv = _finiteNumber(properties['ARV']);
    if (version is! String ||
        version.isEmpty ||
        meshCode is! String ||
        meshCode.isEmpty ||
        arv == null ||
        arv <= 0) {
      return null;
    }
    return JshisSurfaceStructureArvResponse(
      version: version,
      meshCode: meshCode,
      arv: arv,
    );
  }

  Map<String, Object> toJson() => {
    'version': version,
    'meshCode': meshCode,
    'arv': arv,
  };
}

/// One exact-coordinate J-SHIS V4 ARV term retained for diagnostic replay.
///
/// The term may only be constructed from a successful acquisition record that
/// retains its raw official response path. It deliberately does not provide a
/// nearest-neighbour fallback: an ARV from another 250 m mesh is not an exact
/// NIED station term.
class NiedJshisArvDiagnosticTerm {
  const NiedJshisArvDiagnosticTerm({
    required this.stationCode,
    required this.latitude,
    required this.longitude,
    required this.arv,
    required this.meshCode,
    required this.datasetVersion,
    required this.rawResponsePath,
  });

  final String stationCode;
  final double latitude;
  final double longitude;
  final double arv;
  final String meshCode;
  final String datasetVersion;
  final String rawResponsePath;

  static NiedJshisArvDiagnosticTerm? tryFromAcquisitionRecord(
    Map<Object?, Object?> record,
  ) {
    if (record['status'] != 'success' || record['version'] != 'V4') {
      return null;
    }
    final stationCode = record['stationCode'];
    final meshCode = record['meshCode'];
    final rawResponsePath = record['rawResponsePath'];
    final latitude = _finiteNumber(record['latitude']);
    final longitude = _finiteNumber(record['longitude']);
    final arv = _finiteNumber(record['arv']);
    if (stationCode is! String ||
        stationCode.isEmpty ||
        meshCode is! String ||
        meshCode.isEmpty ||
        rawResponsePath is! String ||
        rawResponsePath.isEmpty ||
        latitude == null ||
        longitude == null ||
        arv == null ||
        arv <= 0) {
      return null;
    }
    return NiedJshisArvDiagnosticTerm(
      stationCode: stationCode,
      latitude: latitude,
      longitude: longitude,
      arv: arv,
      meshCode: meshCode,
      datasetVersion: 'V4',
      rawResponsePath: rawResponsePath,
    );
  }

  bool matchesExactStationCoordinate({
    required String code,
    required double stationLatitude,
    required double stationLongitude,
  }) {
    const coordinateTolerance = 0.0000001;
    return code == stationCode &&
        (stationLatitude - latitude).abs() <= coordinateTolerance &&
        (stationLongitude - longitude).abs() <= coordinateTolerance;
  }
}

double? _finiteNumber(Object? value) {
  final parsed = switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value),
    _ => null,
  };
  return parsed != null && parsed.isFinite ? parsed : null;
}
