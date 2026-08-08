import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image_lib;
import 'package:latlong2/latlong.dart';

import '../../models/nied_scan_positions.dart';
import '../../models/nied_station_db.dart';
import '../../services/sources/nied_gif_value_decoder.dart';
import 'ka_intensity_input.dart';

class KaCaptureInputExtractor {
  const KaCaptureInputExtractor();

  KaYahooGifComparisonReport compareDirectory(String directoryPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw FileSystemException('Capture directory not found', directoryPath);
    }

    final eventId = _readEventId(directory);
    final siteListFile = File(
      '${directory.path}${Platform.pathSeparator}sitelist.json',
    );
    if (!siteListFile.existsSync()) {
      throw FileSystemException('sitelist.json not found', siteListFile.path);
    }

    final siteList = _readJson(siteListFile);
    final siteConfigId = siteList['siteConfigId'] as String?;
    final sites = _mapYahooSites(siteList);
    final yahooFiles = _indexedFiles(directory, _yahooTimestamp);
    final gifFiles = _indexedFiles(directory, _surfaceGifTimestamp);
    final timestamps = {...yahooFiles.keys, ...gifFiles.keys}.toList()..sort();

    final pairs = <KaYahooGifPair>[];
    var yahooUsableCount = 0;
    var gifUsableCount = 0;
    var unmatchedYahooCount = 0;
    var unmatchedGifCount = 0;
    var stationMappingFailureCount = 0;
    var timestampMismatchFrameCount = 0;
    final allObservations = <KaIntensityObservation>[];

    for (final timestamp in timestamps) {
      final yahooFile = yahooFiles[timestamp];
      final gifFile = gifFiles[timestamp];
      final yahooFrame = yahooFile == null ? null : _readJson(yahooFile);
      final realTimeData = yahooFrame?['realTimeData'] as Map<String, dynamic>?;
      final intensity = realTimeData?['intensity'] as String?;
      final yahooObservedAt = _parseObservedAt(realTimeData?['dataTime']);
      final fileObservedAt = _parseTimestamp(timestamp);
      final sameSecond =
          yahooObservedAt == null ||
          yahooObservedAt.millisecondsSinceEpoch ==
              fileObservedAt.millisecondsSinceEpoch;
      if (!sameSecond) timestampMismatchFrameCount++;

      final frameFlags = <String>[
        if (realTimeData?['siteConfigId'] != siteConfigId)
          'site_config_mismatch',
        if (!sameSecond) 'observed_at_mismatch',
      ];

      image_lib.Image? gifImage;
      if (gifFile != null) {
        gifImage = image_lib.decodeImage(gifFile.readAsBytesSync());
      }

      final pairedStationIds = <String>{};
      final usableYahooStationIds = <String>{};
      final usableGifStationIds = <String>{};

      for (final site in sites) {
        if (site == null) {
          stationMappingFailureCount++;
          continue;
        }
        final stationCode = site.stationId;
        KaIntensityObservation? yahooObservation;
        if (intensity != null && site.yahooSiteIndex < intensity.length) {
          final level = intensity.codeUnitAt(site.yahooSiteIndex) - 100;
          final qualityFlags = <String>[
            ...frameFlags,
            if (!KaLevelScale.isInDomain(level)) 'yahoo_level_out_of_domain',
          ];
          yahooObservation = KaIntensityObservation(
            eventId: eventId,
            station: site,
            observedAt: fileObservedAt,
            kind: KaIntensityValueKind.yahooLevel,
            sourceLayer: 'yahoo_realtime_intensity',
            qualityFlags: qualityFlags,
            yahooRawLevel: level,
          );
          allObservations.add(yahooObservation);
          if (yahooObservation.hasUsableYahooLevel && sameSecond) {
            yahooUsableCount++;
            usableYahooStationIds.add(stationCode);
          }
        }

        KaIntensityObservation? gifObservation;
        final scanPosition = NiedScanPositions.positions[stationCode];
        if (gifImage != null && scanPosition != null) {
          final x = scanPosition[0];
          final y = scanPosition[1];
          if (x >= 0 && y >= 0 && x < gifImage.width && y < gifImage.height) {
            final pixel = gifImage.getPixel(x, y);
            final decoded = NiedGifValueDecoder.decodeObservationFromRgba(
              pixel.r.toInt(),
              pixel.g.toInt(),
              pixel.b.toInt(),
            );
            final shindo = decoded?.shindo;
            gifObservation = KaIntensityObservation(
              eventId: eventId,
              station: site,
              observedAt: fileObservedAt,
              kind: KaIntensityValueKind.gifContinuousShindo,
              sourceLayer: 'jma_s',
              qualityFlags: [
                ...frameFlags,
                if (decoded == null) 'gif_pixel_undecodable',
              ],
              gifContinuousShindo: shindo,
              gifKaLevel: shindo == null
                  ? null
                  : KaLevelScale.fromContinuousShindo(shindo),
            );
            allObservations.add(gifObservation);
            if (gifObservation.hasUsableGifLevel && sameSecond) {
              gifUsableCount++;
              usableGifStationIds.add(stationCode);
            }
          }
        }

        if (sameSecond &&
            yahooObservation?.hasUsableYahooLevel == true &&
            gifObservation?.hasUsableGifLevel == true) {
          pairs.add(
            KaYahooGifPair(yahoo: yahooObservation!, gif: gifObservation!),
          );
          pairedStationIds.add(stationCode);
        }
      }

      unmatchedYahooCount += usableYahooStationIds
          .difference(pairedStationIds)
          .length;
      unmatchedGifCount += usableGifStationIds
          .difference(pairedStationIds)
          .length;
    }

    return KaYahooGifComparisonReport.fromPairs(
      eventId: eventId,
      captureDirectory: directory.path,
      frameCount: timestamps.length,
      yahooFrameCount: yahooFiles.length,
      gifFrameCount: gifFiles.length,
      yahooUsableCount: yahooUsableCount,
      gifUsableCount: gifUsableCount,
      unmatchedYahooCount: unmatchedYahooCount,
      unmatchedGifCount: unmatchedGifCount,
      stationMappingFailureCount: stationMappingFailureCount,
      timestampMismatchFrameCount: timestampMismatchFrameCount,
      pairs: pairs,
      observations: allObservations,
    );
  }

  Map<String, File> _indexedFiles(
    Directory directory,
    String? Function(String name) timestampParser,
  ) {
    final result = <String, File>{};
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final timestamp = timestampParser(name);
      if (timestamp == null) continue;
      final existing = result[timestamp];
      if (existing == null || _isPreferredFile(entity, existing)) {
        result[timestamp] = entity;
      }
    }
    return result;
  }

  bool _isPreferredFile(File candidate, File existing) {
    final candidateName = candidate.uri.pathSegments.last;
    final existingName = existing.uri.pathSegments.last;
    return candidateName.endsWith('.yahoo.parsed.json') &&
        !existingName.endsWith('.yahoo.parsed.json');
  }

  String? _yahooTimestamp(String name) {
    final match = RegExp(
      r'^(\d{14})(?:\.yahoo(?:\.parsed)?|)\.json$',
    ).firstMatch(name);
    return match?.group(1);
  }

  String? _surfaceGifTimestamp(String name) {
    final match = RegExp(
      r'^(\d{14})(?:\.lmoni)?\.jma_s\.gif$',
    ).firstMatch(name);
    return match?.group(1);
  }

  List<KaStationIdentity?> _mapYahooSites(Map<String, dynamic> siteList) {
    final items = siteList['items'] as List<dynamic>? ?? const [];
    final database = NiedStationDb.stations;
    final mapped = <KaStationIdentity?>[];
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
        if (roundTo1((candidate['lat'] as num).toDouble()) == targetLat &&
            roundTo1((candidate['lng'] as num).toDouble()) == targetLng) {
          matchedIndex = candidateIndex;
          break;
        }
      }
      if (matchedIndex == null) {
        mapped.add(null);
        continue;
      }
      databaseCursor = matchedIndex;
      final station = database[matchedIndex];
      mapped.add(
        KaStationIdentity(
          stationId: station['code'] as String,
          coordinate: LatLng(
            (station['lat'] as num).toDouble(),
            (station['lng'] as num).toDouble(),
          ),
          network: (station['network'] as String?) ?? 'unknown',
          yahooSiteIndex: itemIndex,
        ),
      );
    }
    return mapped;
  }

  Map<String, dynamic> _readJson(File file) {
    final bytes = file.readAsBytesSync();
    final decoded = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        ? gzip.decode(bytes)
        : bytes;
    return jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
  }

  String _readEventId(Directory directory) {
    for (final name in const ['manifest.json', 'capture_manifest.json']) {
      final file = File('${directory.path}${Platform.pathSeparator}$name');
      if (!file.existsSync()) continue;
      final manifest = _readJson(file);
      final id = manifest['packageId'] ?? manifest['caseId'];
      if (id is String && id.isNotEmpty) return id;
    }
    return directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
  }

  DateTime? _parseObservedAt(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final value = raw.trim();
    final hasExplicitOffset = RegExp(
      r'(?:Z|[+-]\d{2}:?\d{2})$',
    ).hasMatch(value);
    if (hasExplicitOffset) {
      final iso = DateTime.tryParse(value);
      if (iso != null) return iso;
    }
    final match = RegExp(
      r'^(\d{4})[/-](\d{2})[/-](\d{2})\s+(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(value);
    if (match == null) return null;
    return _jstWallTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }

  DateTime _parseTimestamp(String timestamp) => _jstWallTime(
    int.parse(timestamp.substring(0, 4)),
    int.parse(timestamp.substring(4, 6)),
    int.parse(timestamp.substring(6, 8)),
    int.parse(timestamp.substring(8, 10)),
    int.parse(timestamp.substring(10, 12)),
    int.parse(timestamp.substring(12, 14)),
  );

  DateTime _jstWallTime(
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) => DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
  ).subtract(const Duration(hours: 9));
}

class KaYahooGifComparisonReport {
  const KaYahooGifComparisonReport._({
    required this.eventId,
    required this.captureDirectory,
    required this.frameCount,
    required this.yahooFrameCount,
    required this.gifFrameCount,
    required this.yahooUsableCount,
    required this.gifUsableCount,
    required this.unmatchedYahooCount,
    required this.unmatchedGifCount,
    required this.stationMappingFailureCount,
    required this.timestampMismatchFrameCount,
    required this.exactMatchRate,
    required this.meanDifference,
    required this.medianDifference,
    required this.rmse,
    required this.minimumDifference,
    required this.maximumDifference,
    required this.differenceByYahooLevel,
    required this.differenceByNetwork,
    required this.pairs,
    required this.realtimeSnapshots,
    required this.finalYahooPeaks,
    required this.finalGifPeaks,
  });

  factory KaYahooGifComparisonReport.fromPairs({
    required String eventId,
    required String captureDirectory,
    required int frameCount,
    required int yahooFrameCount,
    required int gifFrameCount,
    required int yahooUsableCount,
    required int gifUsableCount,
    required int unmatchedYahooCount,
    required int unmatchedGifCount,
    required int stationMappingFailureCount,
    required int timestampMismatchFrameCount,
    required List<KaYahooGifPair> pairs,
    required List<KaIntensityObservation> observations,
  }) {
    final differences = pairs.map((pair) => pair.levelDifference).toList()
      ..sort();
    final squaredSum = differences.fold<double>(
      0,
      (sum, value) => sum + value * value,
    );
    final mean = differences.isEmpty
        ? double.nan
        : differences.reduce((a, b) => a + b) / differences.length;
    final median = differences.isEmpty
        ? double.nan
        : differences.length.isOdd
        ? differences[differences.length ~/ 2].toDouble()
        : (differences[differences.length ~/ 2 - 1] +
                  differences[differences.length ~/ 2]) /
              2;

    final byLevel = <String, List<int>>{};
    final byNetwork = <String, List<int>>{};
    for (final pair in pairs) {
      (byLevel['${pair.yahoo.yahooRawLevel}'] ??= []).add(pair.levelDifference);
      (byNetwork[pair.yahoo.station.network] ??= []).add(pair.levelDifference);
    }

    final snapshots = <String, List<KaIntensityObservation>>{};
    for (final observation in observations) {
      if (observation.kind != KaIntensityValueKind.yahooLevel ||
          !observation.hasUsableYahooLevel) {
        continue;
      }
      final key = observation.observedAt.toIso8601String();
      (snapshots[key] ??= []).add(observation);
    }

    return KaYahooGifComparisonReport._(
      eventId: eventId,
      captureDirectory: captureDirectory,
      frameCount: frameCount,
      yahooFrameCount: yahooFrameCount,
      gifFrameCount: gifFrameCount,
      yahooUsableCount: yahooUsableCount,
      gifUsableCount: gifUsableCount,
      unmatchedYahooCount: unmatchedYahooCount,
      unmatchedGifCount: unmatchedGifCount,
      stationMappingFailureCount: stationMappingFailureCount,
      timestampMismatchFrameCount: timestampMismatchFrameCount,
      exactMatchRate: differences.isEmpty
          ? double.nan
          : differences.where((value) => value == 0).length /
                differences.length,
      meanDifference: mean,
      medianDifference: median,
      rmse: differences.isEmpty
          ? double.nan
          : math.sqrt(squaredSum / differences.length),
      minimumDifference: differences.isEmpty ? null : differences.first,
      maximumDifference: differences.isEmpty ? null : differences.last,
      differenceByYahooLevel: _summarizeGroups(byLevel),
      differenceByNetwork: _summarizeGroups(byNetwork),
      pairs: List.unmodifiable(pairs),
      realtimeSnapshots: snapshots.entries
          .map(
            (entry) => KaRealtimeSnapshotInput(
              eventId: eventId,
              observedAt: DateTime.parse(entry.key),
              valueKind: KaIntensityValueKind.yahooLevel,
              observations: List.unmodifiable(entry.value),
            ),
          )
          .toList(growable: false),
      finalYahooPeaks: _buildPeaks(
        eventId,
        observations,
        KaIntensityValueKind.yahooLevel,
      ),
      finalGifPeaks: _buildPeaks(
        eventId,
        observations,
        KaIntensityValueKind.gifContinuousShindo,
      ),
    );
  }

  final String eventId;
  final String captureDirectory;
  final int frameCount;
  final int yahooFrameCount;
  final int gifFrameCount;
  final int yahooUsableCount;
  final int gifUsableCount;
  final int unmatchedYahooCount;
  final int unmatchedGifCount;
  final int stationMappingFailureCount;
  final int timestampMismatchFrameCount;
  final double exactMatchRate;
  final double meanDifference;
  final double medianDifference;
  final double rmse;
  final int? minimumDifference;
  final int? maximumDifference;
  final Map<String, Map<String, Object?>> differenceByYahooLevel;
  final Map<String, Map<String, Object?>> differenceByNetwork;
  final List<KaYahooGifPair> pairs;
  final List<KaRealtimeSnapshotInput> realtimeSnapshots;
  final List<KaFinalPeakCalibrationInput> finalYahooPeaks;
  final List<KaFinalPeakCalibrationInput> finalGifPeaks;

  Map<String, Object?> toJson({bool includePairs = true}) => {
    'schemaVersion': 'ka_yahoo_gif_input_comparison_v1',
    'eventId': eventId,
    'captureDirectory': captureDirectory,
    'frameCount': frameCount,
    'yahooFrameCount': yahooFrameCount,
    'gifFrameCount': gifFrameCount,
    'pairCount': pairs.length,
    'yahooUsableCount': yahooUsableCount,
    'gifUsableCount': gifUsableCount,
    'unmatchedYahooCount': unmatchedYahooCount,
    'unmatchedGifCount': unmatchedGifCount,
    'stationMappingFailureCount': stationMappingFailureCount,
    'timestampMismatchFrameCount': timestampMismatchFrameCount,
    'exactMatchRate': exactMatchRate,
    'meanLevelDifference': meanDifference,
    'medianLevelDifference': medianDifference,
    'levelDifferenceRmse': rmse,
    'minimumLevelDifference': minimumDifference,
    'maximumLevelDifference': maximumDifference,
    'differenceByYahooLevel': differenceByYahooLevel,
    'differenceByNetwork': differenceByNetwork,
    'realtimeSnapshotCount': realtimeSnapshots.length,
    'finalYahooPeakCount': finalYahooPeaks.length,
    'finalGifPeakCount': finalGifPeaks.length,
    if (includePairs) 'pairs': pairs.map((pair) => pair.toJson()).toList(),
  };

  static Map<String, Map<String, Object?>> _summarizeGroups(
    Map<String, List<int>> groups,
  ) => {
    for (final entry in groups.entries)
      entry.key: {
        'count': entry.value.length,
        'exactMatchRate':
            entry.value.where((value) => value == 0).length /
            entry.value.length,
        'meanLevelDifference':
            entry.value.reduce((a, b) => a + b) / entry.value.length,
      },
  };

  static List<KaFinalPeakCalibrationInput> _buildPeaks(
    String eventId,
    List<KaIntensityObservation> observations,
    KaIntensityValueKind kind,
  ) {
    final grouped = <String, List<KaIntensityObservation>>{};
    for (final observation in observations) {
      if (observation.kind != kind) continue;
      final usable = kind == KaIntensityValueKind.yahooLevel
          ? observation.hasUsableYahooLevel
          : observation.hasUsableGifLevel;
      if (!usable) continue;
      (grouped[observation.station.stationId] ??= []).add(observation);
    }

    final peaks = <KaFinalPeakCalibrationInput>[];
    for (final stationObservations in grouped.values) {
      var peak = stationObservations.first;
      double value(KaIntensityObservation observation) =>
          kind == KaIntensityValueKind.yahooLevel
          ? observation.yahooRawLevel!.toDouble()
          : observation.gifContinuousShindo!;
      for (final observation in stationObservations.skip(1)) {
        if (value(observation) > value(peak)) peak = observation;
      }
      peaks.add(
        KaFinalPeakCalibrationInput(
          eventId: eventId,
          station: peak.station,
          valueKind: kind,
          peakObservedAt: peak.observedAt,
          peakValue: value(peak),
          frameCount: stationObservations.length,
          qualityFlags: stationObservations
              .expand((observation) => observation.qualityFlags)
              .toSet()
              .toList(),
        ),
      );
    }
    peaks.sort((a, b) => a.station.stationId.compareTo(b.station.stationId));
    return List.unmodifiable(peaks);
  }
}
