import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:flutterrhythmquake/core/source_estimation/nied_pgv_magnitude_diagnostics.dart';
import 'package:flutterrhythmquake/core/source_estimation/source_estimation_models.dart';
import 'package:flutterrhythmquake/models/nied_scan_positions.dart';
import 'package:flutterrhythmquake/models/nied_station_db.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_observation.dart';
import 'package:flutterrhythmquake/services/sources/nied_gif_value_decoder.dart';
import 'package:flutterrhythmquake/services/sources/shindo_color_util.dart';

const _gifZipPath = String.fromEnvironment('NIED_HISTORICAL_GIF_ZIP');
const _jma2011SourceZipPath = String.fromEnvironment(
  'NIED_JMA_2011_SOURCE_ZIP',
);
const _jma2018SourceZipPath = String.fromEnvironment(
  'NIED_JMA_2018_SOURCE_ZIP',
);
const _hokkaidoWaveformPackagePath = String.fromEnvironment(
  'NIED_HOKKAIDO_WAVEFORM_PACKAGE',
);
const _hokkaidoRawPgaAuditPath = String.fromEnvironment(
  'NIED_HOKKAIDO_RAW_PGA_AUDIT',
);
const _noto2024SourceZipPath = String.fromEnvironment(
  'NIED_JMA_NOTO_2024_SOURCE_ZIP',
);
const _kumamoto2016SourceZipPath = String.fromEnvironment(
  'NIED_JMA_KUMAMOTO_2016_SOURCE_ZIP',
);
const _kumamotoRawPgaAuditPath = String.fromEnvironment(
  'NIED_KUMAMOTO_RAW_PGA_AUDIT',
);
const _notoRawPgaAuditPath = String.fromEnvironment('NIED_NOTO_RAW_PGA_AUDIT');

void main() {
  test(
    'probes historical acmap_s PGA against raw JMA source-process fault grids',
    () async {
      final gifs = ZipDecoder().decodeBytes(
        await File(_gifZipPath).readAsBytes(),
      );
      final sourceModels = <String, _JmaSourceProcessModel>{
        '110311': await _JmaSourceProcessModel.fromZip(
          File(_jma2011SourceZipPath),
        ),
        '180906': await _JmaSourceProcessModel.fromZip(
          File(_jma2018SourceZipPath),
        ),
      };
      final report = <String, Object?>{};
      final historicalPgaPeaksByDate =
          <String, Map<String, _HistoricalPgaPeak>>{};

      for (final entry in sourceModels.entries) {
        final dateDirectory = entry.key;
        final sourceModel = entry.value;
        final jmaEntries = _layerEntries(gifs, dateDirectory, 'jma_s');
        final pgaEntries = _layerEntries(gifs, dateDirectory, 'acmap_s');
        expect(jmaEntries, isNotEmpty);
        expect(pgaEntries, isNotEmpty);

        final jmaPeaks = await _scanJmaPeaks(jmaEntries);
        final pgaPeaks = await _scanPgaPeaks(pgaEntries);
        historicalPgaPeaksByDate[dateDirectory] = pgaPeaks;
        final records = _historicalRecords(
          jmaPeaks: jmaPeaks,
          pgaPeaks: pgaPeaks,
        );
        final distanceDomainMaxKm = _siMidorikawa1999DistanceDomainMaxKm(
          sourceModel.jmaMagnitude,
        );
        final domainRecords = records
            .where(
              (record) =>
                  sourceModel.distanceKmToFault(record.descriptor.coordinate) <=
                  distanceDomainMaxKm,
            )
            .toList(growable: false);
        final typeScenarios = <String, Object?>{
          for (final faultType in NiedPgaFaultType.values)
            faultType.name: niedGifPgaMagnitudeDiagnostics(
              stations: domainRecords,
              averageFocalDepthKm: sourceModel.slipWeightedMeanDepthKm,
              faultType: faultType,
              distanceDefinition:
                  'jma_source_process_subfault_rectangles_local_tangent_km',
              faultDistanceKmFor: (record) =>
                  sourceModel.distanceKmToFault(record.descriptor.coordinate),
            ),
        };
        report[dateDirectory] = {
          'historicalGifLayers': const ['jma_s', 'acmap_s'],
          'gifFrameCounts': {
            'jma_s': jmaEntries.length,
            'acmap_s': pgaEntries.length,
          },
          'jmaEvent': {
            'jmaMagnitude': sourceModel.jmaMagnitude,
            'momentMagnitude': sourceModel.momentMagnitude,
            'faultCellCount': sourceModel.cells.length,
            'subfaultLengthKm': sourceModel.subfaultLengthKm,
            'subfaultWidthKm': sourceModel.subfaultWidthKm,
            'slipWeightedMeanDepthKm': sourceModel.slipWeightedMeanDepthKm,
          },
          'stationSelection': {
            'surfaceDisplayStationDb': 'current_nied_station_db',
            'colorDecode':
                'francois_hsv_piecewise_polynomial_common_kmoni_scale',
            'participantRule': 'event_maximum_jma_s_continuous_shindo >= -0.8',
            'participantCountBeforeDistanceDomain': records.length,
            'participantCountInDistanceDomain': domainRecords.length,
            // Si and Midorikawa (1999), section 2: their PGA regression data
            // limit depends on source magnitude, rather than treating distant
            // map colours as equally informative amplitude observations.
            'siMidorikawa1999DistanceDomainMaxKm': distanceDomainMaxKm,
            'pgaPaletteCeilingExcludedByDiagnostic': true,
          },
          // The JMA source-process package describes geometry but does not map
          // the event into the three Si-Midorikawa fault categories. Keep all
          // scenarios separate; selecting the closest result would be tuning.
          'faultTypeScenarios': typeScenarios,
        };
      }

      if (_hokkaidoWaveformPackagePath.isNotEmpty) {
        final hokkaidoReport = report['180906']! as Map<String, Object?>;
        hokkaidoReport['officialWaveformPgaComparison'] =
            await _officialWaveformPgaComparison(
              packageFile: File(_hokkaidoWaveformPackagePath),
              sourceModel: sourceModels['180906']!,
              historicalGifPgaPeaks: historicalPgaPeaksByDate['180906']!,
            );
      }
      if (_hokkaidoRawPgaAuditPath.isNotEmpty) {
        final hokkaidoReport = report['180906']! as Map<String, Object?>;
        hokkaidoReport['rawHorizontalComponentPgaComparison'] =
            await _rawHorizontalComponentPgaComparison(
              auditFile: File(_hokkaidoRawPgaAuditPath),
              sourceModel: sourceModels['180906']!,
              historicalGifPgaPeaks: historicalPgaPeaksByDate['180906']!,
            );
      }

      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(report));
    },
    skip:
        _gifZipPath.isEmpty ||
            _jma2011SourceZipPath.isEmpty ||
            _jma2018SourceZipPath.isEmpty
        ? 'Pass historical GIF and the two raw JMA source-process ZIP paths.'
        : false,
  );

  test(
    'accepts an official JMA source-process ZIP with root-level data files',
    () async {
      final source = await _JmaSourceProcessModel.fromZip(
        File(_noto2024SourceZipPath),
      );
      expect(source.jmaMagnitude, 7.6);
      expect(source.momentMagnitude, 7.43);
      expect(source.cells, isNotEmpty);
      expect(source.subfaultLengthKm, greaterThan(0));
      expect(source.subfaultWidthKm, greaterThan(0));
    },
    skip: _noto2024SourceZipPath.isEmpty
        ? 'Pass the official JMA Noto 2024 source-process ZIP path.'
        : false,
  );

  test(
    'probes raw horizontal-component PGA across frozen source-process cases',
    () async {
      final cases = <({String caseId, File sourceFile, File auditFile})>[
        (
          caseId: 'kumamoto_20160416_m73',
          sourceFile: File(_kumamoto2016SourceZipPath),
          auditFile: File(_kumamotoRawPgaAuditPath),
        ),
        (
          caseId: 'hokkaido_iburi_20180906_m66',
          sourceFile: File(_jma2018SourceZipPath),
          auditFile: File(_hokkaidoRawPgaAuditPath),
        ),
        (
          caseId: 'noto_peninsula_20240101_m76',
          sourceFile: File(_noto2024SourceZipPath),
          auditFile: File(_notoRawPgaAuditPath),
        ),
      ];
      final report = <String, Object?>{};
      for (final item in cases) {
        final source = await _JmaSourceProcessModel.fromZip(item.sourceFile);
        report[item.caseId] = {
          'officialJmaSourceProcess': {
            'jmaMagnitude': source.jmaMagnitude,
            'momentMagnitude': source.momentMagnitude,
            'faultCellCount': source.cells.length,
            'subfaultLengthKm': source.subfaultLengthKm,
            'subfaultWidthKm': source.subfaultWidthKm,
            'slipWeightedMeanDepthKm': source.slipWeightedMeanDepthKm,
          },
          'rawHorizontalComponentPga':
              await _rawHorizontalComponentPgaComparison(
                auditFile: item.auditFile,
                sourceModel: source,
                historicalGifPgaPeaks: const {},
              ),
        };
      }
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(report));
    },
    skip:
        _kumamoto2016SourceZipPath.isEmpty ||
            _kumamotoRawPgaAuditPath.isEmpty ||
            _jma2018SourceZipPath.isEmpty ||
            _hokkaidoRawPgaAuditPath.isEmpty ||
            _noto2024SourceZipPath.isEmpty ||
            _notoRawPgaAuditPath.isEmpty
        ? 'Pass the three official source-process ZIPs and raw PGA audit paths.'
        : false,
  );
}

double _siMidorikawa1999DistanceDomainMaxKm(double jmaMagnitude) {
  if (jmaMagnitude >= 7.0) return 300.0;
  if (jmaMagnitude >= 6.6) return 200.0;
  if (jmaMagnitude >= 6.3) return 150.0;
  return 100.0;
}

List<ArchiveFile> _layerEntries(
  Archive archive,
  String dateDirectory,
  String layer,
) {
  final pattern = RegExp(
    '${RegExp.escape(dateDirectory)}/${RegExp.escape(layer)}/'
    r'\d{14}_\d+\.gif$',
  );
  final entries =
      archive.files
          .where((entry) => entry.isFile && pattern.hasMatch(entry.name))
          .toList(growable: false)
        ..sort((left, right) => left.name.compareTo(right.name));
  return entries;
}

Future<Map<String, double>> _scanJmaPeaks(List<ArchiveFile> entries) async {
  final peaks = <String, double>{};
  for (final entry in entries) {
    final pixels = await _decodeGif(entry);
    for (final station in _stationSamples) {
      final position = _colorPositionAt(pixels, station.sample);
      if (position == null) continue;
      final observation = NiedGifValueDecoder.decodeObservationFromPosition(
        position,
        layer: NiedGifLayer.realtimeShindo,
      );
      final shindo = observation.shindo;
      if (shindo == null) continue;
      final previous = peaks[station.code];
      if (previous == null || shindo > previous) peaks[station.code] = shindo;
    }
  }
  return peaks;
}

Future<Map<String, _HistoricalPgaPeak>> _scanPgaPeaks(
  List<ArchiveFile> entries,
) async {
  final peaks = <String, _HistoricalPgaPeak>{};
  for (final entry in entries) {
    final time = _gifTimeFromEntryName(entry.name);
    final pixels = await _decodeGif(entry);
    for (final station in _stationSamples) {
      final position = _colorPositionAt(pixels, station.sample);
      if (position == null) continue;
      final pga = NiedGifValueDecoder.decodeObservationFromPosition(
        position,
        layer: NiedGifLayer.peakAcceleration,
      ).pga;
      if (pga == null) continue;
      final previous = peaks[station.code];
      if (previous == null || pga > previous.value) {
        peaks[station.code] = _HistoricalPgaPeak(
          value: pga,
          colorPosition: position,
          dataTime: time,
        );
      }
    }
  }
  return peaks;
}

List<SeismicStationEventRecord> _historicalRecords({
  required Map<String, double> jmaPeaks,
  required Map<String, _HistoricalPgaPeak> pgaPeaks,
}) {
  const pgaProvenance = ObservationProvenance(
    origin: ObservationOrigin.niedGifLayer,
    quantity: StationValueType.pga,
    layerId: 'acmap_s',
    isIndependentPhysicalMeasurement: true,
  );
  final records = <SeismicStationEventRecord>[];
  for (final station in _stationSamples) {
    final jmaPeak = jmaPeaks[station.code];
    final pgaPeak = pgaPeaks[station.code];
    if (jmaPeak == null || jmaPeak < -0.8 || pgaPeak == null) continue;
    final record = SeismicStationEventRecord(
      descriptor: SeismicStationDescriptor(
        stationId: station.code,
        code: station.code,
        sourceId: 'nied_historical_gif',
        network: station.network,
        coordinate: station.coordinate,
        sensorRole: StationSensorRole.surface,
      ),
      firstObservedAt: pgaPeak.dataTime,
      firstTriggerAt: pgaPeak.dataTime,
      peakValue: jmaPeak,
      lastValue: jmaPeak,
    );
    record.provenance[StationValueType.pga] = pgaProvenance;
    record.eventPhysicalPeaks[StationValueType.pga] =
        SeismicPhysicalObservation(
          quantity: StationValueType.pga,
          layerId: 'acmap_s',
          value: pgaPeak.value,
          colorPosition: pgaPeak.colorPosition,
          dataTime: pgaPeak.dataTime,
          receivedAt: pgaPeak.dataTime,
        );
    records.add(record);
  }
  return records;
}

/// Runs the same PGA inversion against independently computed K-NET/KiK-net
/// waveform peaks. This is deliberately kept beside the historical GIF probe
/// as a comparison domain, never a claim that projected waveform observations
/// are decoded GIF pixels.
Future<Map<String, Object?>> _officialWaveformPgaComparison({
  required File packageFile,
  required _JmaSourceProcessModel sourceModel,
  required Map<String, _HistoricalPgaPeak> historicalGifPgaPeaks,
}) async {
  final raw =
      jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
  final stationsByCode = <String, _OfficialWaveformStation>{};
  for (final stationRaw in (raw['stations'] as List<Object?>).cast<Map>()) {
    if (stationRaw['sensorRole'] != 'surface') continue;
    final code = stationRaw['stationCode'] as String?;
    final latitude = stationRaw['latitude'];
    final longitude = stationRaw['longitude'];
    if (code == null || latitude is! num || longitude is! num) continue;
    stationsByCode[code] = _OfficialWaveformStation(
      code: code,
      coordinate: LatLng(latitude.toDouble(), longitude.toDouble()),
      network: stationRaw['network'] as String? ?? 'official_waveform',
    );
  }

  final pgaPeaks = <String, _OfficialWaveformPgaPeak>{};
  for (final observationRaw
      in (raw['observations'] as List<Object?>).cast<Map>()) {
    if (observationRaw['sensorRole'] != 'surface') continue;
    final code = observationRaw['stationCode'] as String?;
    final pga = observationRaw['pgaGal'];
    final observedAt = observationRaw['observedAtUtc'] as String?;
    if (code == null || pga is! num || observedAt == null || pga <= 0) continue;
    final peak = _OfficialWaveformPgaPeak(
      value: pga.toDouble(),
      dataTime: DateTime.parse(observedAt).toUtc(),
    );
    final previous = pgaPeaks[code];
    if (previous == null || peak.value > previous.value) {
      pgaPeaks[code] = peak;
    }
  }

  const provenance = ObservationProvenance(
    origin: ObservationOrigin.officialWaveform,
    quantity: StationValueType.pga,
    layerId: 'knet_kiknet_offset_corrected_waveform_peak',
    isIndependentPhysicalMeasurement: true,
  );
  final records = <SeismicStationEventRecord>[];
  for (final entry in pgaPeaks.entries) {
    final station = stationsByCode[entry.key];
    if (station == null) continue;
    final peak = entry.value;
    final record = SeismicStationEventRecord(
      descriptor: SeismicStationDescriptor(
        stationId: station.code,
        code: station.code,
        sourceId: 'official_waveform_pga_diagnostic',
        network: station.network,
        coordinate: station.coordinate,
        sensorRole: StationSensorRole.surface,
      ),
      firstObservedAt: peak.dataTime,
      // The package is event-scoped and does not contain the untriggered
      // complete network. This marks only package membership for the
      // diagnostic's existing participant gate; it is not a live trigger.
      firstTriggerAt: peak.dataTime,
    );
    record.provenance[StationValueType.pga] = provenance;
    record.eventPhysicalPeaks[StationValueType.pga] =
        SeismicPhysicalObservation(
          quantity: StationValueType.pga,
          layerId: 'knet_kiknet_offset_corrected_waveform_peak',
          value: peak.value,
          dataTime: peak.dataTime,
          receivedAt: peak.dataTime,
          qualityFlags: const {
            'official_waveform',
            'offset_corrected_acceleration',
            'not_real_nied_gif',
          },
        );
    records.add(record);
  }

  final distanceDomainMaxKm = _siMidorikawa1999DistanceDomainMaxKm(
    sourceModel.jmaMagnitude,
  );
  final domainRecords = records
      .where(
        (record) =>
            sourceModel.distanceKmToFault(record.descriptor.coordinate) <=
            distanceDomainMaxKm,
      )
      .toList(growable: false);
  return {
    'comparisonDomain':
        'official_waveform_features_not_real_nied_gif_not_gif_calibration',
    'inputPackage': packageFile.path,
    'sourceFeatureFormat': raw['sourceFeatureFormat'],
    'inputQualityFlags': raw['qualityFlags'],
    'memberRule': 'event_scoped_waveform_package_finite_pga_peak',
    'surfaceStationCountBeforeDistanceDomain': records.length,
    'surfaceStationCountInDistanceDomain': domainRecords.length,
    'siMidorikawa1999DistanceDomainMaxKm': distanceDomainMaxKm,
    'historicalGifPgaToOfficialWaveformPeakComparison':
        _compareHistoricalGifPgaToOfficialWaveform(
          historicalGifPgaPeaks: historicalGifPgaPeaks,
          waveformPgaPeaks: pgaPeaks,
        ),
    'faultTypeScenarios': {
      for (final faultType in NiedPgaFaultType.values)
        faultType.name: niedGifPgaMagnitudeDiagnostics(
          stations: domainRecords,
          averageFocalDepthKm: sourceModel.slipWeightedMeanDepthKm,
          faultType: faultType,
          distanceDefinition:
              'jma_source_process_subfault_rectangles_local_tangent_km',
          faultDistanceKmFor: (record) =>
              sourceModel.distanceKmToFault(record.descriptor.coordinate),
        ),
    },
  };
}

/// Compares the same inversion with the paper's horizontal-component selection
/// rule, but only after explicitly retaining the raw package's missing response
/// correction and band-pass filtering limitations.
Future<Map<String, Object?>> _rawHorizontalComponentPgaComparison({
  required File auditFile,
  required _JmaSourceProcessModel sourceModel,
  required Map<String, _HistoricalPgaPeak> historicalGifPgaPeaks,
}) async {
  final raw =
      jsonDecode(await auditFile.readAsString()) as Map<String, dynamic>;
  final pgaPeaks = <String, _OfficialWaveformPgaPeak>{};
  final records = <SeismicStationEventRecord>[];
  const provenance = ObservationProvenance(
    origin: ObservationOrigin.officialWaveform,
    quantity: StationValueType.pga,
    layerId: 'knet_raw_offset_corrected_largest_horizontal_component_peak',
    isIndependentPhysicalMeasurement: true,
  );
  for (final stationRaw in (raw['stations'] as List<Object?>).cast<Map>()) {
    if (stationRaw['sensorRole'] != 'surface') continue;
    final code = stationRaw['stationCode'] as String?;
    final latitude = stationRaw['stationLatitude'];
    final longitude = stationRaw['stationLongitude'];
    final pga = stationRaw['paperPgaCandidateGal'];
    final dataTime = stationRaw['sampleStartTimeUtc'] as String?;
    if (code == null ||
        latitude is! num ||
        longitude is! num ||
        pga is! num ||
        dataTime == null ||
        pga <= 0) {
      continue;
    }
    final peak = _OfficialWaveformPgaPeak(
      value: pga.toDouble(),
      dataTime: DateTime.parse(dataTime).toUtc(),
    );
    pgaPeaks[code] = peak;
    final record = SeismicStationEventRecord(
      descriptor: SeismicStationDescriptor(
        stationId: code,
        code: code,
        sourceId: 'official_waveform_horizontal_component_pga_diagnostic',
        network: stationRaw['network'] as String? ?? 'official_waveform',
        coordinate: LatLng(latitude.toDouble(), longitude.toDouble()),
        sensorRole: StationSensorRole.surface,
      ),
      firstObservedAt: peak.dataTime,
      // The offline audit contains event-scoped downloaded records only. This
      // marks package membership for the diagnostic gate; it is not a trigger.
      firstTriggerAt: peak.dataTime,
    );
    record.provenance[StationValueType.pga] = provenance;
    record.eventPhysicalPeaks[StationValueType
        .pga] = SeismicPhysicalObservation(
      quantity: StationValueType.pga,
      layerId: 'knet_raw_offset_corrected_largest_horizontal_component_peak',
      value: peak.value,
      dataTime: peak.dataTime,
      receivedAt: peak.dataTime,
      qualityFlags: const {
        'official_waveform',
        'raw_offset_corrected_acceleration',
        'largest_horizontal_component_peak',
        'no_instrument_response_correction',
        'no_noise_selected_band_pass_filter',
        'not_real_nied_gif',
      },
    );
    records.add(record);
  }

  final distanceDomainMaxKm = _siMidorikawa1999DistanceDomainMaxKm(
    sourceModel.jmaMagnitude,
  );
  final domainRecords = records
      .where(
        (record) =>
            sourceModel.distanceKmToFault(record.descriptor.coordinate) <=
            distanceDomainMaxKm,
      )
      .toList(growable: false);
  return {
    'comparisonDomain':
        'raw_knet_horizontal_component_peak_not_response_corrected_not_band_pass_filtered',
    'inputAudit': auditFile.path,
    'inputAuditSchema': raw['schemaVersion'],
    'measurementDefinition':
        'largest absolute NS or EW component peak after raw constant-offset removal',
    'notPaperCompatibleBecause': const [
      'no_instrument_response_correction',
      'no_noise_selected_band_pass_filter',
    ],
    'memberRule': 'event_scoped_waveform_package_finite_pga_peak',
    'surfaceStationCountBeforeDistanceDomain': records.length,
    'surfaceStationCountInDistanceDomain': domainRecords.length,
    'siMidorikawa1999DistanceDomainMaxKm': distanceDomainMaxKm,
    'historicalGifPgaToRawHorizontalComponentPeakComparison':
        _compareHistoricalGifPgaToOfficialWaveform(
          historicalGifPgaPeaks: historicalGifPgaPeaks,
          waveformPgaPeaks: pgaPeaks,
        ),
    'faultTypeScenarios': {
      for (final faultType in NiedPgaFaultType.values)
        faultType.name: niedGifPgaMagnitudeDiagnostics(
          stations: domainRecords,
          averageFocalDepthKm: sourceModel.slipWeightedMeanDepthKm,
          faultType: faultType,
          distanceDefinition:
              'jma_source_process_subfault_rectangles_local_tangent_km',
          faultDistanceKmFor: (record) =>
              sourceModel.distanceKmToFault(record.descriptor.coordinate),
        ),
    },
  };
}

Map<String, Object?> _compareHistoricalGifPgaToOfficialWaveform({
  required Map<String, _HistoricalPgaPeak> historicalGifPgaPeaks,
  required Map<String, _OfficialWaveformPgaPeak> waveformPgaPeaks,
}) {
  final log10WaveformToGifRatios = <double>[];
  for (final entry in waveformPgaPeaks.entries) {
    final gifPeak = historicalGifPgaPeaks[entry.key];
    if (gifPeak == null || gifPeak.value <= 0 || !gifPeak.value.isFinite) {
      continue;
    }
    final waveformPeak = entry.value.value;
    if (waveformPeak <= 0 || !waveformPeak.isFinite) continue;
    log10WaveformToGifRatios.add(
      math.log(waveformPeak / gifPeak.value) / math.ln10,
    );
  }
  if (log10WaveformToGifRatios.isEmpty) {
    return {
      'pairedFinitePeakStationCount': 0,
      'comparisonQuality': 'no_same_code_finite_pga_peaks',
    };
  }
  log10WaveformToGifRatios.sort();
  return {
    'pairedFinitePeakStationCount': log10WaveformToGifRatios.length,
    'log10OfficialWaveformToHistoricalGifPgaRatioMedian': _percentile(
      log10WaveformToGifRatios,
      0.50,
    ),
    'log10OfficialWaveformToHistoricalGifPgaRatioP25': _percentile(
      log10WaveformToGifRatios,
      0.25,
    ),
    'log10OfficialWaveformToHistoricalGifPgaRatioP75': _percentile(
      log10WaveformToGifRatios,
      0.75,
    ),
    // The waveform package and NIED monitor do not yet share a frozen common
    // filter/measurement contract. This comparison checks only whether the
    // independently decoded products remain plausibly related; it is not a
    // GIF colour calibration or an attenuation-model fit.
    'comparisonQuality':
        'same_station_peak_only_different_processing_not_calibration',
  };
}

double _percentile(List<double> sorted, double fraction) {
  if (sorted.isEmpty) throw ArgumentError.value(sorted, 'sorted');
  final index = (sorted.length - 1) * fraction;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  final weight = index - lower;
  return sorted[lower] * (1.0 - weight) + sorted[upper] * weight;
}

final List<_StationSample> _stationSamples = () {
  final byCode = <String, Map<String, Object?>>{
    for (final raw in NiedStationDb.stations)
      if (raw['code'] case final String code) code: raw,
  };
  final samples = <_StationSample>[];
  for (final entry in NiedScanPositions.points.entries) {
    final raw = byCode[entry.key];
    final latitude = raw?['lat'];
    final longitude = raw?['lng'];
    if (latitude is! num || longitude is! num) continue;
    samples.add(
      _StationSample(
        code: entry.key,
        coordinate: LatLng(latitude.toDouble(), longitude.toDouble()),
        network: raw?['network'] as String? ?? 'NIED',
        sample: entry.value,
      ),
    );
  }
  return List<_StationSample>.unmodifiable(samples);
}();

double? _colorPositionAt(_DecodedGif pixels, NiedScanPoint point) {
  final x = point.sampleX;
  final y = point.sampleY;
  if (x < 0 || x >= pixels.width || y < 0 || y >= pixels.height) return null;
  final rgb = pixels.packedRgb[y * pixels.width + x];
  // The historical frames use a different indexed GIF palette. Decode their
  // station colour through the common K-NET/KiK-net HSV scale instead of
  // matching against the current display palette. This follows Francois'
  // published piecewise colour-to-position interpolation, which was designed
  // for GIF/PNG source variations and keeps physical layers independent.
  return ShindoColorUtil.rgbaToPosition(
    (rgb >> 16) & 0xff,
    (rgb >> 8) & 0xff,
    rgb & 0xff,
  );
}

Future<_DecodedGif> _decodeGif(ArchiveFile entry) async {
  final bytes = Uint8List.fromList(entry.content as List<int>);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) throw StateError('Unable to decode ${entry.name}');
    final packedRgb = List<int>.filled(image.width * image.height, 0);
    for (var index = 0; index < packedRgb.length; index++) {
      final offset = index * 4;
      packedRgb[index] =
          (rgba.getUint8(offset) << 16) |
          (rgba.getUint8(offset + 1) << 8) |
          rgba.getUint8(offset + 2);
    }
    return _DecodedGif(
      width: image.width,
      height: image.height,
      packedRgb: packedRgb,
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

DateTime _gifTimeFromEntryName(String name) {
  final timestamp = name.split('/').last.split('_').first;
  return DateTime.utc(
    int.parse(timestamp.substring(0, 4)),
    int.parse(timestamp.substring(4, 6)),
    int.parse(timestamp.substring(6, 8)),
    int.parse(timestamp.substring(8, 10)),
    int.parse(timestamp.substring(10, 12)),
    int.parse(timestamp.substring(12, 14)),
  );
}

class _JmaSourceProcessModel {
  const _JmaSourceProcessModel({
    required this.jmaMagnitude,
    required this.momentMagnitude,
    required this.subfaultLengthKm,
    required this.subfaultWidthKm,
    required this.slipWeightedMeanDepthKm,
    required this.cells,
  });

  final double jmaMagnitude;
  final double momentMagnitude;
  final double subfaultLengthKm;
  final double subfaultWidthKm;
  final double slipWeightedMeanDepthKm;
  final List<_JmaFaultCell> cells;

  static Future<_JmaSourceProcessModel> fromZip(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final event = _readEntry(archive, '01event.txt');
    final fault = _readEntry(archive, '02fault.txt');
    final slip = _readEntry(archive, '04slip.txt');
    final jmaMagnitude = _doubleAfter(
      event,
      RegExp(r'^M=\s*([\d.]+)', multiLine: true),
    );
    final momentMagnitude = _doubleAfter(event, RegExp(r'\bMw=\s*([\d.]+)'));
    final sizeMatch = RegExp(
      r'^Dx=\s*([\d.]+)\s+Dw=\s*([\d.]+)',
      multiLine: true,
    ).firstMatch(fault);
    if (jmaMagnitude == null || momentMagnitude == null || sizeMatch == null) {
      throw FormatException('JMA source-process metadata is incomplete.');
    }
    final lengthKm = double.parse(sizeMatch.group(1)!);
    final widthKm = double.parse(sizeMatch.group(2)!);
    final cells = _parseFaultCells(fault);
    if (cells.isEmpty) {
      throw FormatException('JMA source-process has no cells.');
    }
    final slips = _parseSlips(slip);
    var totalWeight = 0.0;
    var weightedDepth = 0.0;
    for (final cell in cells) {
      final weight = slips['${cell.x}:${cell.w}'] ?? 0.0;
      if (weight <= 0) continue;
      totalWeight += weight;
      weightedDepth += cell.depthKm * weight;
    }
    final meanDepth = totalWeight > 0
        ? weightedDepth / totalWeight
        : cells.map((cell) => cell.depthKm).reduce((a, b) => a + b) /
              cells.length;
    return _JmaSourceProcessModel(
      jmaMagnitude: jmaMagnitude,
      momentMagnitude: momentMagnitude,
      subfaultLengthKm: lengthKm,
      subfaultWidthKm: widthKm,
      slipWeightedMeanDepthKm: meanDepth,
      cells: List.unmodifiable(cells),
    );
  }

  double distanceKmToFault(LatLng station) => cells
      .map(
        (cell) => cell.distanceKmToRectangle(
          station,
          lengthKm: subfaultLengthKm,
          widthKm: subfaultWidthKm,
        ),
      )
      .reduce(math.min);
}

String _readEntry(Archive archive, String suffix) {
  final entry = archive.files.firstWhere(
    (entry) =>
        entry.isFile &&
        (entry.name == suffix || entry.name.endsWith('/$suffix')),
    orElse: () => throw FormatException('Missing $suffix in JMA source ZIP.'),
  );
  return utf8.decode(entry.content as List<int>);
}

double? _doubleAfter(String text, RegExp expression) =>
    expression.firstMatch(text)?.group(1).let(double.tryParse);

List<_JmaFaultCell> _parseFaultCells(String text) {
  final cells = <_JmaFaultCell>[];
  for (final line in const LineSplitter().convert(text)) {
    final tokens = line.trim().split(RegExp(r'\s+'));
    if (tokens.length < 10) continue;
    final x = int.tryParse(tokens[0]);
    final w = int.tryParse(tokens[1]);
    final longitude = double.tryParse(tokens[2]);
    final latitude = double.tryParse(tokens[3]);
    final depthKm = double.tryParse(tokens[4]);
    final strike = double.tryParse(tokens[5]);
    final dip = double.tryParse(tokens[6]);
    if (x == null ||
        w == null ||
        longitude == null ||
        latitude == null ||
        depthKm == null ||
        strike == null ||
        dip == null) {
      continue;
    }
    cells.add(
      _JmaFaultCell(
        x: x,
        w: w,
        coordinate: LatLng(latitude, longitude),
        depthKm: depthKm,
        strikeDegrees: strike,
        dipDegrees: dip,
      ),
    );
  }
  return cells;
}

Map<String, double> _parseSlips(String text) {
  final slips = <String, double>{};
  for (final line in const LineSplitter().convert(text)) {
    final tokens = line.trim().split(RegExp(r'\s+'));
    if (tokens.length < 4) continue;
    final x = int.tryParse(tokens[0]);
    final w = int.tryParse(tokens[1]);
    final amount = double.tryParse(tokens[3]);
    if (x != null && w != null && amount != null && amount > 0) {
      slips['$x:$w'] = amount;
    }
  }
  return slips;
}

class _JmaFaultCell {
  const _JmaFaultCell({
    required this.x,
    required this.w,
    required this.coordinate,
    required this.depthKm,
    required this.strikeDegrees,
    required this.dipDegrees,
  });

  final int x;
  final int w;
  final LatLng coordinate;
  final double depthKm;
  final double strikeDegrees;
  final double dipDegrees;

  double distanceKmToRectangle(
    LatLng station, {
    required double lengthKm,
    required double widthKm,
  }) {
    final degreesToRadians = math.pi / 180.0;
    final latitudeRadians =
        (station.latitude + coordinate.latitude) / 2.0 * degreesToRadians;
    final northKm = (station.latitude - coordinate.latitude) * 110.574;
    final eastKm =
        (station.longitude - coordinate.longitude) *
        111.320 *
        math.cos(latitudeRadians);
    // ENU coordinates: the station is at U=0 and the subfault centre is
    // depthKm below it, so the centre-to-station U component is positive.
    final upKm = depthKm;
    final strikeRadians = strikeDegrees * degreesToRadians;
    final dipRadians = dipDegrees * degreesToRadians;
    final downDipAzimuth = strikeRadians + math.pi / 2.0;
    final strikeEast = math.sin(strikeRadians);
    final strikeNorth = math.cos(strikeRadians);
    final dipEast = math.sin(downDipAzimuth) * math.cos(dipRadians);
    final dipNorth = math.cos(downDipAzimuth) * math.cos(dipRadians);
    final dipUp = -math.sin(dipRadians);

    final alongStrike = eastKm * strikeEast + northKm * strikeNorth;
    final alongDip = eastKm * dipEast + northKm * dipNorth + upKm * dipUp;
    final nearestStrike = alongStrike.clamp(-lengthKm / 2.0, lengthKm / 2.0);
    final nearestDip = alongDip.clamp(-widthKm / 2.0, widthKm / 2.0);
    final closestEast = strikeEast * nearestStrike + dipEast * nearestDip;
    final closestNorth = strikeNorth * nearestStrike + dipNorth * nearestDip;
    final closestUp = dipUp * nearestDip;
    final eastResidual = eastKm - closestEast;
    final northResidual = northKm - closestNorth;
    final upResidual = upKm - closestUp;
    return math.sqrt(
      eastResidual * eastResidual +
          northResidual * northResidual +
          upResidual * upResidual,
    );
  }
}

class _StationSample {
  const _StationSample({
    required this.code,
    required this.coordinate,
    required this.network,
    required this.sample,
  });

  final String code;
  final LatLng coordinate;
  final String network;
  final NiedScanPoint sample;
}

class _HistoricalPgaPeak {
  const _HistoricalPgaPeak({
    required this.value,
    required this.colorPosition,
    required this.dataTime,
  });

  final double value;
  final double colorPosition;
  final DateTime dataTime;
}

class _OfficialWaveformStation {
  const _OfficialWaveformStation({
    required this.code,
    required this.coordinate,
    required this.network,
  });

  final String code;
  final LatLng coordinate;
  final String network;
}

class _OfficialWaveformPgaPeak {
  const _OfficialWaveformPgaPeak({required this.value, required this.dataTime});

  final double value;
  final DateTime dataTime;
}

class _DecodedGif {
  const _DecodedGif({
    required this.width,
    required this.height,
    required this.packedRgb,
  });

  final int width;
  final int height;
  final List<int> packedRgb;
}

extension on String? {
  T? let<T>(T? Function(String value) transform) {
    final value = this;
    return value == null ? null : transform(value);
  }
}
