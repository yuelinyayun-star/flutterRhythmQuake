import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

const knetWaveformParserVersion = 'knet_waveform_archive_v1';

enum KnetWaveformFormat { ascii, csv }

enum KnetNetwork { knet, kikNet, unknown }

enum KnetSensorRole { surface, borehole, unknown }

class KnetWaveformArchiveParser {
  const KnetWaveformArchiveParser();

  List<KnetWaveformChannel> parseZipBytes(
    List<int> bytes, {
    String? sourcePath,
  }) {
    final archive = ZipDecoder().decodeBytes(Uint8List.fromList(bytes));
    final channels = <KnetWaveformChannel>[];

    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\', '/');
      final lower = name.toLowerCase();
      final contentBytes = entry.content as List<int>;
      final text = utf8.decode(contentBytes, allowMalformed: true);

      if (_isAsciiName(lower)) {
        channels.add(
          parseAscii(
            text,
            sourcePath: sourcePath == null ? name : '$sourcePath:$name',
          ),
        );
      } else if (_isCsvName(lower)) {
        channels.addAll(
          parseCsv(
            text,
            sourcePath: sourcePath == null ? name : '$sourcePath:$name',
          ),
        );
      }
    }

    return channels;
  }

  KnetWaveformChannel parseAscii(String content, {String? sourcePath}) {
    final lines = const LineSplitter().convert(content.trimRight());
    if (lines.length < 18) {
      throw const FormatException('K-NET ASCII requires 17 header lines');
    }

    final header = <String, String>{};
    for (var index = 0; index < 17; index++) {
      final line = lines[index];
      final split = _splitAsciiHeaderLine(line);
      header[split.$1] = split.$2;
    }

    final scaleFactor = _parseScaleFactor(_required(header, 'Scale Factor'));
    final samplingHz = _parseSamplingHz(_required(header, 'Sampling Freq(Hz)'));
    final recordTimeUtc = _parseJst(_required(header, 'Record Time'));
    final sampleStartTimeUtc = recordTimeUtc.subtract(
      const Duration(seconds: 15),
    );
    final samples = _parseAsciiSamples(lines.skip(17));
    final accelerationGal = samples
        .map((value) => value * scaleFactor)
        .toList(growable: false);
    final extension = _fileExtension(sourcePath);
    final direction = _normaliseDirection(header['Dir.']);
    final component = _componentFromToken(extension ?? direction);
    final sensorRole = _roleFromToken(extension ?? direction);
    final network = _networkFromRoleAndExtension(sensorRole, extension);

    return KnetWaveformChannel(
      sourcePath: sourcePath,
      format: KnetWaveformFormat.ascii,
      network: network,
      stationCode: _required(header, 'Station Code'),
      stationLatitude: _parseDouble(_required(header, 'Station Lat.')),
      stationLongitude: _parseDouble(
        header['Station Long.'] ?? header['Station Lon.'] ?? '',
      ),
      stationHeightMeters: _parseNullableDouble(header['Station Height(m)']),
      eventOriginTimeUtc: _parseJst(_required(header, 'Origin Time')),
      eventLatitude: _parseNullableDouble(header['Lat.']),
      eventLongitude: _parseNullableDouble(header['Long.'] ?? header['Lon.']),
      eventDepthKm: _parseNullableDouble(header['Depth. (km)']),
      eventMagnitude: _parseNullableDouble(header['Mag.']),
      recordTimeUtc: recordTimeUtc,
      sampleStartTimeUtc: sampleStartTimeUtc,
      samplingHz: samplingHz,
      durationSeconds: _parseNullableDouble(header['Duration Time(s)']),
      component: component,
      sensorRole: sensorRole,
      scaleFactor: scaleFactor,
      headerMaxAccelerationGal: _parseNullableDouble(
        header['Max. Acc. (gal)'] ?? header['Max Acc. (gal)'],
      ),
      lastCorrectionUtc: _parseOptionalJst(header['Last Correction']),
      memo: header['Memo.'],
      digitValues: samples,
      accelerationGal: accelerationGal,
      offsetGal: _mean(accelerationGal),
      dataPrecision: 'raw_digit_scale_factor',
      processingVersion: knetWaveformParserVersion,
    );
  }

  List<KnetWaveformChannel> parseCsv(String content, {String? sourcePath}) {
    final rawLines = const LineSplitter()
        .convert(content.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (rawLines.isEmpty || rawLines.first.trim() != '#K-NET CSV') {
      throw const FormatException('K-NET CSV header not found');
    }

    final metadata = _parseCsvMetadata(rawLines);
    final columns = metadata.columns;
    if (columns.length < 5 ||
        columns[0] != 'Time' ||
        columns[1] != 'RelativeTime(s)') {
      throw const FormatException('K-NET CSV data header not found');
    }

    final dataRows = rawLines
        .where((line) => !line.startsWith('#'))
        .map(_splitCsv)
        .toList(growable: false);
    if (dataRows.isEmpty) {
      throw const FormatException('K-NET CSV contains no waveform rows');
    }

    final firstTimeUtc = _parseJst(dataRows.first[0]);
    final channelLabels = columns.skip(2).toList(growable: false);
    final channelValues = List.generate(
      channelLabels.length,
      (_) => <double>[],
      growable: false,
    );

    for (final row in dataRows) {
      if (row.length < columns.length) {
        throw FormatException(
          'CSV row has ${row.length} columns, expected ${columns.length}',
        );
      }
      for (var index = 0; index < channelLabels.length; index++) {
        channelValues[index].add(_parseDouble(row[index + 2]));
      }
    }

    final channels = <KnetWaveformChannel>[];
    for (var index = 0; index < channelLabels.length; index++) {
      final label = channelLabels[index];
      final component = _componentFromCsvLabel(label, index);
      final role = _roleFromCsvLabel(label, channelLabels.length, index);
      channels.add(
        KnetWaveformChannel(
          sourcePath: sourcePath,
          format: KnetWaveformFormat.csv,
          network: channelLabels.length >= 6
              ? KnetNetwork.kikNet
              : KnetNetwork.knet,
          stationCode: metadata.stationCode,
          stationLatitude: metadata.stationLatitude,
          stationLongitude: metadata.stationLongitude,
          stationHeightMeters: role == KnetSensorRole.borehole
              ? metadata.height1Meters
              : metadata.height2Meters ?? metadata.height1Meters,
          eventOriginTimeUtc: metadata.originTimeUtc,
          eventLatitude: metadata.eventLatitude,
          eventLongitude: metadata.eventLongitude,
          eventDepthKm: metadata.eventDepthKm,
          eventMagnitude: metadata.eventMagnitude,
          recordTimeUtc: firstTimeUtc,
          sampleStartTimeUtc: firstTimeUtc,
          samplingHz: metadata.samplingHz,
          durationSeconds: metadata.durationSeconds,
          component: component,
          sensorRole: role,
          scaleFactor: null,
          headerMaxAccelerationGal: null,
          lastCorrectionUtc: null,
          memo: null,
          digitValues: null,
          accelerationGal: List<double>.unmodifiable(channelValues[index]),
          offsetGal: index < metadata.offsetsGal.length
              ? metadata.offsetsGal[index]
              : _mean(channelValues[index]),
          dataPrecision: 'csv_physical_gal_0.01',
          processingVersion: knetWaveformParserVersion,
        ),
      );
    }
    return channels;
  }

  static bool _isAsciiName(String lower) =>
      RegExp(r'\.(ns|ew|ud|ns1|ew1|ud1|ns2|ew2|ud2)$').hasMatch(lower);

  static bool _isCsvName(String lower) => lower.endsWith('.csv');
}

class KnetWaveformChannel {
  const KnetWaveformChannel({
    required this.sourcePath,
    required this.format,
    required this.network,
    required this.stationCode,
    required this.stationLatitude,
    required this.stationLongitude,
    required this.stationHeightMeters,
    required this.eventOriginTimeUtc,
    required this.eventLatitude,
    required this.eventLongitude,
    required this.eventDepthKm,
    required this.eventMagnitude,
    required this.recordTimeUtc,
    required this.sampleStartTimeUtc,
    required this.samplingHz,
    required this.durationSeconds,
    required this.component,
    required this.sensorRole,
    required this.scaleFactor,
    required this.headerMaxAccelerationGal,
    required this.lastCorrectionUtc,
    required this.memo,
    required this.digitValues,
    required this.accelerationGal,
    required this.offsetGal,
    required this.dataPrecision,
    required this.processingVersion,
  });

  final String? sourcePath;
  final KnetWaveformFormat format;
  final KnetNetwork network;
  final String stationCode;
  final double stationLatitude;
  final double stationLongitude;
  final double? stationHeightMeters;
  final DateTime eventOriginTimeUtc;
  final double? eventLatitude;
  final double? eventLongitude;
  final double? eventDepthKm;
  final double? eventMagnitude;
  final DateTime recordTimeUtc;
  final DateTime sampleStartTimeUtc;
  final double samplingHz;
  final double? durationSeconds;
  final String component;
  final KnetSensorRole sensorRole;
  final double? scaleFactor;
  final double? headerMaxAccelerationGal;
  final DateTime? lastCorrectionUtc;
  final String? memo;
  final List<int>? digitValues;
  final List<double> accelerationGal;
  final double offsetGal;
  final String dataPrecision;
  final String processingVersion;

  int get sampleCount => accelerationGal.length;

  double get sampleIntervalSeconds => 1.0 / samplingHz;

  double get peakAbsoluteAccelerationGal =>
      accelerationGal.fold(0, (peak, value) => math.max(peak, value.abs()));

  double get offsetCorrectedPeakAccelerationGal => accelerationGal.fold(
    0,
    (peak, value) => math.max(peak, (value - offsetGal).abs()),
  );

  Map<String, Object?> toJson({bool includeSamples = false}) {
    return {
      'sourcePath': sourcePath,
      'format': format.name,
      'network': network.name,
      'stationCode': stationCode,
      'stationLatitude': stationLatitude,
      'stationLongitude': stationLongitude,
      'stationHeightMeters': stationHeightMeters,
      'eventOriginTimeUtc': eventOriginTimeUtc.toIso8601String(),
      'eventLatitude': eventLatitude,
      'eventLongitude': eventLongitude,
      'eventDepthKm': eventDepthKm,
      'eventMagnitude': eventMagnitude,
      'recordTimeUtc': recordTimeUtc.toIso8601String(),
      'sampleStartTimeUtc': sampleStartTimeUtc.toIso8601String(),
      'samplingHz': samplingHz,
      'durationSeconds': durationSeconds,
      'component': component,
      'sensorRole': sensorRole.name,
      'scaleFactor': scaleFactor,
      'headerMaxAccelerationGal': headerMaxAccelerationGal,
      'lastCorrectionUtc': lastCorrectionUtc?.toIso8601String(),
      'sampleCount': sampleCount,
      'offsetGal': offsetGal,
      'peakAbsoluteAccelerationGal': peakAbsoluteAccelerationGal,
      'offsetCorrectedPeakAccelerationGal': offsetCorrectedPeakAccelerationGal,
      'dataPrecision': dataPrecision,
      'processingVersion': processingVersion,
      if (includeSamples) 'digitValues': digitValues,
      if (includeSamples) 'accelerationGal': accelerationGal,
    };
  }
}

class _CsvMetadata {
  const _CsvMetadata({
    required this.originTimeUtc,
    required this.eventLatitude,
    required this.eventLongitude,
    required this.eventDepthKm,
    required this.eventMagnitude,
    required this.stationCode,
    required this.stationLatitude,
    required this.stationLongitude,
    required this.height1Meters,
    required this.height2Meters,
    required this.samplingHz,
    required this.durationSeconds,
    required this.offsetsGal,
    required this.columns,
  });

  final DateTime originTimeUtc;
  final double? eventLatitude;
  final double? eventLongitude;
  final double? eventDepthKm;
  final double? eventMagnitude;
  final String stationCode;
  final double stationLatitude;
  final double stationLongitude;
  final double? height1Meters;
  final double? height2Meters;
  final double samplingHz;
  final double? durationSeconds;
  final List<double> offsetsGal;
  final List<String> columns;
}

_CsvMetadata _parseCsvMetadata(List<String> lines) {
  List<String>? event;
  List<String>? station;
  double? samplingHz;
  double? durationSeconds;
  List<double>? offsets;
  List<String>? columns;

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (!line.startsWith('#')) continue;
    final value = line.substring(1);
    if (value == 'OriginTime,Latitude,Longitude,Depth(km),Magnitude') {
      event = _splitCsv(lines[++index].substring(1));
    } else if (value.startsWith('Code,Latitude,Longitude')) {
      station = _splitCsv(lines[++index].substring(1));
    } else if (value == 'SamplingFrequency(Hz)') {
      samplingHz = _parseDouble(lines[++index].substring(1));
    } else if (value == 'DurationTime(s)') {
      durationSeconds = _parseDouble(lines[++index].substring(1));
    } else if (value == 'Offset') {
      index++;
      if (index + 1 >= lines.length) {
        throw const FormatException('K-NET CSV offset values not found');
      }
      offsets = _splitCsv(
        lines[++index].substring(1),
      ).map(_parseDouble).toList(growable: false);
    } else if (value.startsWith('Time,RelativeTime(s),')) {
      columns = _splitCsv(
        value,
      ).map(_normaliseCsvColumn).toList(growable: false);
    }
  }

  if (event == null || event.length < 5) {
    throw const FormatException('K-NET CSV event metadata not found');
  }
  if (station == null || station.length < 4) {
    throw const FormatException('K-NET CSV station metadata not found');
  }
  if (samplingHz == null || columns == null) {
    throw const FormatException('K-NET CSV record metadata not found');
  }

  return _CsvMetadata(
    originTimeUtc: _parseJst(event[0]),
    eventLatitude: _parseNullableDouble(event[1]),
    eventLongitude: _parseNullableDouble(event[2]),
    eventDepthKm: _parseNullableDouble(event[3]),
    eventMagnitude: _parseNullableDouble(event[4]),
    stationCode: station[0],
    stationLatitude: _parseDouble(station[1]),
    stationLongitude: _parseDouble(station[2]),
    height1Meters: _parseNullableDouble(station[3]),
    height2Meters: station.length >= 5
        ? _parseNullableDouble(station[4])
        : null,
    samplingHz: samplingHz,
    durationSeconds: durationSeconds,
    offsetsGal: offsets ?? const [],
    columns: columns,
  );
}

(String, String) _splitAsciiHeaderLine(String line) {
  for (final key in _asciiHeaderKeys) {
    if (line.startsWith(key)) {
      return (key, line.substring(key.length).trim());
    }
  }
  final match = RegExp(r'^(.*?)\s{2,}(.+?)\s*$').firstMatch(line);
  if (match == null) {
    return (line.trim(), '');
  }
  return (match.group(1)!.trim(), match.group(2)!.trim());
}

const _asciiHeaderKeys = [
  'Station Height(m)',
  'Sampling Freq(Hz)',
  'Duration Time(s)',
  'Max. Acc. (gal)',
  'Max Acc. (gal)',
  'Last Correction',
  'Station Code',
  'Station Long.',
  'Station Lon.',
  'Station Lat.',
  'Depth. (km)',
  'Scale Factor',
  'Origin Time',
  'Record Time',
  'Long.',
  'Lon.',
  'Lat.',
  'Mag.',
  'Dir.',
  'Memo.',
];

String _required(Map<String, String> header, String key) {
  final value = header[key];
  if (value == null || value.trim().isEmpty) {
    throw FormatException('Required K-NET header "$key" not found');
  }
  return value.trim();
}

double _parseDouble(String value) => double.parse(value.trim());

double? _parseNullableDouble(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

double _parseScaleFactor(String value) {
  final match = RegExp(
    r'(-?\d+(?:\.\d+)?)\s*\(gal\)\s*/\s*(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) {
    throw FormatException('Invalid K-NET scale factor: $value');
  }
  return double.parse(match.group(1)!) / double.parse(match.group(2)!);
}

double _parseSamplingHz(String value) {
  final match = RegExp(r'(-?\d+(?:\.\d+)?)').firstMatch(value);
  if (match == null) {
    throw FormatException('Invalid sampling frequency: $value');
  }
  return double.parse(match.group(1)!);
}

List<int> _parseAsciiSamples(Iterable<String> lines) {
  final values = <int>[];
  for (final line in lines) {
    for (final match in RegExp(r'[+-]?\d+').allMatches(line)) {
      values.add(int.parse(match.group(0)!));
    }
  }
  if (values.isEmpty) {
    throw const FormatException('K-NET ASCII contains no waveform samples');
  }
  return List<int>.unmodifiable(values);
}

DateTime? _parseOptionalJst(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return _parseJst(value);
}

DateTime _parseJst(String value) {
  final match = RegExp(
    r'^(\d{4})/(\d{1,2})/(\d{1,2})[ -](\d{1,2}):(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?$',
  ).firstMatch(value.trim());
  if (match == null) throw FormatException('Invalid JST datetime: $value');
  final millisecondsText = (match.group(7) ?? '').padRight(3, '0');
  final jstAsUtc = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
    millisecondsText.isEmpty ? 0 : int.parse(millisecondsText),
  );
  return jstAsUtc.subtract(const Duration(hours: 9));
}

String? _fileExtension(String? sourcePath) {
  if (sourcePath == null) return null;
  final name = sourcePath.split('/').last.split('\\').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toUpperCase();
}

String _normaliseDirection(String? value) =>
    (value ?? '').toUpperCase().replaceAll('-', '').replaceAll(' ', '');

String _componentFromToken(String? token) {
  final upper = (token ?? '').toUpperCase().replaceAll('-', '');
  if (upper.startsWith('NS') ||
      upper == 'NS' ||
      upper == 'NS1' ||
      upper == 'NS2') {
    return 'NS';
  }
  if (upper.startsWith('EW') ||
      upper == 'EW' ||
      upper == 'EW1' ||
      upper == 'EW2') {
    return 'EW';
  }
  if (upper.startsWith('UD') ||
      upper == 'UD' ||
      upper == 'UD1' ||
      upper == 'UD2') {
    return 'UD';
  }
  return upper.isEmpty ? 'unknown' : upper;
}

KnetSensorRole _roleFromToken(String? token) {
  final upper = (token ?? '').toUpperCase();
  if (upper.endsWith('1')) return KnetSensorRole.borehole;
  if (upper.endsWith('2')) return KnetSensorRole.surface;
  if (upper == 'NS' || upper == 'EW' || upper == 'UD') {
    return KnetSensorRole.surface;
  }
  return KnetSensorRole.unknown;
}

KnetNetwork _networkFromRoleAndExtension(
  KnetSensorRole role,
  String? extension,
) {
  if (extension == null) return KnetNetwork.unknown;
  if (RegExp(r'[12]$').hasMatch(extension)) return KnetNetwork.kikNet;
  if (role == KnetSensorRole.surface) return KnetNetwork.knet;
  return KnetNetwork.unknown;
}

String _componentFromCsvLabel(String label, int index) {
  final upper = label.toUpperCase();
  if (upper.startsWith('NS') || upper == '1' || upper == '4') return 'NS';
  if (upper.startsWith('EW') || upper == '2' || upper == '5') return 'EW';
  if (upper.startsWith('UD') || upper == '3' || upper == '6') return 'UD';
  return switch (index % 3) {
    0 => 'NS',
    1 => 'EW',
    _ => 'UD',
  };
}

KnetSensorRole _roleFromCsvLabel(String label, int channelCount, int index) {
  final upper = label.toUpperCase();
  if (upper.endsWith('1') || upper == '1' || upper == '2' || upper == '3') {
    return KnetSensorRole.borehole;
  }
  if (upper.endsWith('2') || upper == '4' || upper == '5' || upper == '6') {
    return KnetSensorRole.surface;
  }
  if (channelCount == 3) return KnetSensorRole.surface;
  return index < 3 ? KnetSensorRole.borehole : KnetSensorRole.surface;
}

String _normaliseCsvColumn(String value) {
  final trimmed = value.trim();
  return trimmed.replaceAll(RegExp(r'\(gal\)$'), '').replaceAll('-', '');
}

List<String> _splitCsv(String line) =>
    line.split(',').map((v) => v.trim()).toList();

double _mean(List<double> values) {
  if (values.isEmpty) return 0;
  return values.reduce((a, b) => a + b) / values.length;
}
