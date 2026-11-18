import 'package:flutter/foundation.dart';

import '../../models/source_status.dart';
import '../../models/unified_quake_data.dart';
import 'base_source.dart';
import 'kma_pews_feed.dart';
import 'native_station_runtime.dart';

/// The runtime owns ingress, binary decoding, revisions and raw payloads.
class KmaPewsEewService extends BaseSourceService {
  KmaPewsEewService({KmaPewsFeed? feed}) : _feed = feed ?? KmaPewsFeed.instance;

  static const sourceName = 'KMA-PEWS';
  static const enabledPreferenceKey = 'api_source_kma_pews_eew_enabled';
  static bool get supported => NativeStationRuntime.supported;
  final KmaPewsFeed _feed;
  bool _running = false;
  SourceStatus _status = SourceStatus.disconnected;

  void _updateStatus(SourceStatus status) {
    if (_status == status) return;
    _status = status;
    onStatusChanged?.call(status);
  }

  @override
  String get name => sourceName;

  @override
  void connect() {
    if (_running) return;
    if (!NativeStationRuntime.supported) {
      _updateStatus(SourceStatus.error);
      return;
    }
    _running = true;
    _updateStatus(SourceStatus.connecting);
    try {
      _feed.attach(this, _receive);
    } catch (error) {
      _running = false;
      debugPrint('KMA-PEWS startup failed: $error');
      _updateStatus(SourceStatus.error);
    }
  }

  void _receive(Map<String, dynamic> frame) {
    if (!_running) return;
    _updateStatus(SourceStatus.values.byName(frame['status'] as String));
    for (final event in frame['eewEvents'] as List) {
      emitUnified(
        UnifiedQuakeData.fromMap(Map<String, dynamic>.from(event as Map)),
      );
    }
  }

  @override
  void disconnect() {
    _running = false;
    _feed.detach(this);
    _updateStatus(SourceStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

class RhythmKmaEewService extends BaseSourceService {
  static const sourceName = 'Rhythm KMA';
  static const enabledPreferenceKey = 'api_source_rhythm_kma_eew_enabled';
  NativeStationRuntime? _runtime;
  SourceStatus _status = SourceStatus.disconnected;

  void _updateStatus(SourceStatus status) {
    if (_status == status) return;
    _status = status;
    onStatusChanged?.call(status);
  }

  @override
  String get name => sourceName;

  @override
  void connect() {
    if (_runtime != null) return;
    if (!NativeStationRuntime.supported) {
      _updateStatus(SourceStatus.error);
      return;
    }
    _updateStatus(SourceStatus.connecting);
    final runtime = _runtime = NativeStationRuntime();
    runtime.onFrame = (frame) {
      if (!identical(runtime, _runtime)) return;
      _updateStatus(SourceStatus.values.byName(frame['status'] as String));
      for (final event in frame['eewEvents'] as List) {
        emitUnified(
          UnifiedQuakeData.fromMap(Map<String, dynamic>.from(event as Map)),
        );
      }
    };
    try {
      runtime.start({'kind': 'kma_eew', 'source': 'rhythm'});
    } catch (error) {
      runtime.stop();
      _runtime = null;
      debugPrint('Rhythm KMA startup failed: $error');
      _updateStatus(SourceStatus.error);
    }
  }

  @override
  void disconnect() {
    _runtime?.stop();
    _runtime = null;
    _updateStatus(SourceStatus.disconnected);
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
