import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutterrhythmquake/core/source_estimation/jshis_surface_structure_api.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';

const _defaultOutputRoot = '.dart_tool/nied_jshis_arv_v4';
const _schemaVersion = 'nied_jshis_arv_acquisition_v1';

/// Acquires J-SHIS V4 ARV at the exact published NIED station coordinates.
///
/// Each successful official response is written byte-for-byte as received
/// before it is parsed. The generated manifest is a provenance index, not a
/// calibrated station term and is not consumed by production code.
Future<void> main(List<String> args) async {
  final outputRoot = _argument(args, '--output-root') ?? _defaultOutputRoot;
  final limit = _nonNegativeIntArgument(args, '--limit', defaultValue: 0);
  final delayMs = _nonNegativeIntArgument(
    args,
    '--delay-ms',
    defaultValue: 250,
  );
  final retries = _nonNegativeIntArgument(args, '--retries', defaultValue: 2);
  final startAt = _nonNegativeIntArgument(args, '--start-at', defaultValue: 0);
  final stationCodesFilePath = _argument(args, '--station-codes-file');
  final overwrite = args.contains('--overwrite');

  final report = await acquireNiedJshisArvV4(
    outputRoot: Directory(outputRoot),
    startAt: startAt,
    limit: limit,
    delay: Duration(milliseconds: delayMs),
    retries: retries,
    overwrite: overwrite,
    onlyStationCodes: stationCodesFilePath == null
        ? null
        : _readStationCodes(File(stationCodesFilePath)),
  );
  stdout.writeln('wrote J-SHIS V4 NIED ARV acquisition manifest');
  stdout.writeln('root: $outputRoot');
  stdout.writeln(
    'processed in current run: ${report['summary']!['processedInCurrentRun']}',
  );
  stdout.writeln('success: ${report['summary']!['successCount']}');
  stdout.writeln('failure: ${report['summary']!['failureCount']}');
}

Future<Map<String, Map<String, Object?>>> acquireNiedJshisArvV4({
  required Directory outputRoot,
  int startAt = 0,
  int limit = 0,
  Duration delay = const Duration(milliseconds: 250),
  int retries = 2,
  bool overwrite = false,
  Set<String>? onlyStationCodes,
  HttpClient? client,
}) async {
  if (startAt < 0 || limit < 0 || delay.isNegative || retries < 0) {
    throw ArgumentError(
      'startAt, limit, delay, and retries must be non-negative.',
    );
  }
  final ownedClient = client == null;
  final httpClient = client ?? HttpClient();
  final rawDirectory = Directory(
    '${outputRoot.path}${Platform.pathSeparator}raw',
  )..createSync(recursive: true);
  final manifestFile = File(
    '${outputRoot.path}${Platform.pathSeparator}manifest.json',
  );
  final rowsByStationCode = _readExistingRows(manifestFile);
  final stationDatabase = onlyStationCodes == null
      ? NiedStationDb.stations
      : NiedStationDb.stations
            .where((station) => onlyStationCodes.contains(station['code']))
            .toList(growable: false);
  final selected = stationDatabase.skip(startAt);
  final stations = limit == 0 ? selected : selected.take(limit);
  var processedInRun = 0;

  try {
    for (final station in stations) {
      final row = await _acquireStation(
        station: station.cast<String, Object?>(),
        rawDirectory: rawDirectory,
        delay: delay,
        retries: retries,
        overwrite: overwrite,
        client: httpClient,
      );
      rowsByStationCode[row['stationCode']! as String] = row;
      processedInRun += 1;
    }
  } finally {
    if (ownedClient) httpClient.close(force: true);
  }

  final rows = [
    for (final station in NiedStationDb.stations)
      if (rowsByStationCode.containsKey(station['code']))
        rowsByStationCode[station['code']]!,
  ];
  final successCount = rows.where((row) => row['status'] == 'success').length;
  final report = <String, Map<String, Object?>>{
    'schema': {
      'version': _schemaVersion,
      'purpose': 'diagnostic_only_exact_nied_coordinate_jshis_arv_acquisition',
      'productionMagnitudeEnabled': false,
    },
    'source': {
      'provider': 'J-SHIS / NIED',
      'documentationUrl': JshisSurfaceStructureRequest.apiDocumentationUrl,
      'datasetVersion': 'V4',
      'coordinateReferenceSystem': 'WGS84 / EPSG:4326',
      'attribute': 'ARV',
      'attributeDefinition':
          'maximum velocity amplification from engineering bedrock (Vs=400 m/s) to surface',
      'rawResponsePolicy': 'raw GeoJSON is stored before parsing',
    },
    'summary': {
      'requestedStationCount': NiedStationDb.stations.length,
      'requestedSelectionStationCount': stationDatabase.length,
      'startAt': startAt,
      'limit': limit,
      'processedInCurrentRun': processedInRun,
      'storedRecordCount': rows.length,
      'successCount': successCount,
      'failureCount': rows.length - successCount,
      'completeCoverage':
          rows.length == NiedStationDb.stations.length &&
          successCount == NiedStationDb.stations.length,
    },
    'records': {'items': rows},
  };
  manifestFile.parent.createSync(recursive: true);
  await manifestFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  return report;
}

Set<String> _readStationCodes(File file) {
  if (!file.existsSync()) {
    throw ArgumentError.value(
      file.path,
      '--station-codes-file',
      'File not found.',
    );
  }
  final raw = file.readAsStringSync();
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return <String>{};
  if (trimmed.startsWith('[')) {
    final decoded = jsonDecode(trimmed);
    if (decoded is! List || decoded.any((value) => value is! String)) {
      throw const FormatException(
        'Station-code JSON must be an array of strings.',
      );
    }
    return decoded.cast<String>().toSet();
  }
  return trimmed.split(RegExp(r'\s+')).where((code) => code.isNotEmpty).toSet();
}

Future<Map<String, Object?>> _acquireStation({
  required Map<String, Object?> station,
  required Directory rawDirectory,
  required Duration delay,
  required int retries,
  required bool overwrite,
  required HttpClient client,
}) async {
  final code = station['code']! as String;
  final latitude = (station['lat']! as num).toDouble();
  final longitude = (station['lng']! as num).toDouble();
  final request = JshisSurfaceStructureRequest(
    latitude: latitude,
    longitude: longitude,
  );
  final rawFile = File(
    '${rawDirectory.path}${Platform.pathSeparator}$code.geojson',
  );
  final base = <String, Object?>{
    'stationCode': code,
    'stationName': station['name'],
    'network': station['network'],
    'latitude': latitude,
    'longitude': longitude,
    'requestUrl': request.uri.toString(),
    'rawResponsePath': rawFile.path,
  };

  try {
    final usedExistingRawResponse = !overwrite && rawFile.existsSync();
    final rawResponse = usedExistingRawResponse
        ? await rawFile.readAsString()
        : await _requestAndPersistRaw(
            request: request,
            rawFile: rawFile,
            retries: retries,
            client: client,
          );
    final rawRetrievedAtUtc = (await rawFile.lastModified())
        .toUtc()
        .toIso8601String();
    final parsed = JshisSurfaceStructureArvResponse.tryParse(rawResponse);
    if (parsed == null) {
      return {
        ...base,
        'status': 'invalid_official_response',
        'rawRetrievedAtUtc': rawRetrievedAtUtc,
        'indexedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'usedExistingRawResponse': usedExistingRawResponse,
      };
    }
    return {
      ...base,
      'status': 'success',
      'rawRetrievedAtUtc': rawRetrievedAtUtc,
      'indexedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'usedExistingRawResponse': usedExistingRawResponse,
      ...parsed.toJson(),
    };
  } catch (error) {
    return {
      ...base,
      'status': 'request_failed',
      'indexedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'errorType': error.runtimeType.toString(),
      'error': '$error',
    };
  } finally {
    if (delay != Duration.zero) await Future<void>.delayed(delay);
  }
}

Map<String, Map<String, Object?>> _readExistingRows(File manifestFile) {
  if (!manifestFile.existsSync()) return <String, Map<String, Object?>>{};
  try {
    final decoded = jsonDecode(manifestFile.readAsStringSync());
    if (decoded is! Map) return <String, Map<String, Object?>>{};
    final records = decoded['records'];
    if (records is! Map) return <String, Map<String, Object?>>{};
    final items = records['items'];
    if (items is! List) return <String, Map<String, Object?>>{};
    return {
      for (final item in items)
        if (item is Map && item['stationCode'] is String)
          item['stationCode']! as String: item.cast<String, Object?>(),
    };
  } on FormatException {
    return <String, Map<String, Object?>>{};
  }
}

Future<String> _requestAndPersistRaw({
  required JshisSurfaceStructureRequest request,
  required File rawFile,
  required int retries,
  required HttpClient client,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt <= retries; attempt++) {
    try {
      final httpRequest = await client
          .getUrl(request.uri)
          .timeout(const Duration(seconds: 30));
      httpRequest.headers.set(
        HttpHeaders.acceptHeader,
        'application/geo+json, application/json',
      );
      final response = await httpRequest.close().timeout(
        const Duration(seconds: 30),
      );
      final body = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'J-SHIS returned HTTP ${response.statusCode} for $request',
        );
      }
      await rawFile.writeAsString(body, encoding: utf8, flush: true);
      return body;
    } catch (error) {
      lastError = error;
      if (attempt < retries) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
  }
  throw lastError ?? StateError('No J-SHIS request attempt was made.');
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

int _nonNegativeIntArgument(
  List<String> args,
  String name, {
  required int defaultValue,
}) {
  final raw = _argument(args, name);
  if (raw == null) return defaultValue;
  final value = int.tryParse(raw);
  if (value == null || value < 0) {
    throw ArgumentError.value(raw, name, 'Expected a non-negative integer.');
  }
  return value;
}
