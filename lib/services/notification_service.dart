import 'package:flutter/foundation.dart';

import '../models/unified_quake_data.dart';
import '../providers/notification_settings_provider.dart';
import '../providers/quake_provider.dart';
import 'sound_effect_service.dart';
import 'background_service.dart';

/// 通知服务
///
/// 监听 [QuakeProvider] 的统一事件流，根据 [NotificationSettingsProvider]
/// 的开关设置，触发系统通知、提示音和事件聚焦。
///
/// 参考 KA（kanameishi）的通知行为：
/// - 地震预警（EEW）通知标题包含 `titleText` 与 `reportNumText`；
/// - 通知正文按“震源 / 深度 / 震级 / 最大烈度”换行展示；
/// - 警报级 EEW 同时响应 `onEew` 与 `onEewWarn` 两套开关；
/// - 提示音遵循 issue → update → final，并在强度达到 caution 等级时追加 caution；
/// - 信息事件按来源区分 hypocenter / detail / cancel 音效。
class NotificationService {
  final QuakeProvider _quakeProvider;
  final NotificationSettingsProvider _settings;
  final void Function(String) _playSound;

  final Set<String> _focusedEventIds = <String>{};
  final Map<String, _EewSoundFlags> _eewSoundFlags = <String, _EewSoundFlags>{};

  NotificationService(
    this._quakeProvider,
    this._settings, {
    void Function(String)? playSound,
  }) : _playSound =
           playSound ??
           ((key) {
             SoundEffectService().play(key);
           }) {
    _quakeProvider.onUnifiedEventNotified = _handleEvent;
  }

  void _handleEvent(UnifiedQuakeData event, bool isUpdate) {
    if (!_settings.canNotify) return;

    // 后台模式下不弹出应用内轻通知与音效，统一走系统通知渠道。
    if (BackgroundService().isInBackground) return;

    if (event.isEew) {
      _handleEewEvent(event, isUpdate);
    } else {
      _handleInfoEvent(event, isUpdate);
    }
  }

  void _handleEewEvent(UnifiedQuakeData event, bool isUpdate) {
    final isWarn = event.isWarn;
    final base = _settings.onEew;
    final warn = _settings.onEewWarn;
    final notify = isWarn
        ? (base.notification || warn.notification)
        : base.notification;
    final sound = isWarn ? (base.sound || warn.sound) : base.sound;
    final focus = isWarn ? (base.focus || warn.focus) : base.focus;

    if (!notify && !sound && !focus) return;

    final eventKey = '${event.source}|${event.eventId}';

    if (sound) {
      _playEewSound(event, eventKey);
    }

    if (focus) {
      _focusEvent(event, eventKey);
    }

    if (notify) {
      BackgroundService().showEewSystemNotification(
        event,
        localIntensity: _quakeProvider.estimatedIntensity,
      );
    }
  }

  void _playEewSound(UnifiedQuakeData event, String eventKey) {
    if (event.isCanceled) {
      _playSound('cancel');
      return;
    }

    final flags = _eewSoundFlags.putIfAbsent(eventKey, _EewSoundFlags.new);

    if (!flags.firstSound) {
      _playSound('issue');
      flags.firstSound = true;
    } else if (event.isFinal) {
      _playSound('final');
    } else {
      _playSound('update');
    }

    if (event.isWarn) {
      if (!flags.warnSound) {
        if (_quakeProvider.claimEewThresholdSound(event, warn: true)) {
          _playSound('warn');
        }
        flags.warnSound = true;
        flags.cautionSound = true;
      }
    } else if (_isCautionClass(event.className) && !flags.cautionSound) {
      if (_quakeProvider.claimEewThresholdSound(event, warn: false)) {
        _playSound('caution');
      }
      flags.cautionSound = true;
    }

    _pruneEewSoundFlags();
  }

  bool _isCautionClass(String className) {
    return className == 'green' ||
        className == 'yellow' ||
        className == 'orange' ||
        className == 'dark-orange' ||
        className == 'red' ||
        className == 'dark-red' ||
        className == 'purple';
  }

  void _pruneEewSoundFlags() {
    while (_eewSoundFlags.length > 20) {
      _eewSoundFlags.remove(_eewSoundFlags.keys.first);
    }
  }

  void _handleInfoEvent(UnifiedQuakeData event, bool isUpdate) {
    final settings = _settings.onReport;
    if (!settings.notification && !settings.sound && !settings.focus) return;

    final eventKey = '${event.source}|${event.eventId}';

    if (settings.sound) {
      SoundEffectService().play(_infoSoundKeyForEvent(event));
    }

    if (settings.focus) {
      _focusEvent(event, eventKey);
    }

    if (settings.notification) {
      BackgroundService().showReportSystemNotification(event);
    }
  }

  static String _infoSoundKeyForEvent(UnifiedQuakeData event) {
    if (event.isCanceled) return 'cancel';
    final source = event.source;
    final title = event.titleText;
    if (source == 'jmaEqlist' || source == 'p2pJmaEqlist') {
      if (title.contains('震度速報')) return 'prompt';
      if (title == '震源に関する情報' || title == '震源情報') {
        return 'hypocenter';
      }
      return 'detail';
    }
    if (source == 'cencEqlist') {
      return title.contains('自动') || title.contains('自動')
          ? 'hypocenter'
          : 'detail';
    }
    if (source == 'usgsEqlist') {
      return title.contains('自动') ||
              title.contains('自動') ||
              title.contains('Automatic')
          ? 'hypocenter'
          : 'detail';
    }
    if (source == 'fssnEqlist') {
      if (title.contains('取消')) return 'cancel';
      if (title.contains('自动') || title.contains('自動')) return 'hypocenter';
      return 'detail';
    }
    return 'detail';
  }

  @visibleForTesting
  static String infoSoundKeyForTest(UnifiedQuakeData event) {
    return _infoSoundKeyForEvent(event);
  }

  void _focusEvent(UnifiedQuakeData event, String eventKey) {
    if (!_focusedEventIds.add(eventKey)) return;
    final index = _quakeProvider.unifiedEvents.indexWhere(
      (e) => e.source == event.source && e.eventId == event.eventId,
    );
    if (index >= 0) {
      _quakeProvider.setCurrentUnifiedIndex(index);
    }
  }

  void dispose() {
    _quakeProvider.onUnifiedEventNotified = null;
    _focusedEventIds.clear();
    _eewSoundFlags.clear();
  }
}

class _EewSoundFlags {
  bool firstSound = false;
  bool cautionSound = false;
  bool warnSound = false;
}
