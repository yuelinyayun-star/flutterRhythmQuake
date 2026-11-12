part of 'palert_service.dart';

class PAlertPreparedSummary {
  const PAlertPreparedSummary(this.maximum);
  final PAlertStation? maximum;
}

/// Receives prepared display values only. HTTP, polling, original JSON parsing,
/// history, spatial detection, expiry and effect selection belong to Rust.
class _PAlertNativeRuntime {
  _PAlertNativeRuntime(this.owner);
  final PAlertService owner;
  NativeStationRuntime? _runtime;
  bool get active => _runtime != null;
  String signature = '', status = '', _detectionSignature = '';
  int frames = 0;
  String? error;
  List<NativeStationGrid> grids = const [];
  List<ObsStationInputSample> automation = const [];
  PAlertPreparedSummary? summary;
  List<PAlertStation> _catalogue = const [];
  List<SeismicActiveEvent> events = const [];

  void start() {
    final runtime = _runtime = NativeStationRuntime();
    runtime.onPreparedPAlert = (frame) {
      if (!identical(runtime, _runtime) || !owner._running) return;
      final nextStatus = frame[1] as String;
      final statusChanged = status != nextStatus;
      status = nextStatus;
      error = frame[2] as String?;
      owner._isConnected = status == 'connected';
      frames = frame[3] as int;
      signature = frame[8] as String;
      final catalogue = frame[9] as List?;
      if (catalogue != null) {
        _catalogue = [
          for (final row in catalogue)
            PAlertStation(
              id: row[0] as String,
              network: row[1] as String,
              name: row[2] as String,
              area: row[3] as String,
              coordinate: LatLng(row[4] as double, row[5] as double),
            ),
        ];
      }
      // Bind native presentation columns. No source decoding, threshold,
      // filtering, history, timing policy or maximum selection occurs here.
      final values = frame[10] as List<double>;
      final displayTimes = <int, DateTime>{};
      DateTime? date(double value) => value.isNaN
          ? null
          : displayTimes.putIfAbsent(
              value.toInt(),
              () => DateTime.fromMillisecondsSinceEpoch(
                value.toInt(),
                isUtc: true,
              ),
            );
      int? integer(double value) => value.isNaN ? null : value.toInt();
      owner._stations = [
        for (var i = 0; i < _catalogue.length; i++)
          PAlertStation(
            id: _catalogue[i].id,
            network: _catalogue[i].network,
            name: _catalogue[i].name,
            area: _catalogue[i].area,
            coordinate: _catalogue[i].coordinate,
            pgaGal: values[i * 10 + 9].toInt() & 1 == 0 ? null : values[i * 10],
            pgvCms: values[i * 10 + 9].toInt() & 2 == 0
                ? null
                : values[i * 10 + 1],
            cwaIntensityIndex: integer(values[i * 10 + 2]),
            heldCwaIntensityIndex: integer(values[i * 10 + 3]),
            heldLevel: integer(values[i * 10 + 4]),
            sampledLevel: integer(values[i * 10 + 5]) ?? -1,
            dataTime: date(values[i * 10 + 6]),
            receivedAt: date(values[i * 10 + 7]),
            preparedMapRecent: values[i * 10 + 8] != 0,
          ),
      ];
      final maximum = frame[11] as int;
      summary = PAlertPreparedSummary(
        maximum < 0 ? null : owner._stations[maximum],
      );
      final detection = frame[12] as List;
      final geometry = detection[7] as List<double>;
      final cells = <String, NiedDetectionGridCell>{};
      grids = [
        for (var p = 0; p < geometry.length; p += 12)
          NativeStationGrid(
            LatLng(geometry[p], geometry[p + 1]),
            geometry[p + 2].toInt(),
            [
              for (var q = p + 4; q < p + 12; q += 2)
                LatLng(geometry[q], geometry[q + 1]),
            ],
          ),
      ];
      for (var p = 0; p < geometry.length; p += 12) {
        final center = LatLng(geometry[p], geometry[p + 1]);
        cells['${center.latitude},${center.longitude}'] = NiedDetectionGridCell(
          center: center,
          level: geometry[p + 2].toInt(),
          shindo: geometry[p + 3],
        );
      }
      owner._workerDetection = ShakeDetectionSnapshot(
        stage: ShakeDetectStage.values.byName(detection[0] as String),
        weakCount: detection[1] as int,
        detectedCount: detection[2] as int,
        strongCount: detection[3] as int,
        maxShindo: detection[4] as int,
        gridCells: cells,
        detectedStations: [
          for (final row in detection[5] as List)
            DetectedStationEntry(
              code: _catalogue[row[0] as int].id,
              prefecture: _catalogue[row[0] as int].area,
              level: row[1] as int,
              jmaShindo: row[2] as int,
              detectState: row[3] as int,
              detectReason: 'kanameishi-chain',
            ),
        ],
      );
      final readyAutomation = frame[16] as List<int>;
      automation = [
        for (var p = 0; p < readyAutomation.length; p += 3)
          ObsStationInputSample(
            stationId: owner._stations[readyAutomation[p]].id,
            stationName: owner._stations[readyAutomation[p]].name,
            active: true,
            intensityLevel: readyAutomation[p + 1],
            intensity: readyAutomation[p + 1].toDouble(),
            latitude: owner._stations[readyAutomation[p]].coordinate.latitude,
            longitude: owner._stations[readyAutomation[p]].coordinate.longitude,
            observedAt: owner._stations[readyAutomation[p]].dataTime!,
            strong: readyAutomation[p + 2] != 0,
          ),
      ];
      owner.dataTimeNotifier.value = _date(frame[5]);
      owner.receivedTimeNotifier.value = _date(frame[6]);
      events = bindPAlertNativeSourceViews(frame[17] as List);
      owner.processingIsolateName = 'rust-palert-runtime';
      if (frame[14] == true) {
        StationHistoryCapture.instance.publish(
          'palert',
          () => runtime.archive!,
          originalJsonLoader: () => runtime.original,
          receivedAt: _date(frame[7]),
        );
      }
      final key = detection[6] as String;
      if (key != _detectionSignature) {
        _detectionSignature = key;
        owner.onDetectionChanged?.call(owner._workerDetection);
      }
      for (final signal in frame[13] as List<int>) {
        if (signal == -1) {
          owner.onShakeExpired?.call();
        } else {
          owner.onShakeDetected?.call(signal);
        }
      }
      if (statusChanged) owner.onStatusChanged?.call(owner._isConnected);
      owner._stationController.add(owner._stations);
    };
    final endpoint = owner._endpoint;
    runtime.start({
      'kind': 'palert',
      'nativeDisplay': true,
      'inference': owner._nativeInferenceEnabled,
      'sensitivity': owner._sensitivity,
      'pollMillis': owner._pollInterval.inMilliseconds,
      if (endpoint != null)
        'endpoint': {
          'host': endpoint.host,
          'path': endpoint.hasQuery
              ? '${endpoint.path}?${endpoint.query}'
              : endpoint.path,
          'port': endpoint.port,
          'secure': endpoint.scheme == 'https',
        },
      ...owner._nativeSettings,
    });
  }

  static DateTime? _date(dynamic v) => v == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: true);
  // Bind native diagnostic records for the existing inspection UI. Values and
  // keys are already final; this performs no source interpretation or formula.
  static Object? _displayValue(dynamic value) {
    if (value is! List) return value;
    if (value.length == 2 && value[0] == 'palert_display_map_v1') {
      final pairs = value[1] as List;
      return <String, Object?>{
        for (var i = 0; i < pairs.length; i += 2)
          pairs[i] as String: _displayValue(pairs[i + 1]),
      };
    }
    return [for (final entry in value) _displayValue(entry)];
  }

  Map<String, dynamic> history(bool includeOriginal) {
    final runtime = _runtime!;
    final snapshot = runtime.archive!;
    return includeOriginal
        ? {...snapshot, 'originalJson': runtime.original}
        : snapshot;
  }

  void setSensitivity(int value) => _runtime?.settings({'sensitivity': value});
  void setInferenceEnabled(bool value) =>
      _runtime?.settings({'inference': value});
  void inject(List<int> bytes, DateTime clock) =>
      _runtime!.injectOriginal(bytes, clock);
  void stop() {
    StationHistoryCapture.instance.clearLatest('palert');
    _runtime?.stop();
    _runtime = null;
    signature = '';
    status = '';
    _detectionSignature = '';
    frames = 0;
    grids = const [];
    automation = const [];
    summary = null;
    _catalogue = const [];
    events = const [];
    error = null;
  }
}

/// Binds final native source records to existing UI models.
List<SeismicActiveEvent> bindPAlertNativeSourceViews(List<dynamic> rows) => [
  for (final row in rows)
    SeismicActiveEvent(
      eventId: row[0] as String,
      sourceId: 'palert',
      startedAt: _PAlertNativeRuntime._date(row[1])!.toLocal(),
      updatedAt: _PAlertNativeRuntime._date(row[2])!,
      stageName: 'confirmed',
      maxShindo: -1,
      estimate: SourceEstimate(
        latitude: (row[3][0] as num).toDouble(),
        longitude: (row[3][1] as num).toDouble(),
        depthKm: (row[3][2] as num).toDouble(),
        magnitude: (row[4] as num?)?.toDouble(),
        originTime: _PAlertNativeRuntime._date(row[1])?.toLocal(),
        confidence: (row[5] as num).toDouble(),
        method: 'palert_hyp_v1',
        supportingStationCount: row[6] as int,
        diagnostics:
            _PAlertNativeRuntime._displayValue(row[7]) as Map<String, Object?>,
      ),
      metadata: {'palert_max_cwa_intensity_index': row[8]},
    ),
];
