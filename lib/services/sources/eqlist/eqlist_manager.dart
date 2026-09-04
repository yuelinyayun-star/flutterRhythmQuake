import 'package:flutter/foundation.dart';
import '../../../core/utils/quake_time.dart';
import '../../../models/quake_message.dart';
import 'jma_eqlist_service.dart';
import 'cenc_eqlist_service.dart';
import 'cwa_eqlist_service.dart';
import '../cenc_cmt_service.dart';
import '../usgs_cmt_service.dart';
import '../jma_cmt_service.dart';
import '../fnet_cmt_service.dart';
import '../hinet_aqua_cmt_service.dart';
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
/// - EMSC: 欧洲地中海地震中心，通过HTTP轮询获取
/// - FSSN: 中国地震速报，通过FAN推送获取（列表订阅+实时推送）
/// - KMA: 韩国气象厅，通过FAN实时推送获取
/// - CWA: 台湾中央气象署，通过ExpTech v2 HTTP轮询获取，FAN推送作为备用
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

  /// CENC 震源机制解（CMT）服务
  final CencCmtService cencCmt = CencCmtService();

  /// USGS 震源机制解（CMT）服务
  final UsgsCmtService usgsCmt = UsgsCmtService();

  /// JMA 震源机制解（CMT）服务
  final JmaCmtService jmaCmt = JmaCmtService();

  /// F-net 震源机制解（CMT）服务
  final FnetCmtService fnetCmt = FnetCmtService();

  /// Hi-net AQUA 震源机制解（CMT）服务
  final HinetAquaCmtService hinetAquaCmt = HinetAquaCmtService();

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

  /// CENC CMT 震源机制解缓存
  final List<QuakeMessage> _cencCmtList = [];

  /// USGS CMT 震源机制解缓存
  final List<QuakeMessage> _usgsCmtList = [];

  /// JMA CMT 震源机制解缓存
  final List<QuakeMessage> _jmaCmtList = [];

  /// F-net CMT 震源机制解缓存
  final List<QuakeMessage> _fnetCmtList = [];

  /// Hi-net AQUA CMT 震源机制解缓存
  final List<QuakeMessage> _hinetAquaCmtList = [];

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

  /// 获取 CENC CMT 列表（只读）
  List<QuakeMessage> get cencCmtList => List.unmodifiable(_cencCmtList);

  /// 获取 USGS CMT 列表（只读）
  List<QuakeMessage> get usgsCmtList => List.unmodifiable(_usgsCmtList);

  /// 获取 JMA CMT 列表（只读）
  List<QuakeMessage> get jmaCmtList => List.unmodifiable(_jmaCmtList);

  /// 获取 F-net CMT 列表（只读）
  List<QuakeMessage> get fnetCmtList => List.unmodifiable(_fnetCmtList);

  /// 获取 Hi-net AQUA CMT 列表（只读）
  List<QuakeMessage> get hinetAquaCmtList =>
      List.unmodifiable(_hinetAquaCmtList);

  /// 任意列表更新时的回调
  void Function()? onAnyUpdated;

  /// USGS 官方源最新事件回调，用于进入统一 UI。
  void Function(Map<String, dynamic>)? onUsgsCurrentUpdated;

  /// EMSC 官方源最新事件回调，用于进入统一 UI。
  void Function(Map<String, dynamic>)? onEmscCurrentUpdated;

  /// CWA 官方源最新事件回调，用于进入统一 UI。
  void Function(Map<String, dynamic>)? onCwaCurrentUpdated;
  void Function(bool connected)? onHttpStatusChanged;
  void Function(bool connected)? onCmtStatusChanged;

  final Map<String, bool> _httpStatusByService = <String, bool>{};
  final Map<String, bool> _cmtStatusByService = <String, bool>{};
  bool _running = false;

  void _setHttpServiceStatus(String name, bool connected) {
    _httpStatusByService[name] = connected;
    final anyConnected = _httpStatusByService.values.any((state) => state);
    onHttpStatusChanged?.call(anyConnected);
  }

  void _setCmtServiceStatus(String name, bool connected) {
    _cmtStatusByService[name] = connected;
    final anyConnected = _cmtStatusByService.values.any((state) => state);
    onCmtStatusChanged?.call(anyConnected);
  }

  /// 启动所有HTTP轮询服务
  ///
  /// JMA、USGS、EMSC、CWA通过HTTP轮询获取数据
  /// CENC、FSSN、KMA通过FAN推送获取数据
  void start({
    bool jmaHttpEnabled = true,
    bool cencHttpEnabled = true,
    bool usgsHttpEnabled = true,
    bool emscHttpEnabled = true,
    bool cwaHttpEnabled = true,
    bool cencCmtEnabled = true,
    bool usgsCmtEnabled = true,
    bool jmaCmtEnabled = true,
    bool fnetCmtEnabled = true,
    bool hinetAquaCmtEnabled = true,
  }) {
    if (_running) return;
    _running = true;
    _httpStatusByService
      ..clear()
      ..addAll({
        'JMA': false,
        'CENC': false,
        'USGS': false,
        'EMSC': false,
        'CWA': false,
      });
    _cmtStatusByService
      ..clear()
      ..addAll({
        'CENC_CMT': false,
        'USGS_CMT': false,
        'JMA_CMT': false,
        'FNET_CMT': false,
        'HINET_AQUA_CMT': false,
      });
    onHttpStatusChanged?.call(false);
    onCmtStatusChanged?.call(false);
    if (jmaHttpEnabled) {
      jma.onStatusChanged = (connected) =>
          _setHttpServiceStatus('JMA', connected);
    }
    if (cencHttpEnabled) {
      cenc.onStatusChanged = (connected) =>
          _setHttpServiceStatus('CENC', connected);
    }
    if (usgsHttpEnabled) {
      usgs.onStatusChanged = (connected) =>
          _setHttpServiceStatus('USGS', connected);
    }
    if (emscHttpEnabled) {
      emsc.onStatusChanged = (connected) =>
          _setHttpServiceStatus('EMSC', connected);
    }
    if (cwaHttpEnabled) {
      cwa.onStatusChanged = (connected) =>
          _setHttpServiceStatus('CWA', connected);
    }
    cencCmt.onStatusChanged = (connected) =>
        _setCmtServiceStatus('CENC_CMT', connected);
    usgsCmt.onStatusChanged = (connected) =>
        _setCmtServiceStatus('USGS_CMT', connected);
    jmaCmt.onStatusChanged = (connected) =>
        _setCmtServiceStatus('JMA_CMT', connected);
    fnetCmt.onStatusChanged = (connected) =>
        _setCmtServiceStatus('FNET_CMT', connected);
    hinetAquaCmt.onStatusChanged = (connected) =>
        _setCmtServiceStatus('HINET_AQUA_CMT', connected);
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
    usgs.onCurrentUpdated = (data) => onUsgsCurrentUpdated?.call(data);
    emsc.onCurrentUpdated = (data) => onEmscCurrentUpdated?.call(data);
    cwa.onCurrentUpdated = (data) => onCwaCurrentUpdated?.call(data);
    emsc.onListUpdated = (items) {
      _emscList
        ..clear()
        ..addAll(items);
      _trim(_emscList);
      onAnyUpdated?.call();
    };
    if (jmaHttpEnabled) jma.start();
    if (cencHttpEnabled) cenc.start();
    if (usgsHttpEnabled) usgs.start();
    if (emscHttpEnabled) emsc.start();
    if (cwaHttpEnabled) cwa.start();
    if (cencCmtEnabled) cencCmt.start();
    if (usgsCmtEnabled) usgsCmt.start();
    if (jmaCmtEnabled) jmaCmt.start();
    if (fnetCmtEnabled) fnetCmt.start();
    if (hinetAquaCmtEnabled) hinetAquaCmt.start();
    debugPrint(
      'EqlistManager: JMA+USGS+EMSC+CWA HTTP poll, CENC+FSSN+KMA via FAN push, CENC CMT + USGS CMT + JMA CMT + F-net CMT + Hi-net AQUA CMT via HTTP poll',
    );
  }

  /// 停止所有HTTP轮询服务
  void stop() {
    if (!_running) return;
    _running = false;
    _httpStatusByService.clear();
    _cmtStatusByService.clear();
    onHttpStatusChanged?.call(false);
    onCmtStatusChanged?.call(false);
    jma.stop();
    cenc.stop();
    usgs.stop();
    usgs.onCurrentUpdated = null;
    emsc.stop();
    emsc.onCurrentUpdated = null;
    cwa.stop();
    cwa.onCurrentUpdated = null;
    cencCmt.stop();
    usgsCmt.stop();
    jmaCmt.stop();
    fnetCmt.stop();
    hinetAquaCmt.stop();
    jma.onStatusChanged = null;
    cenc.onStatusChanged = null;
    usgs.onStatusChanged = null;
    emsc.onStatusChanged = null;
    cwa.onStatusChanged = null;
    cencCmt.onStatusChanged = null;
    usgsCmt.onStatusChanged = null;
    jmaCmt.onStatusChanged = null;
    fnetCmt.onStatusChanged = null;
    hinetAquaCmt.onStatusChanged = null;
  }

  /// Android 前台服务关闭后恢复主 isolate 的官方 HTTP 列表连接。
  void startOfficialHttpServices() {
    if (!_running) return;
    jma.onStatusChanged = (connected) =>
        _setHttpServiceStatus('JMA', connected);
    usgs.onStatusChanged = (connected) =>
        _setHttpServiceStatus('USGS', connected);
    emsc.onStatusChanged = (connected) =>
        _setHttpServiceStatus('EMSC', connected);
    cwa.onStatusChanged = (connected) =>
        _setHttpServiceStatus('CWA', connected);
    cenc.onStatusChanged = (connected) =>
        _setHttpServiceStatus('CENC', connected);
    jma.start();
    usgs.start();
    emsc.start();
    cwa.start();
    cenc.start();
  }

  /// Android 前台服务接管官方 HTTP 列表时停止主 isolate 的重复连接。
  void stopOfficialHttpServices() {
    if (!_running) return;
    jma.stop();
    usgs.stop();
    emsc.stop();
    cwa.stop();
    cenc.stop();
    _setHttpServiceStatus('USGS', false);
    _setHttpServiceStatus('JMA', false);
    _setHttpServiceStatus('EMSC', false);
    _setHttpServiceStatus('CWA', false);
    _setHttpServiceStatus('CENC', false);
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
    cwa.noteExternalUpdate();
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
    cenc.noteExternalUpdate();
    _cencList
      ..clear()
      ..addAll(items);
    _trim(_cencList);
    onAnyUpdated?.call();
  }

  void updateJmaList(List<QuakeMessage> items) {
    jma.noteExternalUpdate();
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
    cwa.noteExternalUpdate();
    _cwaList.insert(0, e);
    _trim(_cwaList);
    onAnyUpdated?.call();
  }

  /// 添加单个CENC条目
  void addCencItem(QuakeMessage e) {
    cenc.noteExternalUpdate();
    _cencList.insert(0, e);
    _trim(_cencList);
    onAnyUpdated?.call();
  }

  void upsertBucketItem(String bucket, QuakeMessage e) {
    if (bucket == 'jmaEqlist') {
      jma.noteExternalUpdate();
    } else if (bucket == 'cencEqlist') {
      cenc.noteExternalUpdate();
    } else if (bucket == 'cwaEqlist') {
      cwa.noteExternalUpdate();
    }
    final list = switch (bucket) {
      'jmaEqlist' => _jmaList,
      'cencEqlist' => _cencList,
      'usgsEqlist' => _usgsList,
      'fssnEqlist' => _fssnList,
      'kmaEqlist' => _kmaList,
      'cwaEqlist' => _cwaList,
      'emscEqlist' => _emscList,
      'cencCmt' => _cencCmtList,
      'usgsCmt' => _usgsCmtList,
      'jmaCmt' => _jmaCmtList,
      'fnetCmt' => _fnetCmtList,
      'hinetAquaCmt' => _hinetAquaCmtList,
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
    if (!_isJmaHistorySource(a.source) || !_isJmaHistorySource(b.source)) {
      return false;
    }
    final secondA =
        _toComparableUtc(a).millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
    final secondB =
        _toComparableUtc(b).millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
    if (secondA == secondB) return true;

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
    'cencCmt': _cencCmtList,
    'usgsCmt': _usgsCmtList,
    'jmaCmt': _jmaCmtList,
    'fnetCmt': _fnetCmtList,
    'hinetAquaCmt': _hinetAquaCmtList,
  };
}
