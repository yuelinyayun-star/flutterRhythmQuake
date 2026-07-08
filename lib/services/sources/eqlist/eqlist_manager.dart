import 'package:flutter/foundation.dart';
import '../../../core/utils/quake_time.dart';
import '../../../models/quake_message.dart';
import 'jma_eqlist_service.dart';
import 'cenc_eqlist_service.dart';
import 'cwa_eqlist_service.dart';
import '../usgs_eqlist_service.dart';
import '../emsc_eqlist_service.dart';

/// 地震列表管理器
///
/// 该类统一管理多个数据源的地震列表。
/// 聚合JMA、CENC、USGS、FSSN、KMA、CWA等数据源。
///
/// 主要功能：
/// - 管理多个地震列表服务
/// - 聚合各数据源的地震列表
/// - 提供统一的列表访问接口
/// - 列表更新回调通知
///
/// 数据源说明：
/// - JMA: 日本气象厅，通过HTTP轮询获取
/// - CENC: 中国地震台网中心，通过FAN推送+Wolfx WS获取，HTTP轮询作为备用
/// - USGS: 美国地质调查局，通过HTTP轮询获取
/// - FSSN: 中国地震速报，通过FAN推送获取（列表订阅+实时推送）
/// - KMA: 韩国气象厅，通过FAN实时推送获取
/// - CWA: 台湾中央气象署，通过FAN推送获取（列表订阅+实时推送），HTTP轮询作为备用
class EqlistManager {
  static final EqlistManager _instance = EqlistManager._internal();
  factory EqlistManager() => _instance;
  EqlistManager._internal();

  /// JMA地震列表服务
  final JmaEqlistService jma = JmaEqlistService();

  /// CENC地震列表服务
  final CencEqlistService cenc = CencEqlistService();

  /// CWA地震列表服务
  final CwaEqlistService cwa = CwaEqlistService();

  /// USGS地震列表服务
  final UsgsEqlistService usgs = UsgsEqlistService();

  /// EMSC地震列表服务
  final EmscEqlistService emsc = EmscEqlistService();

  /// JMA地震列表缓存
  final List<QuakeMessage> _jmaList = [];

  /// CENC地震列表缓存
  final List<QuakeMessage> _cencList = [];

  /// USGS地震列表缓存
  final List<QuakeMessage> _usgsList = [];

  /// FSSN地震列表缓存
  final List<QuakeMessage> _fssnList = [];

  /// KMA地震列表缓存
  final List<QuakeMessage> _kmaList = [];

  /// CWA地震列表缓存
  final List<QuakeMessage> _cwaList = [];

  /// EMSC地震列表缓存
  final List<QuakeMessage> _emscList = [];

  /// 获取JMA列表（只读）
  List<QuakeMessage> get jmaList => List.unmodifiable(_jmaList);

  /// 获取CENC列表（只读）
  List<QuakeMessage> get cencList => List.unmodifiable(_cencList);

  /// 获取USGS列表（只读）
  List<QuakeMessage> get usgsList => List.unmodifiable(_usgsList);

  /// 获取FSSN列表（只读）
  List<QuakeMessage> get fssnList => List.unmodifiable(_fssnList);

  /// 获取KMA列表（只读）
  List<QuakeMessage> get kmaList => List.unmodifiable(_kmaList);

  /// 获取CWA列表（只读）
  List<QuakeMessage> get cwaList => List.unmodifiable(_cwaList);

  /// 获取EMSC列表（只读）
  List<QuakeMessage> get emscList => List.unmodifiable(_emscList);

  /// 任意列表更新时的回调
  void Function()? onAnyUpdated;
  bool _running = false;

  /// 启动所有HTTP轮询服务
  ///
  /// JMA、USGS通过HTTP轮询获取数据
  /// CENC、FSSN、KMA、CWA通过FAN推送获取数据
  void start() {
    if (_running) return;
    _running = true;
    jma.onListUpdated = (items) {
      _jmaList
        ..clear()
        ..addAll(items);
      _trim(_jmaList);
      onAnyUpdated?.call();
    };
    cenc.onListUpdated = (items) {
      _cencList
        ..clear()
        ..addAll(items);
      _trim(_cencList);
      onAnyUpdated?.call();
    };
    cwa.onListUpdated = (items) {
      _cwaList
        ..clear()
        ..addAll(items);
      _trim(_cwaList);
      onAnyUpdated?.call();
    };
    usgs.onListUpdated = (items) {
      _usgsList
        ..clear()
        ..addAll(items);
      _trim(_usgsList);
      onAnyUpdated?.call();
    };
    emsc.onListUpdated = (items) {
      _emscList
        ..clear()
        ..addAll(items);
      _trim(_emscList);
      onAnyUpdated?.call();
    };
    jma.start();
    cenc.start();
    usgs.start();
    emsc.start();
    debugPrint(
      'EqlistManager: JMA+USGS+CENC+EMSC HTTP poll, CWA+FSSN+KMA via FAN push',
    );
  }

  /// 停止所有HTTP轮询服务
  void stop() {
    if (!_running) return;
    _running = false;
    jma.stop();
    cenc.stop();
    usgs.stop();
    emsc.stop();
  }

  /// 更新FSSN列表
  ///
  /// 由FanService推送触发
  void updateFssnList(List<QuakeMessage> items) {
    _fssnList
      ..clear()
      ..addAll(items);
    _trim(_fssnList);
    onAnyUpdated?.call();
  }

  /// 更新KMA列表
  ///
  /// 由FanService推送触发
  void updateKmaList(List<QuakeMessage> items) {
    _kmaList
      ..clear()
      ..addAll(items);
    _trim(_kmaList);
    onAnyUpdated?.call();
  }

  /// 更新CWA列表
  ///
  /// 由FanService推送触发
  void updateCwaList(List<QuakeMessage> items) {
    _cwaList
      ..clear()
      ..addAll(items);
    _trim(_cwaList);
    onAnyUpdated?.call();
  }

  /// 更新CENC列表
  ///
  /// 由FanService推送触发
  void updateCencList(List<QuakeMessage> items) {
    _cencList
      ..clear()
      ..addAll(items);
    _trim(_cencList);
    onAnyUpdated?.call();
  }

  void updateJmaList(List<QuakeMessage> items) {
    _jmaList
      ..clear()
      ..addAll(items);
    _trim(_jmaList);
    onAnyUpdated?.call();
  }

  /// 更新USGS列表
  ///
  /// 由HTTP轮询触发
  void updateUsgsList(List<QuakeMessage> items) {
    _usgsList
      ..clear()
      ..addAll(items);
    _trim(_usgsList);
    onAnyUpdated?.call();
  }

  /// 更新EMSC列表
  ///
  /// 由HTTP轮询触发
  void updateEmscList(List<QuakeMessage> items) {
    _emscList
      ..clear()
      ..addAll(items);
    _trim(_emscList);
    onAnyUpdated?.call();
  }

  /// 添加单个FSSN条目
  void addFssnItem(QuakeMessage e) {
    _fssnList.insert(0, e);
    _trim(_fssnList);
    onAnyUpdated?.call();
  }

  /// 添加单个KMA条目
  void addKmaItem(QuakeMessage e) {
    _kmaList.insert(0, e);
    _trim(_kmaList);
    onAnyUpdated?.call();
  }

  /// 添加单个CWA条目
  void addCwaItem(QuakeMessage e) {
    _cwaList.insert(0, e);
    _trim(_cwaList);
    onAnyUpdated?.call();
  }

  /// 添加单个CENC条目
  void addCencItem(QuakeMessage e) {
    _cencList.insert(0, e);
    _trim(_cencList);
    onAnyUpdated?.call();
  }

  void upsertBucketItem(String bucket, QuakeMessage e) {
    final list = switch (bucket) {
      'jmaEqlist' => _jmaList,
      'cencEqlist' => _cencList,
      'usgsEqlist' => _usgsList,
      'fssnEqlist' => _fssnList,
      'kmaEqlist' => _kmaList,
      'cwaEqlist' => _cwaList,
      'emscEqlist' => _emscList,
      _ => null,
    };
    if (list == null) return;
    list.removeWhere(
      (item) =>
          item.eventId == e.eventId ||
          (bucket == 'jmaEqlist' && _sameJmaHistoryEvent(item, e)),
    );
    list.insert(0, e);
    _trim(list);
    onAnyUpdated?.call();
  }

  bool _sameJmaHistoryEvent(QuakeMessage a, QuakeMessage b) {
    final keyA = _jmaHistoryDedupeKey(a);
    final keyB = _jmaHistoryDedupeKey(b);
    return keyA != null && keyA == keyB;
  }

  String? _jmaHistoryDedupeKey(QuakeMessage event) {
    if (!_isJmaHistorySource(event.source)) return null;
    final location = event.location.trim().replaceAll(RegExp(r'\s+'), '');
    if (location.isEmpty) return null;
    final originMinute =
        _toComparableUtc(event).millisecondsSinceEpoch ~/
        Duration.millisecondsPerMinute;
    final magnitude = (event.magnitude * 10).round();
    final depth = event.depth.round();
    return '$originMinute|$location|$magnitude|$depth';
  }

  bool _isJmaHistorySource(QuakeSourceType source) {
    return source == QuakeSourceType.wolfx ||
        source == QuakeSourceType.jma_fan ||
        source == QuakeSourceType.p2p;
  }

  DateTime _toComparableUtc(QuakeMessage event) {
    final t = event.originTime;
    final offset = QuakeTime.isJapanSource(event.source)
        ? const Duration(hours: 9)
        : const Duration(hours: 8);
    return DateTime.utc(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
      t.microsecond,
    ).subtract(offset);
  }

  /// 裁剪列表长度
  ///
  /// 保持每个列表最多50条记录
  void _trim(List<QuakeMessage> list) {
    if (list.length > 50) list.removeRange(50, list.length);
  }

  /// 获取所有数据源的列表映射
  ///
  /// 返回格式: {'jmaEqlist': [...], 'cencEqlist': [...], ...}
  Map<String, List<QuakeMessage>> getAllBuckets() => {
    'jmaEqlist': _jmaList,
    'cencEqlist': _cencList,
    'usgsEqlist': _usgsList,
    'fssnEqlist': _fssnList,
    'kmaEqlist': _kmaList,
    'cwaEqlist': _cwaList,
    'emscEqlist': _emscList,
  };
}
