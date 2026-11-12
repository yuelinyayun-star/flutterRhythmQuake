import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
// Test harness uses the interface already provided by path_provider_windows.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutterrhythmquake/main.dart' as app;
import 'package:flutterrhythmquake/services/sources/fdsn_motion_service_io.dart';
import 'package:flutterrhythmquake/services/sources/nied_realtime_pipeline.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_realtime_pipeline.dart';
import 'package:flutterrhythmquake/services/sources/mock_input_service.dart';
import 'package:flutterrhythmquake/widgets/map/quake_map_view.dart';

// Explicit opt-in entrypoint. Never used by release packaging.
void main() {
  if (!kProfileMode || !Platform.isWindows) {
    throw StateError('This entrypoint requires Windows Profile mode');
  }
  final root = Platform.environment['RQ_PROFILE_ROOT'];
  if (root == null || !Directory(root).isAbsolute) {
    throw StateError(
      'RQ_PROFILE_ROOT must name an isolated absolute directory',
    );
  }
  PathProviderPlatform.instance = _ProfilePaths(root);
  app.main();
  // Match release logging while retaining VM sampling and frame timings.
  debugPrint = (String? message, {int? wrapWidth}) {};
  final timings = <FrameTiming>[];
  final originalGifInput = MockInputService();
  Map<String, Object?> replay = const {'state': 'idle'};
  // Diagnostic-only controls exercise the same original-GIF UI entrypoint.
  registerExtension('ext.rhythm.niedReplay', (method, parameters) async {
    final source = parameters['source'];
    if (source != null &&
        const ['lmoni', 'kmoni', 'yahoo', 'jian', 'whews'].contains(source)) {
      QuakeMapView.niedSourceNotifier.value = source;
    }
    final path = parameters['gifPath'];
    if (path != null && replay['state'] != 'running') {
      replay = {'state': 'running', 'path': path};
      unawaited(
        originalGifInput
            .injectFromNiedGifPath(path)
            .then(
              (count) {
                replay = {'state': 'completed', 'frames': count};
              },
              onError: (Object error) {
                replay = {'state': 'error', 'error': error.toString()};
              },
            ),
      );
    }
    return ServiceExtensionResponse.result(jsonEncode(replay));
  });
  SchedulerBinding.instance.addTimingsCallback((frames) {
    timings.addAll(frames);
    if (timings.length > 600) timings.removeRange(0, timings.length - 600);
  });
  registerExtension('ext.rhythm.performance', (method, parameters) async {
    final service = FdsnMotionService();
    final result = {
      'pid': pid,
      'rssBytes': ProcessInfo.currentRss,
      'maxRssBytes': ProcessInfo.maxRss,
      'niedPipeline': NiedRealtimePipeline.active?.diagnostics,
      'originalGifReplay': replay,
      'fdsnDataOwner':
          FdsnRealtimePipeline.active?.lastFrame?.processingIsolate,
      'stationConnections': [
        // ignore: invalid_use_of_visible_for_testing_member
        for (final connection
            in FdsnRealtimePipeline.active?.lastFrame?.connections ??
            service.connectionSnapshot)
          {
            ...connection,
            'decodeRejected': {
              for (final e in (connection['decodeRejected'] as Map).entries)
                e.key.toString(): e.value,
            },
          },
      ],
      'frames': [
        for (final t in timings)
          {
            'buildUs': t.buildDuration.inMicroseconds,
            'rasterUs': t.rasterDuration.inMicroseconds,
          },
      ],
    };
    timings.clear();
    return ServiceExtensionResponse.result(jsonEncode(result));
  });
}

class _ProfilePaths extends PathProviderPlatform {
  _ProfilePaths(this.root);
  final String root;
  Future<String> _path(String name) async =>
      (await Directory('$root/$name').create(recursive: true)).path;
  @override
  Future<String> getApplicationSupportPath() => _path('support');
  @override
  Future<String> getApplicationDocumentsPath() => _path('documents');
  @override
  Future<String> getApplicationCachePath() => _path('cache');
  @override
  Future<String> getTemporaryPath() => _path('temp');
  @override
  Future<String> getDownloadsPath() => _path('downloads');
}
