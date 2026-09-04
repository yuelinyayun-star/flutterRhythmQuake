import 'dart:async';

import '../../models/source_status.dart';
import '../../models/unified_quake_data.dart';
import 'base_source.dart';

class GlobalQuakeService extends BaseSourceService {
  static final GlobalQuakeService _instance = GlobalQuakeService._internal();

  factory GlobalQuakeService() => _instance;

  GlobalQuakeService._internal();

  static const enabledPreferenceKey = 'global_quake_bridge_enabled';
  static const primaryHostPreferenceKey = 'global_quake_primary_host';
  static const primaryPortPreferenceKey = 'global_quake_primary_port';
  static const secondaryHostPreferenceKey = 'global_quake_secondary_host';
  static const secondaryPortPreferenceKey = 'global_quake_secondary_port';
  static const firstReportMagnitudeThresholdPreferenceKey =
      'global_quake_first_report_magnitude_threshold';
  static const defaultPrimaryHost = 'server.globalquake.net';
  static const defaultSecondaryHost = 'server-backup.globalquake.net';
  static const defaultPort = 38000;

  final _stateController = StreamController<void>.broadcast();

  @override
  String get name => 'GlobalQuake';

  @override
  bool get autoStart => false;

  Stream<void> get onDebugStateChanged => _stateController.stream;
  bool get isEnabled => false;
  SourceStatus get status => SourceStatus.disconnected;
  String? get lastError => 'GlobalQuake bridge is supported only on desktop.';
  String? get lastLog => null;
  UnifiedQuakeData? get lastEvent => null;
  int? get processId => null;
  String get localWsUrl => 'ws://127.0.0.1:4550';
  bool get isSupported => false;
  double get firstReportMagnitudeThreshold => 0;

  void configureServers({
    required String primaryHost,
    required int primaryPort,
    required String secondaryHost,
    required int secondaryPort,
  }) {}

  void configureFirstReportMagnitudeFilter(double threshold) {}

  @override
  void connect() {
    onStatusChanged?.call(SourceStatus.error);
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  @override
  void disconnect() {
    onStatusChanged?.call(SourceStatus.disconnected);
    if (!_stateController.isClosed) {
      _stateController.add(null);
    }
  }

  @override
  void dispose() {
    _stateController.close();
    super.dispose();
  }
}
