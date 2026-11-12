part of 'quake_provider.dart';

/// UI/platform binding for the native unified event session. Source decisions
/// and retained rule state must not be recalculated in this binding.
extension _NativeUnifiedEvents on QuakeProvider {
  Future<void> _importNativeUnifiedRows(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    _nativeEventOwner.send({
      'op': 'importRows',
      'rows': {
        for (final key in keys)
          key: prefs.getStringList(key) ?? const <String>[],
      },
      'context': _nativeUnifiedContext(),
    });
  }

  NativeUnifiedEventOwner get _nativeEventOwner =>
      _nativeUnified ??= NativeUnifiedEventOwner(
        onBatch: _bindNativeUnifiedBatch,
        onCatalog: (rows) {
          if (_disposed) return;
          _flatHistory = rows;
          _notifyHistorySlice();
        },
      );

  void _nativeProjectFlatHistory() {
    _nativeEventOwner.projectCatalog(
      historyBySource,
      sourceFilter: _sourceFilter,
      magnitudeFilter: _magFilter,
      bucketFilters: {
        for (final entry in QuakeProvider._unifiedToQst.entries)
          if (_sourceInfoMagFilters[entry.value] case final double threshold)
            entry.key: threshold,
      },
    );
  }

  Map<String, dynamic> _nativeUnifiedContext() {
    final now = DateTime.now();
    return {
      'nowUs': now.microsecondsSinceEpoch,
      'nowIso': now.toIso8601String(),
      'sourceNowUs': NtpService().now.microsecondsSinceEpoch,
      'eewNowUs': _eewClock().microsecondsSinceEpoch,
      'localOffsetMinutes': now.timeZoneOffset.inMinutes,
      'volcanoEnabled': _jmaVolcanoPushEnabled,
      'showStale': _showStaleInfoEvent,
      'whitelist': _infoActionWhitelist,
      'blockedSources': [
        if (!AppEdition.hasGlobalQuake) 'globalQuakeEew',
        if (!AppEdition.hasIcl) 'iclEew',
      ],
      'filters': {
        for (final entry in QuakeProvider._unifiedToQst.entries)
          if (_sourceInfoMagFilters[entry.value == QuakeSourceType.cencIr
                  ? QuakeSourceType.cenc
                  : entry.value]
              case final double threshold)
            entry.key: threshold,
        '\u0024unadapted': _sourceInfoMagFilters[QuakeSourceType.unadapted],
      },
      'historyLoaded': _eewHistoryLoaded,
      'speechBusy': TtsService().speakingNotifier.value,
      'historyKeepForever': _eewHistoryRetention.keepForever,
      'historyMaxPerSource': _eewHistoryRetention.maxPerSource,
    };
  }

  void _nativeSortUnifiedViews() {
    if (_unifiedEvents.length < 2) return;
    final ordered = _nativeEventOwner.sortViews(_unifiedEvents);
    _unifiedEvents
      ..clear()
      ..addAll(ordered);
  }

  UnifiedQuakeData _nativeMergeForTest(
    UnifiedQuakeData previous,
    UnifiedQuakeData event,
  ) => _nativeEventOwner.merge(previous, event);

  void _bindNativeUnifiedBatch(
    Map<String, dynamic> batch,
    Map<int, UnifiedQuakeData> pool,
  ) {
    if (_disposed) return;
    final actions = batch['actions'] as List;
    final oldViews = List<UnifiedQuakeData>.of(_unifiedEvents);
    final oldLinks = Map.of(_jmaLpgmDisplayLinks);
    final display = batch['jmaLpgmDisplay'] as Map;
    _jmaLpgmDisplayLinks.clear();
    for (final row in display['links'] as List) {
      final bulletin = pool[row['companion']]!.jmaLpgmBulletin!;
      final retained = _jmaLpgmCompanions[bulletin.eventId] ?? bulletin;
      for (final token in row['information'] as List) {
        _jmaLpgmDisplayLinks[pool[token]!] = (
          bulletin: retained,
          showRegions: row['showRegions'] as bool,
        );
      }
    }
    _unifiedEvents
      ..clear()
      ..addAll([for (final id in display['active'] as List) pool[id]!]);
    final lpgmDisplayChanged =
        oldLinks.length != _jmaLpgmDisplayLinks.length ||
        oldLinks.entries.any((e) => _jmaLpgmDisplayLinks[e.key] != e.value);
    if (lpgmDisplayChanged) {
      _currentUnifiedIndex = _unifiedEvents.isEmpty
          ? 0
          : _currentUnifiedIndex.clamp(0, _unifiedEvents.length - 1);
    }
    final ir = _realtimeCencIrData;
    if (ir?.source == CencIrDataSource.nowQuake &&
        !_hasUnifiedCencIrEvent(ir!)) {
      // Release only after the worker has processed this report, including
      // rejection. Unrelated/bootstrap batches must not discard pending data.
      final consumed = batch['consumed'] as List? ?? const [];
      if (consumed.any((id) {
        final report = pool[id];
        return report?.source == 'nowQuakeCencIr' &&
            (report!.eventId == ir.reportId || report.eventId == ir.uniEventId);
      })) {
        _realtimeCencIrData = null;
        _notifyNativeUnifiedListeners();
      }
    }
    for (final raw in actions) {
      final action = raw as List;
      final kind = action[0] as String;
      final event = action.length > 1 && action[1] is int
          ? pool[action[1]]
          : null;
      switch (kind) {
        case 'startupHistory':
          final original = _nativeStartupGroups!;
          _eewHistory
            ..clear()
            ..addAll([
              for (final row in action[1] as List)
                original[row[0] as int].copyWith(
                  reports: [for (final id in row[1] as List) pool[id]!],
                ),
            ]);
          _nativeStartupGroups = null;
          _eewHistoryRevision++;
          _notifyHistorySlice();
          _schedulePersistEewHistory();
        case 'list':
          _syncUnifiedToListBucket(event!);
        case 'notify':
          _notifyNativeUnifiedListeners();
        case 'history':
          final oldIndex = action[1] as int?;
          final records = [for (final id in action[3] as List) pool[id]!];
          if (oldIndex == null) {
            _eewHistory.insert(
              0,
              EewEventGroup(
                eventId: records.first.eventId,
                reports: records,
                firstArrivedAt: records.first.arrivedAt!,
              ),
            );
          } else {
            final old = _eewHistory[oldIndex];
            _eewHistory[oldIndex] = old.copyWith(
              reports: records,
              storedReports: old.storedReports?.retainReports(records),
            );
          }
          _captureHistoryReportsAt(oldIndex ?? 0);
          _schedulePersistEewHistory();
          _eewHistoryRevision++;
          _notifyHistorySlice();
        case 'discard':
          TtsService().discardEvent(action[2] as String);
        case 'historyOrder':
          final groups = [
            for (final index in action[1] as List) _eewHistory[index as int],
          ];
          _eewHistory
            ..clear()
            ..addAll(groups);
        case 'accepted':
          final current = event!;
          final previous = action[2] == null ? null : pool[action[2]];
          final newInfo = action[3] as bool;
          final suppress = action[4] as bool;
          final immediate = action[6] as bool;
          _syncStationHistoryRecording();
          _domesticEewEffects.observe(current);
          if (previous == null && current.isEew) {
            _cameraSourceDisplayKeys = null;
          }
          if (previous == null && _mobileEewCarousel && current.isEew) {
            _mobileCameraInfoKey = null;
          }
          _unifiedMapRevision++;
          if (!suppress) {
            if (newInfo) {
              ObsAutomationInputService().emitUnifiedEvent(
                previous!,
                ObsUnifiedEventPhase.removed,
              );
              ObsAutomationInputService().emitUnifiedEvent(
                current,
                ObsUnifiedEventPhase.added,
              );
            } else {
              ObsAutomationInputService().emitUnifiedEvent(
                current,
                current.isCanceled && (previous == null || !previous.isCanceled)
                    ? ObsUnifiedEventPhase.canceled
                    : previous == null
                    ? ObsUnifiedEventPhase.added
                    : ObsUnifiedEventPhase.updated,
              );
            }
          }
          if (previous == null) _currentUnifiedIndex = 0;
          _startUnifiedCarousel();
          if (current.isEew) {
            _ensureUnifiedCountdownVoiceTimer();
            _publishUnifiedUi(immediate: immediate);
          } else {
            _notifyNativeUnifiedListeners();
          }
        case 'effects':
          _dispatchUnifiedEventEffects(event!, isUpdate: action[2] as bool);
        case 'removed':
          final removed = event!;
          final key = action[2] as String;
          final endedAt = DateTime.fromMicrosecondsSinceEpoch(
            batch['nowUs'] as int,
            isUtc: true,
          );
          for (final j in (action[3] as List).cast<int>()) {
            _eewHistory[j] = _eewHistory[j].copyWith(captureEndedAt: endedAt);
            _schedulePersistEewHistory();
          }
          ObsAutomationInputService().emitUnifiedEvent(
            removed,
            ObsUnifiedEventPhase.removed,
          );
          _clearRealtimeCencIrForUnifiedEvent(removed);
          _cancelPendingUnifiedUpdateEffects(key);
          if (!removed.isEew) TtsService().discardEvent(key);
          _unifiedCountdownLastSpokenSeconds.remove(key);
          _syncStationHistoryRecording();
          _domesticEewEffects.retainActive(_unifiedEvents);
          _unifiedMapRevision++;
          if (removed.isEew) _clearEewVoice(removed);
          if (_unifiedEvents.isEmpty) {
            _currentUnifiedIndex = 0;
            _unifiedCarouselTimer?.cancel();
            onAllEventsExpired?.call();
          } else {
            _currentUnifiedIndex = _currentUnifiedIndex.clamp(
              0,
              _unifiedEvents.length - 1,
            );
            _startUnifiedCarousel();
          }
          _ensureUnifiedCountdownVoiceTimer();
          _notifyNativeUnifiedListeners();
        case 'replay':
          _refreshReplayPresentation();
          _announceUnifiedEvent(event!, isFirst: !(action[2] as bool));
          onUnifiedEventNotified?.call(event, action[2] as bool);
        case 'replayCleared':
          for (final id in action[1] as List) {
            final old = pool[id];
            if (old?.isEew == true) _clearEewVoice(old!);
          }
          _refreshReplayPresentation();
        case 'stopReplay':
          historyReplay.stop();
        case 'persist':
          unawaited(_persistNativeUnifiedState());
      }
      if (_disposed) return;
    }
    // Source product services own their publication/expiry; an otherwise empty
    // batch only binds their prepared slot snapshot.
    if (actions.isEmpty && oldViews.length != _unifiedEvents.length) {
      _currentUnifiedIndex = _unifiedEvents.isEmpty
          ? 0
          : _currentUnifiedIndex.clamp(0, _unifiedEvents.length - 1);
    }
    if (lpgmDisplayChanged) {
      _unifiedMapRevision++;
      _notifyNativeUnifiedListeners();
    }
  }

  Future<void> _persistNativeUnifiedState() async {
    final owner = _nativeUnified;
    if (owner == null) return;
    final snapshot = owner.query('export') as Map;
    final prefs = await SharedPreferences.getInstance();
    if (snapshot['preferenceRows'] case final Map rows) {
      for (final entry in rows.entries) {
        await prefs.setStringList(
          entry.key as String,
          (entry.value as List).cast<String>(),
        );
      }
    }
  }
}
