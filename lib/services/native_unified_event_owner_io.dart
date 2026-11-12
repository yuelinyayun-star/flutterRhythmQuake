import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:clock/clock.dart' as test_clock;
import '../models/source_payload.dart';
import '../models/unified_quake_data.dart';
import '../models/quake_message.dart';
import 'sources/native_station_core_library_io.dart';

/// Immutable display handles and a codec only. The native session owns event
/// admission, identity, revisions, dismissal, expiry and history ordering.
final class NativeUnifiedEventOwner implements Finalizable {
  NativeUnifiedEventOwner({
    required this.onBatch,
    this.onCatalog,
    bool? manualClock,
  }) : _manual = manualClock ?? Platform.environment['FLUTTER_TEST'] == 'true' {
    final weak = WeakReference(this);
    _port = RawReceivePort((_) => weak.target?._drain());
    _owner = _api.create(
      _port.sendPort.nativePort,
      NativeApi.postCObject.cast(),
      _manual ? 1 : 0,
    );
    if (_owner == nullptr) {
      _port.close();
      throw StateError('Native unified event allocation failed');
    }
    _finalizer.attach(this, _owner, detach: this);
    _portFinalizer.attach(this, _port, detach: this);
    _liveOwners.removeWhere((w) => w.target == null || w.target!._disposed);
    _liveOwners.add(weak);
  }
  static bool get supported => StationCoreLibrary.supported;
  static final _api = _Bindings();
  static final _finalizer = NativeFinalizer(_api.destroyPointer);
  static final _portFinalizer = Finalizer<RawReceivePort>(
    (port) => port.close(),
  );
  static Map<String, int> get diagnostics => {
    'sessions': _api.sessions(),
    'workers': _api.workers(),
  };
  static final _liveOwners = <WeakReference<NativeUnifiedEventOwner>>[];
  static List<Map<String, dynamic>> get runtimeDiagnostics => [
    for (final weak in _liveOwners)
      if (weak.target case final owner? when !owner._disposed)
        {
          'retainedViews': owner._pool.length,
          'pendingViews': owner._pending.length,
          'catalogViews': owner._catalogPool.length,
          'pendingCatalogRevisions': owner._catalogPending.length,
          'pendingBucketRequests': owner._bucketRequests.length,
          'native': owner.queryRaw({'op': 'runtimeStats'}),
        },
  ];
  final void Function(Map<String, dynamic>, Map<int, UnifiedQuakeData>) onBatch;
  final void Function(List<QuakeMessage>)? onCatalog;
  final _catalogIds = Expando<int>();
  final _catalogDescriptors = Expando<Map<String, dynamic>>();
  final _catalogPool = <int, QuakeMessage>{};
  final _catalogKnown = <int>{};
  final _catalogPending = <int, Set<int>>{};
  int _catalogSerial = 0, _catalogRevision = 0;
  final bool _manual;
  bool get usesWorker => !_manual;
  int _bucketRequestSerial = 0;
  final _bucketRequests = <int, Completer<Map<String, dynamic>>>{};
  final _testStartedAt = test_clock.clock.now();
  final _ids = Expando<int>(), _keys = Expando<String>();
  final _messageFields = Expando<Map<String, dynamic>>();
  final _displayRetained = <int>{};
  final _pool = <int, UnifiedQuakeData>{};
  int get retainedViewCount => _pool.length;
  bool retainsView(UnifiedQuakeData event) => _pool.containsValue(event);
  final _pending = <int>{};
  final _descriptors = Expando<Map<String, dynamic>>();
  late final RawReceivePort _port;
  Pointer<Void> _owner = nullptr;
  int _serial = 0, _clock = 0;
  bool _disposed = false, _draining = false;
  Timer? _testDeadline;

  static Object _number(double value) {
    if (value.isFinite) return value;
    final bytes = ByteData(8)..setFloat64(0, value, Endian.little);
    return {'\u0024rqF64': bytes.getUint64(0, Endian.little).toRadixString(16)};
  }

  Map<String, dynamic> describe(UnifiedQuakeData e) {
    final token = _ids[e] ??= ++_serial;
    _pool[token] = e;
    return _descriptors[e] ??= {
      '\u0024token': token,
      'source': e.source,
      'origin': e.origin,
      'eventId': e.eventId,
      'isEew': e.isEew,
      'timeZone': e.timeZone,
      'titleText': e.titleText,
      'reportNumText': e.reportNumText,
      'useShindo': e.useShindo,
      'maxIntensity': e.maxIntensity,
      'className': e.className,
      'hypocenter': e.hypocenter,
      'originTime': e.originTime?.toIso8601String(),
      'reportTime': e.reportTime?.toIso8601String(),
      'magnitude': _number(e.magnitude),
      'depth': _number(e.depth),
      'depthText': e.depthText,
      'lat': e.lat == null ? null : _number(e.lat!),
      'lng': e.lng == null ? null : _number(e.lng!),
      'isWarn': e.isWarn,
      'isFinal': e.isFinal,
      'isCanceled': e.isCanceled,
      'isAssumption': e.isAssumption,
      'warnArea': e.warnArea,
      'apiTypeLabel': e.apiTypeLabel,
      'nodalPlane1': e.nodalPlane1,
      'nodalPlane2': e.nodalPlane2,
      'centroidDepth': e.centroidDepth == null
          ? null
          : _number(e.centroidDepth!),
      'momentTensor': e.momentTensor?.toMap(),
      'cmtMetadata': e.cmtMetadata?.toMap(),
      'volcanoEvent': e.volcanoEvent?.toMap(),
      '\u0024volcanoInstants': e.volcanoEvent == null
          ? null
          : [
              e.volcanoEvent!.reportTime?.microsecondsSinceEpoch,
              e.volcanoEvent!.targetTime?.microsecondsSinceEpoch,
              e.volcanoEvent!.windTime?.microsecondsSinceEpoch,
              for (final window in e.volcanoEvent!.ashfallWindows)
                [
                  window.startTime?.microsecondsSinceEpoch,
                  window.endTime?.microsecondsSinceEpoch,
                ],
            ],
      'isJmaLpgm': e.isJmaLpgm,
      'jmaLpgmBulletin': e.jmaLpgmBulletin == null
          ? null
          : {
              'eventId': e.jmaLpgmBulletin!.eventId,
              'serial': e.jmaLpgmBulletin!.serial,
              'signature': e.jmaLpgmBulletin!.signature,
              'hasRegions': e.jmaLpgmBulletin!.regions.isNotEmpty,
              'originEpochUs': e.jmaLpgmBulletin!.originTime
                  ?.toUtc()
                  .microsecondsSinceEpoch,
              'reportEpochUs': e.jmaLpgmBulletin!.reportTime
                  ?.toUtc()
                  .microsecondsSinceEpoch,
              'lat': e.jmaLpgmBulletin!.latitude,
              'lng': e.jmaLpgmBulletin!.longitude,
              'magnitude': e.jmaLpgmBulletin!.magnitude,
              'depth': e.jmaLpgmBulletin!.depthKm,
            },
      'arrivedAt': e.arrivedAt?.toIso8601String(),
      'isHistory': e.isHistory,
      'isSnapshot': e.isSnapshot,
      'hasReportSequence': e.hasReportSequence,
      'displayEstimateResolved': e.displayEstimateResolved,
      'displayEstimatedIntensity': e.displayEstimatedIntensity,
      'useSourceTimeForExpiry': e.useSourceTimeForExpiry,
      // Only these original source scalars enter admission policy; original
      // reports/rawEvent remain attached to their existing read-only views.
      'sourcePayload': {
        if (e.apiTypeLabel == 'Jian Project')
          'infoTypeName': e.sourcePayload?['infoTypeName'],
        if (e.source == 'ceaEew' && e.apiTypeLabel == 'Jian Project') ...{
          'isTraining': e.sourcePayload?['isTraining'],
          'isWarn': e.sourcePayload?['isWarn'],
          'isCancel': e.sourcePayload?['isCancel'],
          'cancel': e.sourcePayload?['cancel'],
        },
      },
      '\u0024payloadAbsent': e.sourcePayload == null,
      '\u0024replaySessionId': e.replaySessionId,
      '\u0024replayOffsetUs': e.replayClockOffset.inMicroseconds,
    };
  }

  void admit(
    UnifiedQuakeData event,
    Map<String, dynamic> context, {
    bool alreadyAccepted = false,
    bool suppressEffects = false,
  }) {
    final descriptor = describe(event);
    _pending.add(descriptor['\u0024token'] as int);
    send({
      'op': 'admit',
      'event': descriptor,
      'context': context,
      'alreadyAccepted': alreadyAccepted,
      'suppressEffects': suppressEffects,
    });
  }

  void send(Map<String, dynamic> command) {
    if (_disposed) throw StateError('Native unified event session disposed');
    if (_manual) {
      _clock = test_clock.clock.now().difference(_testStartedAt).inMicroseconds;
    }
    if (command['event'] case final Map event) {
      if (event['\u0024token'] case final int id) _pending.add(id);
    }
    if (command['groups'] case final List groups) {
      for (final group in groups) {
        for (final event in group as List) {
          _pending.add((event as Map)['\u0024token'] as int);
        }
      }
    }
    final bytes = JsonUtf8Encoder().convert(command);
    using((arena) {
      final data = arena<Uint8>(bytes.length);
      data.asTypedList(bytes.length).setAll(0, bytes);
      final error = _api.send(_owner, data, bytes.length, _clock);
      if (error != 0) {
        throw StateError('Native unified event command rejected ($error)');
      }
    });
    if (_manual) _drain();
  }

  dynamic query(
    String op, {
    UnifiedQuakeData? event,
    UnifiedQuakeData? previous,
    Map<String, dynamic> parameters = const {},
  }) {
    final result = queryRaw({
      ...parameters,
      'op': op,
      if (event != null) 'event': describe(event),
      if (previous != null) 'previous': describe(previous),
    });
    if (!_draining) {
      _pool.removeWhere(
        (id, _) => !_displayRetained.contains(id) && !_pending.contains(id),
      );
    }
    return result;
  }

  Map<String, dynamic> messageFields(UnifiedQuakeData event) =>
      _messageFields[event] ??= Map<String, dynamic>.from(
        query('messageFields', event: event) as Map,
      );

  dynamic queryRaw(Map<String, dynamic> command) {
    if (_disposed) throw StateError('Native unified event session disposed');
    final bytes = JsonUtf8Encoder().convert(command);
    return using((arena) {
      final data = arena<Uint8>(bytes.length), size = arena<Size>();
      data.asTypedList(bytes.length).setAll(0, bytes);
      final pointer = _api.query(_owner, data, bytes.length, size);
      if (pointer == nullptr) {
        throw StateError('Native unified event query failed');
      }
      return PackedSourceJson(
        Uint8List.fromList(pointer.asTypedList(size.value)),
      ).root;
    });
  }

  String key(UnifiedQuakeData event) =>
      _keys[event] ?? query('key', event: event) as String;
  void rebindHistory(
    List<UnifiedQuakeData> original,
    List<UnifiedQuakeData> summaries,
  ) {
    if (original.length != summaries.length) {
      throw StateError('History summary changed report layout');
    }
    final mappings = <List<int>>[];
    for (var j = 0; j < original.length; j++) {
      if (identical(original[j], summaries[j])) continue;
      final old = _ids[original[j]];
      if (old == null) continue;
      final next = _ids[summaries[j]] ??= ++_serial;
      _pool[next] = summaries[j];
      _pending.add(next);
      mappings.add([old, next]);
      final key = _keys[original[j]];
      if (key != null) _keys[summaries[j]] = key;
    }
    if (mappings.isNotEmpty) {
      send({'op': 'rebindHistory', 'mappings': mappings});
    }
  }

  void projectCatalog(
    Map<String, List<QuakeMessage>> buckets, {
    required Set<String> sourceFilter,
    required double magnitudeFilter,
    required Map<String, double> bucketFilters,
  }) {
    final rows = <Map<String, dynamic>>[], ids = <int>{};
    final names = <Object>[];
    for (final entry in buckets.entries) {
      final tokens = <int>[];
      for (final e in entry.value) {
        final token = _catalogIds[e] ??= ++_catalogSerial;
        _catalogPool[token] = e;
        ids.add(token);
        tokens.add(token);
        if (_catalogKnown.add(token)) {
          rows.add(_describeCatalog(e));
        }
      }
      names.add([entry.key, tokens]);
    }
    final revision = ++_catalogRevision;
    _catalogPending[revision] = ids;
    send({
      'op': 'catalog',
      'catalogRevision': revision,
      'rows': rows,
      'buckets': names,
      'sourceFilter': sourceFilter.toList(),
      'magnitudeFilter': magnitudeFilter,
      'bucketFilters': bucketFilters,
    });
  }

  Map<String, dynamic> _describeCatalog(QuakeMessage e) =>
      _catalogDescriptors[e] ??= {
        '\u0024token': _catalogIds[e] ??= ++_catalogSerial,
        'eventId': e.eventId,
        '\u0024quakeSource': e.source.name,
        'lat': _number(e.latitude),
        'lng': _number(e.longitude),
        'apiTypeLabel': e.apiTypeLabel,
        'titleText': e.infoTypeName,
        'hypocenter': e.location,
        'magnitude': _number(e.magnitude),
        'depth': _number(e.depth),
        'originTime': e.originTime.toIso8601String(),
        '\u0024originEpochMs': e.originTime.millisecondsSinceEpoch,
        'reportTime': e.reportTime?.toIso8601String(),
        'timeZone': e.timeZone,
        'reportNumText': e.reportNumText,
        'reviewType': e.reviewType,
        'tsunamiWarning': e.tsunamiWarning,
        'nodalPlane1': e.nodalPlane1,
        'nodalPlane2': e.nodalPlane2,
        'centroidDepth': e.centroidDepth == null
            ? null
            : _number(e.centroidDepth!),
        'momentTensor': e.momentTensor?.toMap(),
        'cmtMetadata': e.cmtMetadata?.toMap(),
        'usgsUpdated': e.usgsUpdated,
        'usgsProductTypes': e.usgsProductTypes,
      };

  ({List<QuakeMessage> rows, int notifications}) upsertBucket(
    String bucket,
    List<QuakeMessage> current,
    QuakeMessage incoming, {
    required bool replayOnly,
  }) {
    final result =
        queryRaw({
              'op': 'bucketUpsert',
              'bucket': bucket,
              'rows': [for (final e in current) _describeCatalog(e)],
              'incoming': _describeCatalog(incoming),
              'replayOnly': replayOnly,
            })
            as Map;
    return (
      rows: [
        for (final j in result['indices'] as List)
          j == -1 ? incoming : current[j as int],
      ],
      notifications: result['notifications'] as int,
    );
  }

  Future<({List<QuakeMessage> rows, int notifications})> upsertBucketAsync(
    String bucket,
    List<QuakeMessage> current,
    QuakeMessage incoming, {
    required bool replayOnly,
  }) async {
    final request = ++_bucketRequestSerial;
    final completer = Completer<Map<String, dynamic>>();
    _bucketRequests[request] = completer;
    try {
      send({
        'op': 'bucketUpsertAsync',
        'request': request,
        'bucket': bucket,
        'rows': [for (final e in current) _describeCatalog(e)],
        'incoming': _describeCatalog(incoming),
        'replayOnly': replayOnly,
      });
      final result = await completer.future;
      return (
        rows: [
          for (final j in result['indices'] as List)
            j == -1 ? incoming : current[j as int],
        ],
        notifications: result['notifications'] as int,
      );
    } finally {
      _bucketRequests.remove(request);
    }
  }

  List<UnifiedQuakeData> sortViews(List<UnifiedQuakeData> events) {
    final indices =
        queryRaw({
              'op': 'sort',
              'events': [for (final e in events) describe(e)],
            })
            as List;
    return [for (final index in indices) events[index as int]];
  }

  UnifiedQuakeData merge(UnifiedQuakeData previous, UnifiedQuakeData event) {
    final fields =
        query('mergeFields', event: event, previous: previous) as List;
    final base = describe(event)['\u0024token'] as int,
        old = describe(previous)['\u0024token'] as int;
    return _view({
      'id': ++_serial,
      'base': base,
      'inherit': {for (final f in fields) f: old},
      'arrivalUs': event.arrivedAt?.microsecondsSinceEpoch,
      'arrivalUtc': event.arrivedAt?.isUtc ?? false,
    });
  }

  UnifiedQuakeData _view(Map row) {
    final base = _pool[row['base']]!;
    final refs = row['inherit'] as Map;
    UnifiedQuakeData from(String field) =>
        refs.containsKey(field) ? _pool[refs[field]]! : base;
    final view = base.copyWith(
      eventId: from('eventId').eventId,
      titleText: from('titleText').titleText,
      reportNumText: from('reportNumText').reportNumText,
      hypocenter: from('hypocenter').hypocenter,
      lat: from('lat').lat,
      lng: from('lng').lng,
      depth: from('depth').depth,
      depthText: from('depthText').depthText,
      magnitude: from('magnitude').magnitude,
      maxIntensity: from('maxIntensity').maxIntensity,
      className: from('className').className,
      warnArea: from('warnArea').warnArea,
      apiTypeLabel: from('apiTypeLabel').apiTypeLabel,
      centroidDepth: from('centroidDepth').centroidDepth,
      momentTensor: from('momentTensor').momentTensor,
      cmtMetadata: from('cmtMetadata').cmtMetadata,
      volcanoEvent: from('volcanoEvent').volcanoEvent,
      arrivedAt: row['arrivalUs'] == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              row['arrivalUs'] as int,
              isUtc: row['arrivalUtc'] as bool,
            ),
    );
    final id = row['id'] as int;
    _ids[view] = id;
    _pool[id] = view;
    return view;
  }

  void _drain() {
    if (_disposed || _draining) return;
    _draining = true;
    try {
      using((arena) {
        final size = arena<Size>();
        while (!_disposed) {
          final pointer = _api.take(_owner, size);
          if (pointer == nullptr) break;
          final batch =
              PackedSourceJson(
                    Uint8List.fromList(pointer.asTypedList(size.value)),
                  ).root
                  as Map<String, dynamic>;
          if (batch['error'] != null) {
            throw StateError(batch['error'] as String);
          }
          for (final row in batch['views'] as List) {
            _view(row as Map);
          }
          for (final row in batch['keys'] as List) {
            final e = _pool[row[0]];
            if (e != null) _keys[e] = row[1] as String;
          }
          for (final action in batch['actions'] as List) {
            if (action[0] == 'bucketUpsert') {
              _bucketRequests
                  .remove(action[1])
                  ?.complete(Map<String, dynamic>.from(action[2] as Map));
            }
            if (action[0] == 'list') {
              final view = _pool[action[1]];
              if (view != null) {
                _messageFields[view] = Map<String, dynamic>.from(
                  action[2] as Map,
                );
              }
            }
            if (action[0] == 'flat') {
              onCatalog?.call([
                for (final id in action[1] as List) _catalogPool[id]!,
              ]);
            }
          }
          onBatch(batch, _pool);
          if (_disposed) break;
          for (final id in batch['consumed'] as List? ?? const []) {
            _pending.remove(id);
          }
          final retained = (batch['retained'] as List).cast<int>().toSet();
          _displayRetained
            ..clear()
            ..addAll(retained);
          _pool.removeWhere(
            (id, _) => !retained.contains(id) && !_pending.contains(id),
          );
          final catalogAck = batch['catalogRevision'] as int;
          _catalogPending.removeWhere((revision, _) => revision <= catalogAck);
          _catalogKnown
            ..clear()
            ..addAll((batch['catalogRetained'] as List).cast<int>());
          for (final ids in _catalogPending.values) {
            _catalogKnown.addAll(ids);
          }
          _catalogPool.removeWhere((id, _) => !_catalogKnown.contains(id));
          if (_manual) {
            _testDeadline?.cancel();
            final next = batch['nextDeadline'] as int?;
            if (next != null) {
              _testDeadline = Timer(
                Duration(
                  microseconds: (next - _clock).clamp(0, 9223372036854775807),
                ),
                () {
                  if (_disposed) return;
                  _clock = next;
                  send({'op': 'tick'});
                },
              );
            }
          }
        }
      });
    } finally {
      _draining = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _testDeadline?.cancel();
    _port.close();
    _finalizer.detach(this);
    _portFinalizer.detach(this);
    _api.destroy(_owner);
    for (final request in _bucketRequests.values) {
      request.completeError(
        StateError('Native unified event session disposed'),
      );
    }
    _bucketRequests.clear();
    _owner = nullptr;
    _pool.clear();
    _catalogPool.clear();
    _catalogKnown.clear();
    _catalogPending.clear();
    _pending.clear();
  }
}

class _Bindings {
  final lib = StationCoreLibrary.library;
  late final create = lib
      .lookupFunction<
        Pointer<Void> Function(Int64, Pointer<Void>, Uint8),
        Pointer<Void> Function(int, Pointer<Void>, int)
      >('rq_unified_event_create');
  late final send = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Int64),
        int Function(Pointer<Void>, Pointer<Uint8>, int, int)
      >('rq_unified_event_send');
  late final query = lib
      .lookupFunction<
        Pointer<Uint8> Function(
          Pointer<Void>,
          Pointer<Uint8>,
          Size,
          Pointer<Size>,
        ),
        Pointer<Uint8> Function(
          Pointer<Void>,
          Pointer<Uint8>,
          int,
          Pointer<Size>,
        )
      >('rq_unified_event_query');
  late final take = lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>),
        Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>)
      >('rq_unified_event_take');
  late final destroyPointer = lib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        'rq_unified_event_destroy',
      );
  late final destroy = destroyPointer
      .asFunction<void Function(Pointer<Void>)>();
  late final sessions = lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_unified_event_sessions',
  );
  late final workers = lib.lookupFunction<Uint64 Function(), int Function()>(
    'rq_unified_event_workers',
  );
}
