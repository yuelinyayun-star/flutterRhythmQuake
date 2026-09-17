import 'dart:collection';

import '../core/utils/quake_time.dart';
import '../core/utils/catalog_event_identity.dart';
import '../models/quake_message.dart';
import '../models/whews_catalog.dart';
import '../models/unified_quake_data.dart';
import 'sources/whews_service.dart';

enum BackgroundEventResultType { newEvent, update, dropped, history }

class BackgroundEventResult {
  const BackgroundEventResult({
    required this.type,
    this.event,
    this.isUpdate = false,
  });

  final BackgroundEventResultType type;
  final UnifiedQuakeData? event;
  final bool isUpdate;
}

/// Android 后台 isolate 使用的统一事件接纳器。
///
/// 这里仅保留与主 [QuakeProvider] 相同的纯数据规则；UI 列表、轮播和消失
/// Timer 仍由主 isolate 管理。
class BackgroundEventProcessor {
  BackgroundEventProcessor({
    required Map<String, double> sourceInfoMagFilters,
    String infoActionWhitelist = '',
    Map<String, DateTime>? seenUsgsInfoBodyKeys,
    Map<String, DateTime>? seenEmscInfoBodyKeys,
    Map<String, DateTime>? seenCwaInfoBodyKeys,
    Map<String, DateTime>? seenNoUpdateInfoEvents,
    Map<String, DateTime>? seenUnifiedInfoEvents,
    Map<String, int>? acceptedEewReportNums,
    this.onSeenStateChanged,
  }) : _sourceInfoMagFilters = Map.of(sourceInfoMagFilters),
       _infoActionWhitelist = infoActionWhitelist.trim(),
       _seenUsgsInfoBodyKeys = Map.of(seenUsgsInfoBodyKeys ?? const {}),
       _seenEmscInfoBodyKeys = Map.of(seenEmscInfoBodyKeys ?? const {}),
       _seenCwaInfoBodyKeys = Map.of(seenCwaInfoBodyKeys ?? const {}),
       _seenNoUpdateInfoEvents = Map.of(seenNoUpdateInfoEvents ?? const {}),
       _seenUnifiedInfoEvents = Map.of(seenUnifiedInfoEvents ?? const {}),
       _acceptedEewReportNums = Map.of(acceptedEewReportNums ?? const {}) {
    _pruneSeenState(notify: false);
  }

  static const String seenUsgsInfoBodyKeysPreferenceKey =
      'seen_usgs_info_body_keys';
  static const String seenEmscInfoBodyKeysPreferenceKey =
      'seen_emsc_info_body_keys';
  static const String seenCwaInfoBodyKeysPreferenceKey =
      'seen_cwa_info_body_keys';
  static const String seenNoUpdateInfoEventsPreferenceKey =
      'seen_no_update_info_events';
  static const String infoActionWhitelistPreferenceKey =
      'info_action_whitelist';
  static const String seenUnifiedInfoEventsPreferenceKey =
      'background_seen_unified_info_events';
  static const String acceptedEewReportNumsPreferenceKey =
      'background_accepted_eew_report_nums';

  static const Duration _bodyKeyTtl = Duration(hours: 24);
  static const Duration _noUpdateInfoTtl = Duration(hours: 48);
  static const int _maxSeenNoUpdateInfoEvents = 500;

  final Map<String, double> _sourceInfoMagFilters;
  final String _infoActionWhitelist;
  final void Function()? onSeenStateChanged;

  /// 信息事件与主 UI 一样按 source slot 保存，而不是按 eventId 分裂成多条。
  final Map<String, _SlotState> _infoSlots = {};
  final List<_SlotState> _eewSlots = [];
  final Set<String> _dismissedKeys = {};
  final Map<String, int> _acceptedEewReportNums;

  final Map<String, DateTime> _seenUsgsInfoBodyKeys;
  final Map<String, DateTime> _seenEmscInfoBodyKeys;
  final Map<String, DateTime> _seenCwaInfoBodyKeys;
  final Map<String, DateTime> _seenNoUpdateInfoEvents;
  final Map<String, DateTime> _seenUnifiedInfoEvents;

  Map<String, DateTime> get seenUsgsInfoBodyKeys =>
      UnmodifiableMapView(_seenUsgsInfoBodyKeys);
  Map<String, DateTime> get seenEmscInfoBodyKeys =>
      UnmodifiableMapView(_seenEmscInfoBodyKeys);
  Map<String, DateTime> get seenCwaInfoBodyKeys =>
      UnmodifiableMapView(_seenCwaInfoBodyKeys);
  Map<String, DateTime> get seenNoUpdateInfoEvents =>
      UnmodifiableMapView(_seenNoUpdateInfoEvents);
  Map<String, DateTime> get seenUnifiedInfoEvents =>
      UnmodifiableMapView(_seenUnifiedInfoEvents);
  Map<String, int> get acceptedEewReportNums =>
      UnmodifiableMapView(_acceptedEewReportNums);

  BackgroundEventResult process(UnifiedQuakeData event) {
    _pruneSeenState(notify: false);
    if (event.isHistory) {
      if (event.isEew || event.originTime == null ||
          !_passesInfoMagnitudeFilter(event)) {
        return _dropped;
      }
      return BackgroundEventResult(
        type: BackgroundEventResultType.history, event: event,
      );
    }
    return event.isEew ? _processEew(event) : _processInfo(event);
  }

  BackgroundEventResult _processInfo(UnifiedQuakeData event) {
    if (!_passesInfoMagnitudeFilter(event)) return _dropped;
    if (_remainingInfoDisplaySeconds(event) <= 0 &&
        _usesReportTimeDisplayWindow(event)) {
      return _dropped;
    }
    if (_shouldSuppressCachedInfoBody(event)) return _dropped;
    if (_shouldSuppressSeenNoUpdateInfoEvent(event)) return _dropped;
    if (_shouldSuppressSeenUnifiedInfoEvent(event)) return _dropped;

    final slotKey = _infoSlotSource(event);
    final slot = _infoSlots[slotKey];
    if (slot == null) {
      final accepted = event.copyWith(
        arrivedAt: event.arrivedAt ?? DateTime.now(),
      );
      _infoSlots[slotKey] = _SlotState(accepted);
      _rememberNoUpdateInfoEvent(accepted);
      _rememberUnifiedInfoEvent(accepted);
      return BackgroundEventResult(
        type: BackgroundEventResultType.newEvent,
        event: accepted,
      );
    }

    final oldEvent = slot.event;
    if (_isSameUsgsInfoBody(oldEvent, event) ||
        _isSameNoUpdateInfoBody(oldEvent, event) ||
        (_isSameInfoEvent(oldEvent, event) &&
            _isSameInfoBody(oldEvent, event)) ||
        _isCencRecentInfoUpdate(oldEvent, event)) {
      return _dropped;
    }

    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime != null && newReportTime != null) {
      final isNewerReport = newReportTime.isAfter(oldReportTime);
      final isNewerOrigin =
          newReportTime.isAtSameMomentAs(oldReportTime) &&
          oldEvent.originTime != null &&
          event.originTime != null &&
          event.originTime!.isAfter(oldEvent.originTime!);
      final isSameEventBodyCorrection =
          _isSameEventBodyChangedWithoutReportTime(oldEvent, event);
      final isUsgsBodyCorrection = _isUsgsSameReportBodyCorrection(
        oldEvent,
        event,
      );
      final isWhewsBodyCorrection = _isWhewsSameReportBodyCorrection(
        oldEvent,
        event,
      );
      if (!isNewerReport &&
          !isNewerOrigin &&
          !isSameEventBodyCorrection &&
          !isUsgsBodyCorrection &&
          !isWhewsBodyCorrection) {
        return _dropped;
      }
    } else if (!_isSameInfoEvent(oldEvent, event) &&
        !_isLaterInfoEvent(oldEvent, event)) {
      return _dropped;
    }

    final isNewEvent = _canonicalEventId(oldEvent) != _canonicalEventId(event);
    final arrivedAt = isNewEvent
        ? (event.arrivedAt ?? DateTime.now())
        : oldEvent.arrivedAt;
    final merged = _mergeUnifiedInfoEvent(
      oldEvent,
      event,
    ).copyWith(arrivedAt: arrivedAt);
    _infoSlots[slotKey] = _SlotState(merged);
    _rememberNoUpdateInfoEvent(merged);
    _rememberUnifiedInfoEvent(merged);
    return BackgroundEventResult(
      type: isNewEvent
          ? BackgroundEventResultType.newEvent
          : BackgroundEventResultType.update,
      event: merged,
      isUpdate: !isNewEvent,
    );
  }

  BackgroundEventResult _processEew(UnifiedQuakeData event) {
    final elapsedSec = QuakeTime.calcPassedSecondsUnified(event);
    if (elapsedSec >= QuakeTime.eewTimeoutSecondsUnified(event)) {
      return _dropped;
    }

    final index = _findEewSlotIndex(event);
    final eventKey = _eventKey(event);
    if (_dismissedKeys.contains(eventKey) ||
        (index >= 0 &&
            _dismissedKeys.contains(_eventKey(_eewSlots[index].event)))) {
      return _dropped;
    }

    if (index < 0) {
      final reportNum = _extractReportNum(event.reportNumText);
      final storedReportNum = event.hasReportSequence
          ? _acceptedEewReportNums[eventKey] : null;
      if (storedReportNum != null && reportNum <= storedReportNum) {
        return _dropped;
      }
      _acceptedEewReportNums[eventKey] = reportNum;
      onSeenStateChanged?.call();
      final accepted = event.copyWith(
        arrivedAt: event.arrivedAt ?? DateTime.now(),
      );
      _eewSlots.add(_SlotState(accepted));
      return BackgroundEventResult(
        type: storedReportNum == null
            ? BackgroundEventResultType.newEvent
            : BackgroundEventResultType.update,
        event: accepted,
        isUpdate: storedReportNum != null,
      );
    }

    final oldEvent = _eewSlots[index].event;
    final oldKey = _eventKey(oldEvent);

    final reportNum = _extractReportNum(event.reportNumText);
    final storedReportNum = _acceptedEewReportNums[oldKey];
    final canApplyRevision = _isSameReportEewRevision(
      oldEvent,
      event,
    );
    if (storedReportNum != null &&
        reportNum <= storedReportNum &&
        !canApplyRevision) {
      return _dropped;
    }

    if (oldKey != eventKey) {
      _acceptedEewReportNums.remove(oldKey);
      _dismissedKeys.remove(oldKey);
    }
    _acceptedEewReportNums[eventKey] = reportNum;
    onSeenStateChanged?.call();
    final accepted = event.copyWith(
      arrivedAt: event.arrivedAt ?? DateTime.now(),
    );
    _eewSlots[index] = _SlotState(accepted);
    return BackgroundEventResult(
      type: BackgroundEventResultType.update,
      event: accepted,
      isUpdate: true,
    );
  }

  void markDismissed(UnifiedQuakeData event) {
    final key = _eventKey(event);
    _dismissedKeys.add(key);
    if (event.isEew) {
      _acceptedEewReportNums[key] = _extractReportNum(event.reportNumText);
    }
    while (_dismissedKeys.length > 200) {
      _dismissedKeys.remove(_dismissedKeys.first);
    }
  }

  void prune() {
    final now = DateTime.now();
    _infoSlots.removeWhere(
      (_, state) => now.difference(state.arrivedAt).inHours > 1,
    );
    _eewSlots.removeWhere(
      (state) => now.difference(state.arrivedAt).inHours > 1,
    );
    _pruneSeenState();
  }

  String _eventKey(UnifiedQuakeData event) {
    final source = event.isEew ? event.source : _infoSlotSource(event);
    return '$source|${_canonicalEventId(event)}';
  }

  String _infoSlotSource(UnifiedQuakeData event) {
    final noUpdateKey = _noUpdateTimeFanInfoSourceKey(event.source);
    if (noUpdateKey != null) return noUpdateKey;
    return event.source == 'p2pJmaEqlist' ? 'jmaEqlist' : event.source;
  }

  String _canonicalEventId(UnifiedQuakeData event) {
    if (!event.isEew && _infoSlotSource(event) == 'jmaEqlist') {
      final originTime = event.originTime;
      if (originTime != null) return _jmaInfoTimeToken(originTime);
      final digits = event.eventId.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 12) return digits;
    }
    return catalogEventId(event.source, event.eventId);
  }

  String _jmaInfoTimeToken(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}'
        '${two(time.month)}${two(time.day)}${two(time.hour)}'
        '${two(time.minute)}${two(time.second)}';
  }

  bool _passesInfoMagnitudeFilter(UnifiedQuakeData event) {
    final sourceType = _sourceType(event);
    final filterSource = sourceType == QuakeSourceType.cencIr
        ? QuakeSourceType.cenc
        : sourceType;
    if (filterSource == null) return true;
    final filterKey = 'source_mag_filter_${filterSource.name}';
    final threshold =
        _sourceInfoMagFilters[filterKey] ??
        (filterSource == QuakeSourceType.unadapted ? -1 : null);
    if (threshold == null || threshold == 0) return true;
    if (threshold < 0) return false;
    return event.magnitude >= threshold || _matchesInfoActionWhitelist(event);
  }

  bool _matchesInfoActionWhitelist(UnifiedQuakeData event) {
    if (_infoActionWhitelist.isEmpty) return false;
    return _infoActionWhitelist
        .split('|')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .any(event.hypocenter.contains);
  }

  bool _usesReportTimeDisplayWindow(UnifiedQuakeData event) {
    return event.useSourceTimeForExpiry ||
        event.origin == WhewsService.adapterOrigin ||
        event.source == 'usgsEqlist' ||
        event.source == 'cwaEqlist' ||
        event.source == 'cencEqlist';
  }

  int _remainingInfoDisplaySeconds(UnifiedQuakeData event) {
    if (event.useSourceTimeForExpiry && event.originTime == null &&
        event.reportTime == null) {
      return 0;
    }
    if (unifiedCatalogSources.containsKey(event.source) &&
        event.originTime == null) {
      return 0;
    }
    var seconds = 300;
    if (event.className.contains('orange') || event.magnitude >= 6.0) {
      seconds = 600;
    }
    if (event.className.contains('red') || event.magnitude >= 7.0) {
      seconds = 900;
    }
    if (event.className == 'purple' || event.magnitude >= 7.5) {
      seconds = 1200;
    }
    if (event.isVolcanoEvent) seconds = 900;
    if (event.isCanceled) seconds = 60;
    final current = _infoSlots[_infoSlotSource(event)]?.event;
    final catalogRemaining = QuakeTime.catalogInformationRemainingSeconds(
      event,
      seconds,
      firstArrivedAt: current != null && _isSameInfoEvent(current, event)
          ? current.arrivedAt
          : null,
    );
    if (catalogRemaining != null) return catalogRemaining;
    final referenceTime = QuakeTime.informationDisplayReference(event);
    if (referenceTime == null) return seconds;
    final elapsed = QuakeTime.calcPassedSecondsFromDateTime(
      referenceTime,
      Duration(hours: event.timeZone),
    );
    return seconds - elapsed;
  }

  bool _shouldSuppressCachedInfoBody(UnifiedQuakeData event) {
    final key = _infoBodyKey(event);
    if (key == null) return false;
    final cache = switch (event.source) {
      'usgsEqlist' => _seenUsgsInfoBodyKeys,
      'emsc' || 'emscEqlist' => _seenEmscInfoBodyKeys,
      'cwaEqlist' => _seenCwaInfoBodyKeys,
      _ => null,
    };
    if (cache == null) return false;
    final contained = cache.containsKey(key);
    cache[key] = DateTime.now().toUtc();
    if (!contained) onSeenStateChanged?.call();
    return contained;
  }

  String? _infoBodyKey(UnifiedQuakeData event) {
    if (event.source != 'usgsEqlist' &&
        event.source != 'emsc' &&
        event.source != 'emscEqlist' &&
        event.source != 'cwaEqlist') {
      return null;
    }
    return [
      event.eventId,
      event.titleText,
      event.hypocenter,
      event.lat?.toStringAsFixed(6) ?? '',
      event.lng?.toStringAsFixed(6) ?? '',
      event.depth.toStringAsFixed(3),
      event.magnitude.toStringAsFixed(3),
      event.maxIntensity,
      QuakeTime.unifiedInstantUtc(event).toIso8601String(),
    ].join('|');
  }

  bool _isSameUsgsInfoBody(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    return event.source == 'usgsEqlist' &&
        oldEvent.source == event.source &&
        _isSameInfoBody(oldEvent, event);
  }

  bool _isSameNoUpdateInfoBody(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    return event.origin != WhewsService.adapterOrigin &&
        _isNoUpdateTimeFanInfoSource(event.source) &&
        _noUpdateTimeFanInfoSourceKey(oldEvent.source) ==
            _noUpdateTimeFanInfoSourceKey(event.source) &&
        _isSameInfoBody(oldEvent, event);
  }

  bool _isSameInfoBody(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    return _canonicalEventId(oldEvent) == _canonicalEventId(event) &&
        oldEvent.titleText == event.titleText &&
        oldEvent.reportNumText == event.reportNumText &&
        oldEvent.hypocenter == event.hypocenter &&
        _sameDouble(oldEvent.lat, event.lat) &&
        _sameDouble(oldEvent.lng, event.lng) &&
        _sameDouble(oldEvent.depth, event.depth) &&
        _sameDouble(oldEvent.magnitude, event.magnitude) &&
        oldEvent.maxIntensity == event.maxIntensity &&
        oldEvent.className == event.className &&
        oldEvent.warnArea == event.warnArea &&
        oldEvent.isCanceled == event.isCanceled &&
        _sameVolcanoEvent(oldEvent, event) &&
        QuakeTime.unifiedInstantUtc(oldEvent) ==
            QuakeTime.unifiedInstantUtc(event);
  }

  bool _sameVolcanoEvent(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    final oldVolcano = oldEvent.volcanoEvent;
    final newVolcano = event.volcanoEvent;
    if (oldVolcano == null || newVolcano == null) {
      return oldVolcano == null && newVolcano == null;
    }
    return oldVolcano.sameAs(newVolcano);
  }

  bool _isCencRecentInfoUpdate(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.source != 'cencEqlist' ||
        event.origin == WhewsService.adapterOrigin) {
      return false;
    }
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime == null || newReportTime == null) return false;
    if (oldEvent.originTime != null &&
        oldReportTime.isAtSameMomentAs(oldEvent.originTime!)) {
      return false;
    }
    if (event.originTime != null &&
        newReportTime.isAtSameMomentAs(event.originTime!)) {
      return false;
    }
    final diffMs = newReportTime.difference(oldReportTime).inMilliseconds;
    return diffMs >= 0 && diffMs < 30000;
  }

  bool _isSameEventBodyChangedWithoutReportTime(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.origin == WhewsService.adapterOrigin) return false;
    if (!_isNoUpdateTimeFanInfoSource(event.source)) return false;
    if (_noUpdateTimeFanInfoSourceKey(oldEvent.source) !=
        _noUpdateTimeFanInfoSourceKey(event.source)) {
      return false;
    }
    if (oldEvent.eventId != event.eventId || event.eventId.trim().isEmpty) {
      return false;
    }
    return !_isSameInfoBody(oldEvent, event) ||
        oldEvent.className != event.className;
  }

  bool _isUsgsSameReportBodyCorrection(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (event.source != 'usgsEqlist' || oldEvent.source != event.source) {
      return false;
    }
    if (oldEvent.eventId != event.eventId ||
        _isSameUsgsInfoBody(oldEvent, event)) {
      return false;
    }
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    return oldReportTime != null &&
        newReportTime != null &&
        newReportTime.isAtSameMomentAs(oldReportTime);
  }

  bool _isWhewsSameReportBodyCorrection(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (oldEvent.origin != WhewsService.adapterOrigin &&
        event.origin != WhewsService.adapterOrigin) {
      return false;
    }
    if (_infoSlotSource(oldEvent) != _infoSlotSource(event) ||
        _canonicalEventId(oldEvent) != _canonicalEventId(event) ||
        _isSameInfoBody(oldEvent, event)) {
      return false;
    }
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    return oldReportTime != null &&
        newReportTime != null &&
        newReportTime.isAtSameMomentAs(oldReportTime);
  }

  String? _seenNoUpdateInfoEventKey(UnifiedQuakeData event) {
    if (event.origin == WhewsService.adapterOrigin) return null;
    final sourceKey = _noUpdateTimeFanInfoSourceKey(event.source);
    final eventId = _canonicalEventId(event).trim();
    if (sourceKey == null || eventId.isEmpty) return null;
    return '$sourceKey|$eventId';
  }

  bool _shouldSuppressSeenNoUpdateInfoEvent(UnifiedQuakeData event) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null || !_seenNoUpdateInfoEvents.containsKey(key)) return false;
    final current = _infoSlots[_infoSlotSource(event)]?.event;
    return current == null || _seenNoUpdateInfoEventKey(current) != key;
  }

  void _rememberNoUpdateInfoEvent(UnifiedQuakeData event) {
    final key = _seenNoUpdateInfoEventKey(event);
    if (key == null) return;
    final isNew = !_seenNoUpdateInfoEvents.containsKey(key);
    _seenNoUpdateInfoEvents[key] = DateTime.now().toUtc();
    if (isNew) onSeenStateChanged?.call();
  }

  String _seenUnifiedInfoEventKey(UnifiedQuakeData event) {
    return '${_infoSlotSource(event)}|${_canonicalEventId(event)}';
  }

  bool _shouldSuppressSeenUnifiedInfoEvent(UnifiedQuakeData event) {
    final reportKey = catalogReportKey(event);
    if (reportKey != null && _seenUnifiedInfoEvents.containsKey(reportKey)) {
      return true;
    }
    final key = _seenUnifiedInfoEventKey(event);
    if (!_seenUnifiedInfoEvents.containsKey(key)) return false;
    final current = _infoSlots[_infoSlotSource(event)]?.event;
    return current == null || _seenUnifiedInfoEventKey(current) != key;
  }

  void _rememberUnifiedInfoEvent(UnifiedQuakeData event) {
    final key = _seenUnifiedInfoEventKey(event);
    final isNew = !_seenUnifiedInfoEvents.containsKey(key);
    _seenUnifiedInfoEvents[key] = DateTime.now().toUtc();
    final reportKey = catalogReportKey(event);
    final isNewReport = reportKey != null &&
        !_seenUnifiedInfoEvents.containsKey(reportKey);
    if (reportKey != null) {
      _seenUnifiedInfoEvents[reportKey] = DateTime.now().toUtc();
    }
    if (isNew || isNewReport) onSeenStateChanged?.call();
  }

  UnifiedQuakeData _mergeUnifiedInfoEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!_isSameInfoEvent(oldEvent, event)) return event;
    var merged = event.copyWith(eventId: oldEvent.eventId);
    if (_jmaInfoTitleRank(event.titleText) <
        _jmaInfoTitleRank(oldEvent.titleText)) {
      merged = merged.copyWith(titleText: oldEvent.titleText);
    }
    if (!_hasKnownUnifiedShindo(event) && _hasKnownUnifiedShindo(oldEvent)) {
      merged = merged.copyWith(
        maxIntensity: oldEvent.maxIntensity,
        className: oldEvent.className,
      );
    }
    if (event.titleText.trim().isEmpty &&
        oldEvent.titleText.trim().isNotEmpty) {
      merged = merged.copyWith(titleText: oldEvent.titleText);
    }
    if (event.reportNumText.trim().isEmpty &&
        oldEvent.reportNumText.trim().isNotEmpty &&
        event.origin != 2) {
      merged = merged.copyWith(reportNumText: oldEvent.reportNumText);
    }
    if (event.hypocenter.trim().isEmpty &&
        oldEvent.hypocenter.trim().isNotEmpty) {
      merged = merged.copyWith(hypocenter: oldEvent.hypocenter);
    }
    if (event.lat == null && oldEvent.lat != null) {
      merged = merged.copyWith(lat: oldEvent.lat);
    }
    if (event.lng == null && oldEvent.lng != null) {
      merged = merged.copyWith(lng: oldEvent.lng);
    }
    if (event.depthText.trim().isEmpty &&
        oldEvent.depthText.trim().isNotEmpty) {
      merged = merged.copyWith(depthText: oldEvent.depthText);
    }
    if (!event.isCanceled &&
        event.warnArea.trim().isEmpty &&
        oldEvent.warnArea.trim().isNotEmpty) {
      merged = merged.copyWith(warnArea: oldEvent.warnArea);
    }
    if (event.apiTypeLabel.trim().isEmpty &&
        oldEvent.apiTypeLabel.trim().isNotEmpty) {
      merged = merged.copyWith(apiTypeLabel: oldEvent.apiTypeLabel);
    }
    if (event.centroidDepth == null && oldEvent.centroidDepth != null) {
      merged = merged.copyWith(centroidDepth: oldEvent.centroidDepth);
    }
    if (event.momentTensor == null && oldEvent.momentTensor != null) {
      merged = merged.copyWith(momentTensor: oldEvent.momentTensor);
    }
    if (event.cmtMetadata == null && oldEvent.cmtMetadata != null) {
      merged = merged.copyWith(cmtMetadata: oldEvent.cmtMetadata);
    }
    if (event.volcanoEvent == null && oldEvent.volcanoEvent != null) {
      merged = merged.copyWith(volcanoEvent: oldEvent.volcanoEvent);
    }
    if (!_hasUnifiedHypocenter(event) && _hasUnifiedHypocenter(oldEvent)) {
      merged = merged.copyWith(
        hypocenter: oldEvent.hypocenter,
        lat: oldEvent.lat,
        lng: oldEvent.lng,
      );
    }
    if (event.magnitude < 0 && oldEvent.magnitude >= 0) {
      merged = merged.copyWith(magnitude: oldEvent.magnitude);
    }
    if (event.depth < 0 && oldEvent.depth >= 0) {
      merged = merged.copyWith(
        depth: oldEvent.depth,
        depthText: oldEvent.depthText,
      );
    }
    return merged;
  }

  bool _isSameInfoEvent(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    if (oldEvent.isEew || event.isEew) return false;
    if (_infoSlotSource(oldEvent) != _infoSlotSource(event)) return false;
    final oldId = _canonicalEventId(oldEvent).trim();
    final newId = _canonicalEventId(event).trim();
    return oldId.isNotEmpty && oldId == newId;
  }

  bool _isLaterInfoEvent(UnifiedQuakeData oldEvent, UnifiedQuakeData event) {
    final oldOrigin = oldEvent.originTime;
    final newOrigin = event.originTime;
    if (oldOrigin != null && newOrigin != null) {
      return newOrigin.isAfter(oldOrigin);
    }
    final oldArrived = oldEvent.arrivedAt;
    final newArrived = event.arrivedAt;
    return oldArrived != null &&
        newArrived != null &&
        newArrived.isAfter(oldArrived);
  }

  int _jmaInfoTitleRank(String title) {
    if (title.contains('各地の震度')) return 4;
    if (title.contains('震度・震源') || title.contains('震源・震度')) return 3;
    if (title.contains('震源')) return 2;
    if (title.contains('震度速報')) return 1;
    return 0;
  }

  bool _hasKnownUnifiedShindo(UnifiedQuakeData event) {
    final value = event.maxIntensity.trim();
    return value.isNotEmpty && value != '-' && value != '?' && value != '不明';
  }

  bool _hasUnifiedHypocenter(UnifiedQuakeData event) {
    final name = event.hypocenter.trim();
    return name.isNotEmpty &&
        !name.contains('調査中') &&
        !name.contains('调查中') &&
        event.lat != null &&
        event.lng != null;
  }

  int _findEewSlotIndex(UnifiedQuakeData event) {
    return _eewSlots.indexWhere(
      (slot) => _isSameUnifiedEewEvent(slot.event, event),
    );
  }

  bool _isSameUnifiedEewEvent(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!oldEvent.isEew || !event.isEew || oldEvent.source != event.source) {
      return false;
    }
    final oldId = oldEvent.eventId.trim();
    final newId = event.eventId.trim();
    if (oldId.isNotEmpty && newId.isNotEmpty && oldId == newId) return true;
    final oldIdTime = _eewEventIdTimeToken(oldId);
    final newIdTime = _eewEventIdTimeToken(newId);
    if (oldIdTime != null && newIdTime != null && oldIdTime != newIdTime) {
      return false;
    }
    final oldOrigin = oldEvent.originTime;
    final newOrigin = event.originTime;
    if (oldOrigin == null ||
        newOrigin == null ||
        oldOrigin.difference(newOrigin).inSeconds.abs() > 2) {
      return false;
    }
    final oldLat = oldEvent.lat;
    final oldLng = oldEvent.lng;
    final newLat = event.lat;
    final newLng = event.lng;
    if (oldLat == null || oldLng == null || newLat == null || newLng == null) {
      return true;
    }
    if ((oldLat == 0 && oldLng == 0) || (newLat == 0 && newLng == 0)) {
      return true;
    }
    return (oldLat - newLat).abs() <= 0.05 && (oldLng - newLng).abs() <= 0.05;
  }

  bool _isSameReportEewRevision(
    UnifiedQuakeData oldEvent,
    UnifiedQuakeData event,
  ) {
    if (!_isSameUnifiedEewEvent(oldEvent, event) ||
        _extractReportNum(oldEvent.reportNumText) !=
            _extractReportNum(event.reportNumText) ||
        _isSameInfoBody(oldEvent, event)) {
      return false;
    }
    if (!event.hasReportSequence && !oldEvent.hasReportSequence) {
      return !event.isSnapshot && event.origin == oldEvent.origin;
    }
    if (event.origin != WhewsService.adapterOrigin) return false;
    final oldReportTime = oldEvent.reportTime;
    final newReportTime = event.reportTime;
    if (oldReportTime == null || newReportTime == null) return false;
    return !newReportTime.isBefore(oldReportTime);
  }

  String? _eewEventIdTimeToken(String eventId) {
    return RegExp(r'(?:19|20)\d{12}').firstMatch(eventId)?.group(0);
  }

  String? _noUpdateTimeFanInfoSourceKey(String source) {
    return switch (source) {
      'hko' || 'hkoEqlist' => 'hko',
      'emsc' || 'emscEqlist' => 'emsc',
      'bcsf' || 'bcsfEqlist' => 'bcsf',
      'gfz' || 'gfzEqlist' => 'gfz',
      'usp' || 'uspEqlist' => 'usp',
      'fssnCmt' => 'fssnCmt',
      _ => null,
    };
  }

  bool _isNoUpdateTimeFanInfoSource(String source) =>
      _noUpdateTimeFanInfoSourceKey(source) != null;

  QuakeSourceType? _sourceType(UnifiedQuakeData event) {
    if (event.isVolcanoEvent) return null;
    if (event.source == 'jmaEqlist' && event.origin == 2) {
      return QuakeSourceType.p2p;
    }
    const map = <String, QuakeSourceType>{
      'jmaEew': QuakeSourceType.jma_fan,
      'cwaEew': QuakeSourceType.cwa_eew,
      'ceaEew': QuakeSourceType.cea,
      'scEew': QuakeSourceType.sc_eew,
      'fjEew': QuakeSourceType.fj_eew,
      'cqEew': QuakeSourceType.cq_eew,
      'kmaEew': QuakeSourceType.kma_eew_fan,
      'sa': QuakeSourceType.sa,
      'globalQuakeEew': QuakeSourceType.usgs,
      'jmaEqlist': QuakeSourceType.jma_fan,
      'p2pJmaEqlist': QuakeSourceType.p2p,
      'cwaEqlist': QuakeSourceType.cwa,
      'cencEqlist': QuakeSourceType.cenc,
      'nowQuakeCencIr': QuakeSourceType.cencIr,
      'kmaEqlist': QuakeSourceType.kma_eq,
      'usgsEqlist': QuakeSourceType.usgs,
      'fssnEqlist': QuakeSourceType.fssn,
      'fssnCmt': QuakeSourceType.fssnCmt,
      'hko': QuakeSourceType.hko,
      'emsc': QuakeSourceType.emsc,
      'emscEqlist': QuakeSourceType.emsc,
      'bcsf': QuakeSourceType.bcsf,
      'gfz': QuakeSourceType.gfz,
      'usp': QuakeSourceType.usp,
      'geonet': QuakeSourceType.geonet,
      'ningxia': QuakeSourceType.ningxia,
      'guangxi': QuakeSourceType.guangxi,
      'shanxi': QuakeSourceType.shanxi,
      'beijing': QuakeSourceType.beijing,
      'yunnan': QuakeSourceType.yunnan,
      ...unifiedCatalogSources,
    };
    final mapped = map[event.source];
    if (mapped != null) return mapped;
    if (event.source.startsWith('unadapted_') ||
        event.source.startsWith('whews_')) {
      return QuakeSourceType.unadapted;
    }
    return null;
  }

  int _extractReportNum(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  bool _sameDouble(double? a, double? b) {
    if (a == null || b == null) return a == b;
    return (a - b).abs() < 0.000001;
  }

  void _pruneSeenState({bool notify = true}) {
    final now = DateTime.now().toUtc();
    var changed = false;
    changed =
        _removeExpired(_seenUsgsInfoBodyKeys, now, _bodyKeyTtl) || changed;
    changed =
        _removeExpired(_seenEmscInfoBodyKeys, now, _bodyKeyTtl) || changed;
    changed = _removeExpired(_seenCwaInfoBodyKeys, now, _bodyKeyTtl) || changed;
    changed =
        _removeExpired(_seenNoUpdateInfoEvents, now, _noUpdateInfoTtl) ||
        changed;
    changed =
        _removeExpired(_seenUnifiedInfoEvents, now, _noUpdateInfoTtl) ||
        changed;
    if (_seenNoUpdateInfoEvents.length > _maxSeenNoUpdateInfoEvents) {
      final sorted = _seenNoUpdateInfoEvents.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (
        var i = 0;
        i < _seenNoUpdateInfoEvents.length - _maxSeenNoUpdateInfoEvents;
        i++
      ) {
        _seenNoUpdateInfoEvents.remove(sorted[i].key);
      }
      changed = true;
    }
    if (changed && notify) onSeenStateChanged?.call();
  }

  bool _removeExpired(
    Map<String, DateTime> values,
    DateTime now,
    Duration ttl,
  ) {
    final before = values.length;
    values.removeWhere((_, seenAt) => now.difference(seenAt.toUtc()) > ttl);
    return before != values.length;
  }

  static const BackgroundEventResult _dropped = BackgroundEventResult(
    type: BackgroundEventResultType.dropped,
  );
}

class _SlotState {
  _SlotState(this.event) : arrivedAt = DateTime.now();

  final UnifiedQuakeData event;
  final DateTime arrivedAt;
}
