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
      'stationConnections': [
        // ignore: invalid_use_of_visible_for_testing_member
        for (final connection in service.connectionDiagnostics)
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
