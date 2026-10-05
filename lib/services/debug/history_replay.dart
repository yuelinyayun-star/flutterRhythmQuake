import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/quake_time.dart';
import '../../models/eew_event_group.dart';
import '../../models/unified_quake_data.dart';
import '../../models/eew_display_duration.dart';
import '../../models/station_history_frame.dart';
import '../ntp_service.dart';
import '../quake_event_adapter.dart';
import 'station_json_archive.dart';
import 'station_replay_blocks.dart';
import 'station_archive_storage_web.dart'
    if (dart.library.io) 'station_archive_storage_io.dart'
    as compression;

enum HistoryReplayTiming { report, arrival, manual }

class HistoryReplayPackage {
  static const format = 'rhythmquake-replay';
  static const version = 2;
  static const maxBytes = 128 * 1024 * 1024;
  static const maxReports = 1000;
  static const maxDuration = Duration(days: 1);

  final String name;
  final List<UnifiedQuakeData> reports;
  final List<DateTime> times;
  final int omittedReports;
  final HistoryReplayTiming timing;
  final List<DateTime?> _arrivalInstants;
  final bool usesDeviceArrivalTimeZone;
  final List<StationHistoryFrame> stationFrames;
  final StoredStationHistory? storedStations;
  final DateTime? captureEndedAt;
  bool get manualTiming => timing == HistoryReplayTiming.manual;
  bool get usesArrivalTiming => timing == HistoryReplayTiming.arrival;

  HistoryReplayPackage._(
    this.name,
    this.reports,
    this.times,
    this.omittedReports,
    this.timing,
    this._arrivalInstants,
    this.usesDeviceArrivalTimeZone,
    this.stationFrames,
    this.captureEndedAt,
    this.storedStations,
  );

  static bool hasPayload(UnifiedQuakeData event) =>
      event.sourcePayload?.isNotEmpty == true;

  factory HistoryReplayPackage.fromGroup(
    EewEventGroup group, {
    bool hasArchivedStations = false,
  }) {
    final saved = group.reports.where(hasPayload).toList();
    return HistoryReplayPackage._validated(
      group.latest.hypocenter,
      saved,
      group.reports.length - saved.length,
      stationFrames: group.stationFrames,
      storedStations: group.storedStations,
      captureEndedAt: group.captureEndedAt,
      hasArchivedStations: hasArchivedStations,
    );
  }

  static DateTime? reportInstant(UnifiedQuakeData event) {
    return _sourceReportInstant(event) ?? event.arrivedAt?.toUtc();
  }

  static DateTime? _sourceReportInstant(UnifiedQuakeData event) {
    if (event.reportTime != null) {
      return QuakeTime.unifiedInstantUtc(event, value: event.reportTime);
    }
    final rawTime = QuakeEventAdapter.savedReportTime(
      event.sourcePayload!,
      event.timeZone,
    );
    if (rawTime != null) {
      return QuakeTime.unifiedInstantUtc(event, value: rawTime);
    }
    return null;
  }

  static int _reportNumber(UnifiedQuakeData event) =>
      int.tryParse(
        RegExp(r'\d+').firstMatch(event.reportNumText)?.group(0) ?? '',
      ) ??
      0;

  static bool _consistentTimes(
    List<UnifiedQuakeData> reports,
    List<DateTime?> times,
  ) {
    final sequences = <String, List<(int, DateTime)>>{};
    for (var i = 0; i < reports.length; i++) {
      final event = reports[i];
      final time = times[i];
      if (time == null) return false;
      if (event.originTime != null) {
        final age = time.difference(QuakeTime.unifiedInstantUtc(event));
        if (age.isNegative || age > maxDuration) return false;
      }
      if (event.hasReportSequence && _reportNumber(event) > 0) {
        final key = '${event.source}:${event.eventId}';
        (sequences[key] ??= []).add((_reportNumber(event), time));
      }
    }
    for (final sequence in sequences.values) {
      sequence.sort((a, b) => a.$1.compareTo(b.$1));
      for (var i = 1; i < sequence.length; i++) {
        if (sequence[i].$2.isBefore(sequence[i - 1].$2)) return false;
      }
    }
    return true;
  }

  factory HistoryReplayPackage._validated(
    String name,
    List<UnifiedQuakeData> reports,
    int omitted, {
    List<DateTime?>? arrivalInstants,
    bool importedLegacy = false,
    List<StationHistoryFrame> stationFrames = const [],
    StoredStationHistory? storedStations,
    DateTime? captureEndedAt,
    HistoryReplayTiming? forcedTiming,
    bool hasArchivedStations = false,
  }) {
    if (reports.isEmpty || reports.length > maxReports || omitted < 0) {
      throw const FormatException('回放报文数量无效');
    }
    for (final event in reports) {
      if (!hasPayload(event) ||
          event.isEmpty ||
          event.source.isEmpty ||
          event.eventId.isEmpty ||
          event.timeZone < -12 ||
          event.timeZone > 14 ||
          !event.magnitude.isFinite ||
          !event.depth.isFinite ||
          (event.lat != null &&
              (!event.lat!.isFinite || event.lat!.abs() > 90)) ||
          (event.lng != null &&
              (!event.lng!.isFinite || event.lng!.abs() > 180))) {
        throw const FormatException('回放报文缺少原始数据或事件字段无效');
      }
    }
    final sourceTimes = reports.map(_sourceReportInstant).toList();
    final arrivalTimes =
        arrivalInstants ??
        reports.map((event) => event.arrivedAt?.toUtc()).toList();
    final hasStations =
        hasArchivedStations ||
        stationFrames.isNotEmpty ||
        (storedStations?.frameKeys.isNotEmpty ?? false);
    final hasArrivalTimeline =
        hasStations && _consistentTimes(reports, arrivalTimes);
    if (hasStations && !hasArrivalTimeline) {
      throw const FormatException('测站回放需要有效的报文接收时间');
    }
    if (forcedTiming != null &&
        (forcedTiming == HistoryReplayTiming.manual ||
            !_consistentTimes(
              reports,
              forcedTiming == HistoryReplayTiming.arrival
                  ? arrivalTimes
                  : sourceTimes,
            ) ||
            (hasStations && forcedTiming != HistoryReplayTiming.arrival))) {
      throw const FormatException('回放缺少可联动的时间信息');
    }
    final timing =
        forcedTiming ??
        (!hasArrivalTimeline && _consistentTimes(reports, sourceTimes)
            ? HistoryReplayTiming.report
            : _consistentTimes(reports, arrivalTimes)
            ? HistoryReplayTiming.arrival
            : HistoryReplayTiming.manual);
    final selectedTimes = timing == HistoryReplayTiming.arrival
        ? arrivalTimes
        : sourceTimes;
    final manual = timing == HistoryReplayTiming.manual;
    final indexed = reports.indexed.toList()
      ..sort((a, b) {
        final time = manual
            ? 0
            : selectedTimes[a.$1]!.compareTo(selectedTimes[b.$1]!);
        if (time != 0) return time;
        final number = _reportNumber(a.$2).compareTo(_reportNumber(b.$2));
        return number == 0 ? a.$1.compareTo(b.$1) : number;
      });
    final ordered = indexed.map((item) => item.$2).toList();
    final times = manual
        ? List.filled(
            ordered.length,
            QuakeTime.unifiedInstantUtc(ordered.first),
          )
        : indexed.map((item) => selectedTimes[item.$1]!).toList();
    if (times.last.difference(times.first) > maxDuration) {
      throw const FormatException('单个回放包跨度不能超过 24 小时');
    }
    if ((captureEndedAt != null &&
            (captureEndedAt.isBefore(times.first) ||
                captureEndedAt.difference(times.first) > maxDuration)) ||
        StationReplayFrames.describe(stationFrames).any(
          (frame) =>
              frame.receivedAt.difference(times.first).abs() > maxDuration,
        )) {
      throw const FormatException('测站回放时间跨度无效');
    }
    return HistoryReplayPackage._(
      name,
      List.unmodifiable(ordered),
      List.unmodifiable(times),
      omitted,
      timing,
      List.unmodifiable(indexed.map((item) => arrivalTimes[item.$1])),
      importedLegacy &&
          arrivalInstants == null &&
          timing == HistoryReplayTiming.arrival &&
          reports.any((event) => event.arrivedAt?.isUtc == false),
      stationFrames is StationReplayFrames
          ? stationFrames
          : List.unmodifiable(
              List<StationHistoryFrame>.of(stationFrames)
                ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt)),
            ),
      captureEndedAt?.toUtc(),
      storedStations,
    );
  }

  Duration get duration => times.last.difference(times.first);

  String get identity {
    final keys =
        reports.map((r) => jsonEncode([r.source, r.eventId])).toSet().toList()
          ..sort();
    return jsonEncode(keys);
  }

  HistoryReplayPackage _withTiming(HistoryReplayTiming timing) =>
      HistoryReplayPackage._validated(
        name,
        reports,
        omittedReports,
        arrivalInstants: _arrivalInstants,
        stationFrames: stationFrames,
        storedStations: storedStations,
        captureEndedAt: captureEndedAt,
        forcedTiming: timing,
      );

  Duration get playbackDuration {
    var end = times.last.add(const Duration(seconds: 30));
    final last = reports.last;
    if (last.isEew && last.originTime != null) {
      final expiry = QuakeTime.unifiedInstantUtc(
        last,
      ).add(eewDisplayDuration(last));
      if (expiry.isAfter(end)) end = expiry;
    }
    if (captureEndedAt != null && captureEndedAt!.isAfter(end)) {
      end = captureEndedAt!;
    }
    if (stationFrames.isNotEmpty) {
      final stationEnd = StationReplayFrames.describe(
        stationFrames,
      ).last.receivedAt.add(const Duration(seconds: 30));
      if (stationEnd.isAfter(end)) end = stationEnd;
    }
    final storedEnd = storedStations?.lastReceivedAt?.add(
      const Duration(seconds: 30),
    );
    if (storedEnd != null && storedEnd.isAfter(end)) end = storedEnd;
    return end.difference(times.first);
  }

  String encode() {
    return utf8.decode(encodeBytes());
  }

  Uint8List encodeBytes() {
    if (storedStations?.frameKeys.isNotEmpty ?? false) {
      throw StateError('Load saved station data before exporting');
    }
    final bytes = JsonUtf8Encoder().convert({
      ...exportMetadata(),
      if (stationFrames.isNotEmpty)
        'stationArchive':
            stationFrames is StationReplayFrames &&
                (stationFrames as StationReplayFrames).archive != null
            ? (stationFrames as StationReplayFrames).archive
            : _compressedStations(stationFrames),
    });
    if (bytes.length > maxBytes) {
      throw const FormatException('回放包超过 128 MiB');
    }
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  static Map<String, dynamic> _compressedStations(
    List<StationHistoryFrame> frames,
  ) => {
    'format': StationReplayFrames.format,
    'blocks': [
      for (var start = 0; start < frames.length; start += 64)
        () {
          final end = (start + 64).clamp(0, frames.length);
          final table = StationJsonArchive.encode(frames.sublist(start, end));
          return StationReplayFrames.encodeBlock(
            table,
            compression.compress(JsonUtf8Encoder().convert(table)),
          );
        }(),
    ],
  };

  /// Shared metadata for regular and incremental native-file exports.
  Map<String, dynamic> exportMetadata() => {
    'format': format,
    'version': version,
    'name': name,
    'omittedReports': omittedReports,
    'arrivalInstantsUtc': _arrivalInstants
        .map((time) => time?.toUtc().toIso8601String())
        .toList(),
    'reports': reports.map((e) => e.toMap()).toList(),
    if (captureEndedAt != null)
      'captureEndedAt': captureEndedAt!.toIso8601String(),
  };

  factory HistoryReplayPackage.decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('回放包超过 128 MiB');
    }
    try {
      final value = jsonDecode(text);
      if (value is! Map<String, dynamic> ||
          value['format'] != format ||
          (value['version'] != 1 && value['version'] != version) ||
          value['reports'] is! List ||
          value['name'] is! String ||
          value['omittedReports'] is! int) {
        throw const FormatException('不是受支持的 RhythmQuake 回放包');
      }
      final reports = value['reports'] as List;
      if (reports.length > maxReports) {
        throw const FormatException('回放报文过多');
      }
      List<DateTime?>? arrivalInstants;
      if (value.containsKey('arrivalInstantsUtc')) {
        final arrivals = value['arrivalInstantsUtc'];
        if (arrivals is! List || arrivals.length != reports.length) {
          throw const FormatException('接收时间元数据无效');
        }
        arrivalInstants = arrivals.map<DateTime?>((time) {
          if (time == null) return null;
          final instant = time is String ? DateTime.tryParse(time) : null;
          if (instant == null || !instant.isUtc) {
            throw const FormatException('接收时间必须标明 UTC 或时区');
          }
          return instant;
        }).toList();
      }
      return HistoryReplayPackage._validated(
        value['name'],
        reports
            .map(
              (e) =>
                  UnifiedQuakeData.fromMap(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        value['omittedReports'],
        arrivalInstants: arrivalInstants,
        importedLegacy: true,
        stationFrames: value['stationArchive'] != null
            ? (value['stationArchive']['format'] == StationReplayFrames.format
                  ? StationReplayFrames.decode(value['stationArchive'] as Map)
                  : StationJsonArchive.decode(value['stationArchive'] as Map))
            : (value['stationFrames'] as List? ?? const [])
                  .map((frame) => StationHistoryFrame.fromMap(frame as Map))
                  .toList(),
        captureEndedAt: value['captureEndedAt'] == null
            ? null
            : DateTime.parse(value['captureEndedAt'] as String),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('回放包结构或事件字段无效');
    }
  }
}

class _ReplayPlan {
  final List<(UnifiedQuakeData, DateTime)> reports;
  final List<StationHistoryFrame> stationFrames;
  final List<(HistoryReplayPackage, DateTime)> expiries;
  final DateTime start;
  final DateTime end;
  final bool manual;
  final int eventCount;
  final int skipped;
  final bool missingAnchorTime;
  final bool usesArrivalTiming;

  _ReplayPlan({
    required this.reports,
    required this.stationFrames,
    required this.expiries,
    required this.start,
    required this.end,
    required this.manual,
    required this.eventCount,
    this.skipped = 0,
    this.missingAnchorTime = false,
    this.usesArrivalTiming = false,
  });

  factory _ReplayPlan.single(
    HistoryReplayPackage package, {
    bool missingAnchorTime = false,
  }) => _ReplayPlan(
    reports: [
      for (var i = 0; i < package.reports.length; i++)
        (package.reports[i], package.times[i]),
    ],
    stationFrames: package.stationFrames,
    expiries: const [],
    start: package.times.first,
    end: package.times.first.add(package.playbackDuration),
    manual: package.manualTiming,
    eventCount: 1,
    missingAnchorTime: missingAnchorTime,
    usesArrivalTiming: package.usesArrivalTiming,
  );

  factory _ReplayPlan.linked(
    HistoryReplayPackage anchor,
    Iterable<HistoryReplayPackage> candidates, {
    int skipped = 0,
  }) {
    final HistoryReplayTiming basis;
    if (HistoryReplayPackage._consistentTimes(
      anchor.reports,
      anchor._arrivalInstants,
    )) {
      basis = HistoryReplayTiming.arrival;
    } else if (!anchor.manualTiming) {
      basis = HistoryReplayTiming.report;
    } else {
      return _ReplayPlan.single(anchor, missingAnchorTime: true);
    }
    final primary = anchor._withTiming(basis);
    final start = primary.times.first;
    final anchorEnd = start.add(primary.playbackDuration);
    final selected = [primary];
    final seen = {primary.identity};
    // Match the clicked event's window, not an unbounded chain of overlaps.
    for (final candidate in candidates) {
      if (seen.contains(candidate.identity)) continue;
      try {
        final timed = candidate._withTiming(basis);
        seen.add(candidate.identity);
        final end = timed.times.first.add(timed.playbackDuration);
        if (timed.times.first.isBefore(anchorEnd) && end.isAfter(start)) {
          selected.add(timed);
        }
      } on FormatException {
        skipped++;
      }
    }
    final reports = <(UnifiedQuakeData, DateTime)>[];
    final frames = <String, StationReplayEntry>{};
    final releases = <void Function()>[];
    final expiries = <(HistoryReplayPackage, DateTime)>[];
    var end = anchorEnd;
    for (final package in selected) {
      final expiry = package.times.first.add(package.playbackDuration);
      expiries.add((package, expiry));
      if (expiry.isAfter(end)) end = expiry;
      final initial = <String, UnifiedQuakeData>{};
      for (var i = 0; i < package.reports.length; i++) {
        final report = package.reports[i];
        final time = package.times[i];
        if (!identical(package, primary) && !time.isAfter(start)) {
          initial[jsonEncode([report.source, report.eventId])] = report;
        } else {
          reports.add((report, time));
        }
      }
      // Restore already-active events at the cursor using their latest report.
      reports.addAll(initial.values.map((report) => (report, start)));
      if (package.stationFrames is StationReplayFrames) {
        releases.add((package.stationFrames as StationReplayFrames).release);
      }
      for (final frame in StationReplayFrames.describe(package.stationFrames)) {
        final key = '${frame.kind}:${frame.receivedAt.microsecondsSinceEpoch}';
        final previous = frames[key];
        if (previous != null &&
            (previous.identity != frame.identity || frame.identity == null)) {
          if (jsonEncode(previous.load().toMap()) !=
              jsonEncode(frame.load().toMap())) {
            throw const FormatException('联动回放的同一时刻测站记录冲突');
          }
        }
        frames[key] = previous ?? frame;
      }
    }
    final indexed = reports.indexed.toList()
      ..sort((a, b) {
        final time = a.$2.$2.compareTo(b.$2.$2);
        return time != 0 ? time : a.$1.compareTo(b.$1);
      });
    return _ReplayPlan(
      reports: indexed.map((item) => item.$2).toList(),
      stationFrames: StationReplayFrames(
        frames.values.toList()
          ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt)),
        release: releases,
      ),
      expiries: expiries,
      start: start,
      end: end,
      manual: false,
      eventCount: selected.length,
      skipped: skipped,
      usesArrivalTiming: basis == HistoryReplayTiming.arrival,
    );
  }
}

/// Plays accepted historical snapshots, not new upstream deliveries. The raw
/// bodies and displayed source times remain unchanged; only the map clock shifts.
class HistoryReplayController extends ChangeNotifier {
  final void Function(UnifiedQuakeData) onReport;
  final void Function(String) onClear;
  final DateTime Function() now;
  final Iterable<EewEventGroup> Function()? historyGroups;
  final Future<EewEventGroup> Function(EewEventGroup)? loadHistoryGroup;
  final void Function(String, UnifiedQuakeData)? onEventExpired;
  HistoryReplayController({
    required this.onReport,
    required this.onClear,
    DateTime Function()? now,
    this.historyGroups,
    this.loadHistoryGroup,
    this.onEventExpired,
  }) : now = now ?? (() => NtpService().now.toUtc());

  HistoryReplayPackage? _package;
  EewEventGroup? _storedAnchor;
  HistoryReplayPackage? get package => _package;
  String? _session;
  Timer? _timer;
  Timer? _stationTimer;
  String? playbackError;
  final List<Timer> _expiryTimers = [];
  final Map<String, HistoryReplayPackage> _imports = {};
  List<EewEventGroup> _relatedHistory = const [];
  _ReplayPlan? _plan;
  bool _timelineLinked = false;
  bool _timelineSettingChanged = false;
  static const timelinePreferenceKey = 'history_replay_timeline_linked';
  bool get timelineLinked => _timelineLinked;
  int get totalReports => _plan?.reports.length ?? package?.reports.length ?? 0;
  int get totalStationFrames =>
      _plan?.stationFrames.length ??
      ((package?.stationFrames.length ?? 0) +
          (package?.storedStations?.frameKeys.length ?? 0));
  int get linkedEventCount => _plan?.eventCount ?? 1;
  int get skippedLinkedEvents => _plan?.skipped ?? 0;
  bool get missingTimelineTime => _plan?.missingAnchorTime ?? false;
  bool get usesArrivalTimeline =>
      _plan?.usesArrivalTiming ?? package?.usesArrivalTiming ?? false;
  List<HistoryReplayPackage> get importedPackages =>
      List.unmodifiable(_imports.values);

  void restoreTimelineLinked(bool value) {
    if (_timelineSettingChanged || _timelineLinked == value) return;
    _timelineLinked = value;
    notifyListeners();
  }

  void setTimelineLinked(bool value) {
    if (_timelineLinked == value) return;
    _timelineSettingChanged = true;
    _timelineLinked = value;
    if (!active) _plan = null;
    notifyListeners();
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) async {
            if (!await prefs.setBool(timelinePreferenceKey, value)) {
              throw StateError('Could not save replay timeline setting');
            }
          })
          .catchError((Object error) {
            debugPrint('Replay timeline setting save failed: $error');
          }),
    );
  }

  void importPackages(List<HistoryReplayPackage> values) {
    if (values.isEmpty) return;
    for (final value in values) {
      _imports[value.identity] = value;
    }
    load(values.first);
  }

  final stationSnapshots = ValueNotifier<Map<String, StationHistoryFrame>>(
    const {},
  );
  VoidCallback? _advance;
  int _sequence = 0;
  int played = 0;
  Duration _clockOffset = Duration.zero;
  DateTime get position => now().subtract(_clockOffset);
  bool get active => _session != null;
  bool get holding => active && played == totalReports;

  void load(
    HistoryReplayPackage value, {
    bool remember = true,
    List<EewEventGroup>? relatedHistory,
    EewEventGroup? storedGroup,
  }) {
    stop();
    if (remember) _imports[value.identity] = value;
    if (relatedHistory != null) _relatedHistory = relatedHistory;
    _package = value;
    _storedAnchor = storedGroup;
    _plan = null;
    played = 0;
    notifyListeners();
  }

  int _preparation = 0;
  bool preparing = false;

  Future<void> playPrepared() async {
    final loader = loadHistoryGroup;
    var value = package;
    if (loader == null || value == null) {
      play();
      return;
    }
    final generation = ++_preparation;
    preparing = true;
    notifyListeners();
    try {
      if (value.storedStations?.frameKeys.isNotEmpty ?? false) {
        final anchor = _storedAnchor;
        if (anchor == null) throw StateError('Missing saved replay selection');
        final loaded = await loader(anchor);
        if (_preparation != generation) return;
        value = HistoryReplayPackage.fromGroup(loaded);
        _package = value;
      }
      if (!timelineLinked) {
        play();
        return;
      }
      final groups = (historyGroups?.call() ?? _relatedHistory).toList();
      final candidates = <HistoryReplayPackage>[];
      final identities = <String, EewEventGroup>{};
      var skipped = 0;
      for (final group in groups) {
        try {
          final candidate = HistoryReplayPackage.fromGroup(group);
          candidates.add(candidate);
          identities[candidate.identity] = group;
        } on FormatException {
          skipped++;
        }
      }
      final preview = _ReplayPlan.linked(value, [
        ...candidates,
        ..._imports.values,
      ], skipped: skipped);
      final selected = preview.expiries
          .map((entry) => entry.$1.identity)
          .toSet();
      final prepared = <EewEventGroup>[];
      for (final entry in identities.entries) {
        if (!selected.contains(entry.key) || entry.key == value.identity) {
          continue;
        }
        prepared.add(await loader(entry.value));
        if (_preparation != generation) return;
      }
      if (_preparation == generation) {
        play(preparedHistory: prepared, preparedSkipped: preview.skipped);
      }
    } finally {
      if (_preparation == generation) {
        preparing = false;
        notifyListeners();
      }
    }
  }

  void play({List<EewEventGroup>? preparedHistory, int preparedSkipped = 0}) {
    final value = package;
    if (value == null) return;
    var skipped = preparedSkipped;
    final candidates = <HistoryReplayPackage>[];
    if (timelineLinked) {
      for (final group
          in preparedHistory ?? historyGroups?.call() ?? _relatedHistory) {
        try {
          candidates.add(HistoryReplayPackage.fromGroup(group));
        } on FormatException {
          skipped++;
        }
      }
      candidates.addAll(_imports.values);
    }
    final plan = timelineLinked
        ? _ReplayPlan.linked(value, candidates, skipped: skipped)
        : _ReplayPlan.single(value);
    if ((value.storedStations?.frameKeys.isNotEmpty ?? false) ||
        plan.expiries.any(
          (entry) => entry.$1.storedStations?.frameKeys.isNotEmpty ?? false,
        )) {
      throw StateError('Load saved station data before playback');
    }
    stop();
    _plan = plan;
    final started = now();
    final session = 'replay-${started.microsecondsSinceEpoch}-${++_sequence}';
    _session = session;
    playbackError = null;
    played = 0;
    final clockOffset = started.difference(plan.start);
    _clockOffset = clockOffset;
    var stationIndex = 0;
    final stationEntries = StationReplayFrames.describe(
      plan.stationFrames,
    ).toList();
    void deliverStations() {
      if (_session != session) return;
      final current = Map<String, StationHistoryFrame>.of(
        stationSnapshots.value,
      );
      final position = now().subtract(clockOffset);
      try {
        while (stationIndex < stationEntries.length &&
            !stationEntries[stationIndex].receivedAt.isAfter(position)) {
          final frame = stationEntries[stationIndex++].load();
          current[frame.kind] = frame;
        }
      } catch (error) {
        stop();
        playbackError = '回放失败：$error';
        notifyListeners();
        return;
      }
      stationSnapshots.value = Map.unmodifiable(current);
      if (_session != session || stationIndex == plan.stationFrames.length) {
        return;
      }
      final due = stationEntries[stationIndex].receivedAt.add(clockOffset);
      final delay = due.difference(now());
      _stationTimer = Timer(
        delay.isNegative ? Duration.zero : delay,
        deliverStations,
      );
    }

    deliverStations();
    if (_session != session) return;
    void deliver() {
      if (_session != session) return;
      final report = plan.reports[played].$1;
      onReport(
        report.copyWith(
          eventId: '$session:${report.eventId}',
          replaySessionId: session,
          replayClockOffset: clockOffset,
          arrivedAt: now(),
          isHistory: false,
          isSnapshot: false,
          apiTypeLabel: '本地注入 · 回放',
        ),
      );
      if (_session != session) return;
      played++;
      notifyListeners();
      if (_session != session) return;
      if (played == plan.reports.length) {
        final remaining = plan.end.add(clockOffset).difference(now());
        _timer = Timer(
          remaining < const Duration(seconds: 30)
              ? const Duration(seconds: 30)
              : remaining,
          stop,
        );
      } else if (!plan.manual) {
        final due = started.add(plan.reports[played].$2.difference(plan.start));
        final delay = due.difference(now());
        _timer = Timer(delay.isNegative ? Duration.zero : delay, deliver);
      }
    }

    _advance = deliver;
    deliver();
    if (_session == session && onEventExpired != null) {
      for (final expiry in plan.expiries) {
        _expiryTimers.add(
          Timer(expiry.$2.add(clockOffset).difference(now()), () {
            if (_session != session) return;
            final latest = <String, UnifiedQuakeData>{};
            for (final report in expiry.$1.reports) {
              latest[jsonEncode([report.source, report.eventId])] = report;
            }
            for (final report in latest.values) {
              if (_session != session) return;
              onEventExpired!(session, report);
            }
          }),
        );
      }
    }
  }

  void next() {
    if (active && _plan!.manual && !holding) _advance?.call();
  }

  void stop() {
    _preparation++;
    preparing = false;
    _timer?.cancel();
    _timer = null;
    _stationTimer?.cancel();
    _stationTimer = null;
    for (final timer in _expiryTimers) {
      timer.cancel();
    }
    _expiryTimers.clear();
    _advance = null;
    final frames = _plan?.stationFrames;
    if (frames is StationReplayFrames) frames.release();
    _plan = null;
    final anchor = _storedAnchor;
    if (anchor != null) _package = HistoryReplayPackage.fromGroup(anchor);
    final session = _session;
    _session = null;
    stationSnapshots.value = const {};
    if (session != null) {
      onClear(session);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    final frames = _plan?.stationFrames;
    if (frames is StationReplayFrames) frames.release();
    _preparation++;
    _timer?.cancel();
    _stationTimer?.cancel();
    for (final timer in _expiryTimers) {
      timer.cancel();
    }
    _expiryTimers.clear();
    stationSnapshots.dispose();
    _advance = null;
    _session = null;
    _plan = null;
    _package = null;
    _storedAnchor = null;
    _relatedHistory = const [];
    _imports.clear();
    super.dispose();
  }
}
