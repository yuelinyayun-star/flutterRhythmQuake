import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../core/seedlink_station_style.dart';
import '../../core/seedlink_activity.dart';
import 'fdsn_source_catalog.dart';
import 'fdsn_source_status.dart';

class FdsnMotionSample {
  final String source;
  final String network;
  final String station;
  final String channel;
  final double? pga;
  final double? pgv;
  final double? intensity;
  final bool active;
  final SeedLinkSensorType sensorType;
  final SeedLinkActivity? activity;
  final DateTime timestamp;

  const FdsnMotionSample({
    required this.source,
    required this.network,
    required this.station,
    required this.channel,
    required this.timestamp,
    this.pga,
    this.pgv,
    this.intensity,
    this.active = false,
    this.sensorType = SeedLinkSensorType.unknown,
    this.activity,
  });

  String get code => '$network.$station';
  bool get hasMeasurement => pga != null || pgv != null || intensity != null;
}

class FdsnMotionService {
  static final FdsnMotionService _instance = FdsnMotionService._();
  factory FdsnMotionService() => _instance;
  FdsnMotionService._();

  static const int defaultStationLimit = 300;
  static const String stationLimitPreferenceKey = 'fdsn_station_limit';
  static const List<int> stationLimitOptions = [
    100,
    300,
    500,
    1000,
    2000,
    3000,
    4000,
    5000,
  ];

  static int normalizeStationLimit(int value) {
    if (stationLimitOptions.contains(value)) return value;
    return stationLimitOptions.reduce(
      (a, b) => (value - a).abs() <= (value - b).abs() ? a : b,
    );
  }

  static int get defaultStreamCount =>
      FdsnMotionService().targetStationLimitNotifier.value;

  final _controller = StreamController<FdsnMotionSample>.broadcast();
  Stream<FdsnMotionSample> get sampleStream => _controller.stream;
  final ValueNotifier<int> linkedStationCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> targetStationLimitNotifier = ValueNotifier<int>(
    defaultStationLimit,
  );
  final ValueNotifier<DateTime?> dataTimeNotifier = ValueNotifier(null);
  final sourceStatusesNotifier = ValueNotifier<List<FdsnSourceStatus>>(const []);

  void acceptSourceStatuses(List<FdsnSourceStatus> statuses) {
    if (!listEquals(sourceStatusesNotifier.value, statuses)) {
      sourceStatusesNotifier.value = List.unmodifiable(statuses);
    }
  }

  void Function(bool connected)? onStatusChanged;

  void recordDataTime(DateTime timestamp) {
    if (timestamp.isAfter(DateTime.now().toUtc())) return;
    final previous = dataTimeNotifier.value;
    if (previous == null || timestamp.isAfter(previous)) {
      dataTimeNotifier.value = timestamp;
    }
  }

  void connect({
    int stationLimit = defaultStationLimit,
    Set<String> enabledSources = FdsnSourceCatalog.names,
  }) {
    final normalizedLimit = normalizeStationLimit(stationLimit);
    if (targetStationLimitNotifier.value != normalizedLimit) {
      targetStationLimitNotifier.value = normalizedLimit;
    }
    linkedStationCountNotifier.value = 0;
    dataTimeNotifier.value = null;
    onStatusChanged?.call(false);
  }

  void disconnect({bool clearSourceStatuses = true}) {
    if (clearSourceStatuses) acceptSourceStatuses(const []);
    linkedStationCountNotifier.value = 0;
    dataTimeNotifier.value = null;
    onStatusChanged?.call(false);
  }

  void dispose() {
    linkedStationCountNotifier.dispose();
    targetStationLimitNotifier.dispose();
    dataTimeNotifier.dispose();
    sourceStatusesNotifier.dispose();
    _controller.close();
  }
}
