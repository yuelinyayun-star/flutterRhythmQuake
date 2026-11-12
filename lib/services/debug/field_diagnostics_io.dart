import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../widgets/ui/map_backdrop_cache.dart';
import '../sources/native_station_core_library_io.dart';

/// Persistent field log for cloud/field builds.
///
/// Enabled only by `--dart-define=RQ_FIELD_LOG=true`; the normal build never
/// starts it. Lines go through the Rust writer (`rq_field_log_*`), which keeps
/// 4 x 5 MB rolling segments and flushes every line.
///
/// A one second heartbeat records how many frames the UI thread produced
/// (`built`) against how many the raster thread completed (`raster`), so a
/// frozen picture with a live isolate shows up as `STALL raster_no_completion`.
/// A gap in heartbeats while the process is alive marks a blocked UI isolate.
// Diagnostic output: print is intentional so a failed start is visible.
// ignore_for_file: avoid_print
class FieldDiagnostics {
  FieldDiagnostics._();

  static const bool enabled = bool.fromEnvironment('RQ_FIELD_LOG');

  static bool _active = false;
  static late final int Function(Pointer<Uint8>, int) _write;
  static late final int Function() _lost;
  static late final int Function() _errors;
  static final Stopwatch _clock = Stopwatch();
  // Held so the periodic heartbeat stays referenced for the process lifetime.
  // ignore: unused_field
  static Timer? _heartbeat;
  static int _sequence = 0;
  static int _built = 0;
  static int _rasterDone = 0;
  static int _lastBuilt = 0;
  static int _lastRasterDone = 0;
  static int _buildMaxMicros = 0;
  static int _rasterMaxMicros = 0;
  static int _totalMaxMicros = 0;
  static int _stallSeconds = 0;
  static int _lastTickMillis = 0;
  static final _observer = _LifecycleObserver();

  static Future<void> start() async {
    if (!enabled || _active) return;
    if (!(Platform.isWindows || Platform.isAndroid)) return;
    if (!StationCoreLibrary.supported) return;
    try {
      final directory = await _directory();
      final library = StationCoreLibrary.library;
      final start = library
          .lookupFunction<
            Uint32 Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)
          >('rq_field_log_start');
      _write = library
          .lookupFunction<
            Uint32 Function(Pointer<Uint8>, UintPtr),
            int Function(Pointer<Uint8>, int)
          >('rq_field_log_write');
      _lost = library.lookupFunction<Uint64 Function(), int Function()>(
        'rq_field_log_lost',
      );
      _errors = library.lookupFunction<Uint64 Function(), int Function()>(
        'rq_field_log_errors',
      );
      final path = '${directory.path}/field.log';
      final ok = using(
        (arena) => start(path.toNativeUtf8(allocator: arena).cast()),
      );
      if (ok != 1) {
        print('[RQField] native log writer did not start: $path');
        return;
      }
      _active = true;
    } catch (error, stack) {
      print('[RQField] start failed: $error\n$stack');
      return;
    }
    _clock.start();
    _lastTickMillis = 0;
    event('session_start', {
      'pid': pid,
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'executable': Platform.resolvedExecutable,
      'releaseMode': kReleaseMode,
    });
    final binding = SchedulerBinding.instance;
    binding.addPersistentFrameCallback((_) => _built++);
    binding.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addObserver(_observer);
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Writes one JSON line; a no-op when the log is not active.
  static void event(String name, [Map<String, Object?>? fields]) {
    if (!_active) return;
    final line = jsonEncode({
      't': DateTime.now().toIso8601String(),
      'up': _clock.elapsedMilliseconds,
      'ev': name,
      if (fields != null) ...fields,
    }, toEncodable: (object) => object.toString());
    final bytes = utf8.encode(line);
    final length = math.min(bytes.length, 60000);
    final pointer = malloc.allocate<Uint8>(length);
    try {
      pointer.asTypedList(length).setAll(0, bytes.getRange(0, length));
      _write(pointer, length);
    } finally {
      malloc.free(pointer);
    }
  }

  static Future<Directory> _directory() async {
    final Directory directory;
    final local = Platform.environment['LOCALAPPDATA'];
    if (Platform.isWindows && local != null) {
      directory = Directory('$local/RhythmQuake/field_logs');
    } else {
      final support = await getApplicationSupportDirectory();
      directory = Directory('${support.path}/field_logs');
    }
    return directory.create(recursive: true);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _rasterDone++;
      _buildMaxMicros = math.max(
        _buildMaxMicros,
        timing.buildDuration.inMicroseconds,
      );
      _rasterMaxMicros = math.max(
        _rasterMaxMicros,
        timing.rasterDuration.inMicroseconds,
      );
      _totalMaxMicros = math.max(
        _totalMaxMicros,
        timing.totalSpan.inMicroseconds,
      );
    }
  }

  static void _tick() {
    final now = _clock.elapsedMilliseconds;
    final lateMs = now - _lastTickMillis - 1000;
    _lastTickMillis = now;
    final built = _built - _lastBuilt;
    final raster = _rasterDone - _lastRasterDone;
    _lastBuilt = _built;
    _lastRasterDone = _rasterDone;
    final scheduled = SchedulerBinding.instance.hasScheduledFrame;
    event('hb', {
      'seq': _sequence++,
      'built': built,
      'raster': raster,
      'buildMaxMs': _ms(_buildMaxMicros),
      'rasterMaxMs': _ms(_rasterMaxMicros),
      'totalMaxMs': _ms(_totalMaxMicros),
      'scheduled': scheduled,
      'rssMB': (ProcessInfo.currentRss / 1048576).round(),
      'lost': _lost(),
      'writeErrors': _errors(),
      if (lateMs > 500) 'timerLateMs': lateMs,
    });
    _buildMaxMicros = 0;
    _rasterMaxMicros = 0;
    _totalMaxMicros = 0;
    if (lateMs > 2000) {
      event('STALL', {'kind': 'ui_timer_late', 'lateMs': lateMs});
    }
    // The UI thread kept building frames but the raster thread completed none.
    if (built > 0 && raster == 0) {
      _stallSeconds++;
      if (_stallSeconds >= 3 && _stallSeconds % 5 == 3) {
        event('STALL', {
          'kind': 'raster_no_completion',
          'seconds': _stallSeconds,
          'built': built,
          'backdropCache': MapBackdropCacheHost.diagnostics,
        });
      }
    } else if (raster > 0) {
      if (_stallSeconds >= 3) {
        event('stall_end', {'seconds': _stallSeconds});
      }
      _stallSeconds = 0;
    }
    if (_sequence % 10 == 0) {
      event('backdrop_cache', {'state': MapBackdropCacheHost.diagnostics});
    }
  }

  static double _ms(int micros) => (micros / 100).round() / 10;
}

class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    FieldDiagnostics.event('lifecycle', {'state': state.name});
  }

  @override
  void didChangeMetrics() {
    final view = ui.PlatformDispatcher.instance.views.firstOrNull;
    if (view == null) return;
    FieldDiagnostics.event('metrics', {
      'physicalWidth': view.physicalSize.width,
      'physicalHeight': view.physicalSize.height,
      'devicePixelRatio': view.devicePixelRatio,
    });
  }
}
