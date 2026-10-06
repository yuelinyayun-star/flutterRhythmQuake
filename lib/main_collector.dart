import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'models/station_history_frame.dart';
import 'services/collector/jian_collector_feed.dart';
import 'services/collector/replay_collector.dart';
import 'services/foreground_station_payload.dart';
import 'services/jian_auth_service.dart';
import 'services/ntp_service.dart';
import 'services/sources/cwa_station_service.dart';
import 'services/sources/kma_monitor.dart';
import 'services/sources/lmoni_image_service.dart';
import 'services/sources/lpgm_monitor_service.dart';
import 'services/sources/nied_monitor.dart';
import 'services/sources/palert_service.dart';
import 'services/sources/seisjs_service.dart';
import 'services/sources/snet_service.dart';
import 'services/sources/station_image_decoder.dart';
import 'services/station_history_capture.dart';

/// Private native entrypoint, never included by the public Web build.
/// Linux: run its dedicated release bundle under Xvfb; station decoding is CPU-only.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StationImageDecoder.cpuOnly = true;
  final env = Platform.environment;
  final tokenFile = env['RQ_JIAN_TOKEN_FILE'];
  final spoolPath = env['RQ_COLLECTOR_SPOOL'];
  final outputPath = env['RQ_COLLECTOR_OUTPUT'];
  if (tokenFile == null ||
      spoolPath == null ||
      outputPath == null ||
      !Directory(spoolPath).isAbsolute ||
      !Directory(outputPath).isAbsolute) {
    stderr.writeln(
      'Set RQ_JIAN_TOKEN_FILE and absolute RQ_COLLECTOR_SPOOL / RQ_COLLECTOR_OUTPUT.',
    );
    exit(64);
  }
  final token = (await File(tokenFile).readAsString()).trim();
  if (!isJianCredential(token, 'rt_')) {
    stderr.writeln('Jian requires an rt_ token file; no connection started.');
    exit(64);
  }
  final enabled =
      (env['RQ_COLLECTOR_STATIONS'] ?? 'nied,snet,kma,cwa,seisjs,palert,lpgm')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
  final collector = ReplayCollector(
    spool: Directory(spoolPath),
    output: Directory(outputPath),
    stations: enabled,
  );
  await collector.open();
  final capture = StationHistoryCapture.instance;
  for (final kind in StationHistoryFrame.kinds) {
    capture.setEnabled(kind, enabled.contains(kind));
  }
  // Persistent listener retains only the last frame while there is no event.
  final receivedStationKinds = <String>{};
  void onStation(StationHistoryFrame frame) {
    collector.addStation(frame);
    if (receivedStationKinds.add(frame.kind)) {
      final readings =
          frame.snapshot[frame.kind == 'lpgm' ? 'topStations' : 'stations']
              as List;
      stdout.writeln(
        'Station JSON received: ${frame.kind}; readings=${readings.length}; '
        'receivedAt=${frame.receivedAt.toIso8601String()}',
      );
    }
  }

  capture.addListener(onStation);
  final subscriptions = <StreamSubscription<dynamic>>[];
  final stopSources = <void Function()>[];
  final sourceStatuses = <String, bool>{};
  void status(String source, bool connected) {
    if (sourceStatuses[source] == connected) return;
    sourceStatuses[source] = connected;
    stdout.writeln('$source ${connected ? "connected" : "disconnected"}');
  }

  late final JianCollectorFeed jian;
  var receivedEvents = 0;
  var acceptedEvents = 0;
  var closing = false;
  Timer? checkpoint;
  Future<void> shutdown([int code = 0]) async {
    if (closing) return;
    closing = true;
    checkpoint?.cancel();
    await jian.stop();
    for (final stop in stopSources) {
      stop();
    }
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    capture.removeListener(onStation);
    try {
      await collector.close();
    } catch (_) {
      stderr.writeln('Checkpoint failed; inspect spool before restart.');
      code = 1;
    }
    exit(code);
  }

  jian = JianCollectorFeed(
    credential: token,
    onEvent: (event) {
      try {
        receivedEvents++;
        if (collector.addEvent(event)) {
          acceptedEvents++;
          stdout.writeln(
            'Accepted EEW: ${event.source}; active=${collector.activeCount}',
          );
        }
      } catch (_) {
        stderr.writeln('Event capture failed; checkpointing before exit.');
        unawaited(shutdown(1));
      }
    },
    onStatus: (value) => stdout.writeln('Jian $value'),
  );
  checkpoint = Timer.periodic(const Duration(seconds: 5), (_) async {
    try {
      for (final file in await collector.tick()) {
        stdout.writeln('Saved ${file.uri.pathSegments.last}');
      }
    } catch (_) {
      stderr.writeln(
        'Collector checkpoint/export failed; stopping without deleting pending data.',
      );
      await shutdown(1);
    }
  });
  final memoryLog = Timer.periodic(const Duration(minutes: 1), (_) {
    stdout.writeln(
      'Collector status: rss=${ProcessInfo.currentRss}; '
      'active=${collector.activeCount}; received=$receivedEvents; '
      'accepted=$acceptedEvents; rejected=${receivedEvents - acceptedEvents}; '
      'stations=${receivedStationKinds.join(",")}',
    );
  });
  stopSources.add(memoryLog.cancel);
  ProcessSignal.sigint.watch().listen((_) => unawaited(shutdown()));
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => unawaited(shutdown()));
  }
  // Keep Flutter plugins alive without a map, animations, preferences or audio.
  // All collector image decoding stays on the CPU path.
  runApp(const SizedBox.shrink());
  unawaited(NtpService().syncTime());
  NtpService().startPeriodicSync();
  startCollectorStations(
    enabled: enabled,
    capture: capture,
    status: status,
    subscriptions: subscriptions,
    stopSources: stopSources,
  );
  jian.start();
  stdout.writeln(
    'Collector running; stations=${enabled.join(",")}; '
    'excluded=GQ,ICL,SeedLink; imageDecoder=CPU',
  );
}

/// Shared wiring keeps the isolated recording probe on the production adapters.
void startCollectorStations({
  required Set<String> enabled,
  required StationHistoryCapture capture,
  required void Function(String, bool) status,
  required List<StreamSubscription<dynamic>> subscriptions,
  required List<void Function()> stopSources,
}) {
  if (enabled.contains('nied')) {
    final image = LmoniImageService();
    final monitor = NiedMonitorService();
    image.onStatusChanged = (value) => status('NIED', value);
    subscriptions.add(
      image.stationStream.listen((stations) {
        if (stations != null) {
          capture.publish(
            'nied',
            () => ForegroundStationPayload.nied(
              stations,
              source: 'lmoni',
              includeTrackingHistory: false,
            ),
          );
        }
      }),
    );
    image.start();
    monitor.configureEndpoint('lmoni');
    monitor.start();
    stopSources.add(() {
      monitor.stop();
      image.stop();
    });
  }
  if (enabled.contains('snet')) {
    final service = SnetService();
    service.onStatusChanged = (value) => status('S-net', value);
    subscriptions.add(
      service.stationStreamFromCallback.listen(
        (stations) => capture.publish(
          'snet',
          () => ForegroundStationPayload.snet(stations),
        ),
      ),
    );
    unawaited(service.startMonitoring(intervalSeconds: 15));
    stopSources.add(service.stopMonitoring);
  }
  if (enabled.contains('kma')) {
    final service = KmaMonitorService();
    service.onStatusChanged = (value) => status('KMA', value);
    subscriptions.add(
      service.stationStream.listen(
        (stations) => capture.publish(
          'kma',
          () => ForegroundStationPayload.kma(
            stations,
            dataTime: service.dataTimeNotifier.value,
          ),
        ),
      ),
    );
    service.connect();
    stopSources.add(service.disconnect);
  }
  if (enabled.contains('cwa')) {
    final service = CwaStationService();
    service.onStatusChanged = (value) => status('TREM', value);
    service.start();
    stopSources.add(service.stop);
  }
  if (enabled.contains('seisjs')) {
    final service = SeisJsService();
    service.onStatusChanged = (value) => status('SeisJS', value);
    service.connect();
    stopSources.add(service.disconnect);
  }
  if (enabled.contains('palert')) {
    final service = PAlertService();
    service.onStatusChanged = (value) => status('P-Alert', value);
    service.start();
    stopSources.add(service.stop);
  }
  if (enabled.contains('lpgm')) {
    final service = LpgmMonitorService();
    subscriptions.add(
      service.snapshotStream.listen(
        (snapshot) => capture.publish(
          'lpgm',
          () => ForegroundStationPayload.lpgm(snapshot),
        ),
      ),
    );
    unawaited(service.start(interval: const Duration(seconds: 1)));
    stopSources.add(service.stop);
  }
}
