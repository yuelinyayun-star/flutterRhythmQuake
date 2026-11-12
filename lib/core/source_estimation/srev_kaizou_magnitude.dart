import 'dart:math' as math;

import '../../services/sources/jp_shindo_scale.dart';
import 'srev_kaizou_scratch_station_table.dart';

const int srevKaizouScratchStationCount = 1748;
const double srevKaizouMinimumStationDistanceKm = 20.0;
const Duration srevKaizouMaximumShindoHoldDuration = Duration(seconds: 10);

/// JMA の「最終報」相当の確定ホールド。震源が安定し、かつ入力震度がこの時間
/// 以上改善しないことをもって参考震級を確定する。JMA は観測（最大振幅／最大
/// 計測震度）が成熟してから M を確定するため、震源位置が安定した最初の
/// フレームで凍結すると弱イベントで M が過小になる。
/// 参照：地震火山部『緊急地震速報の概要や処理手法に関する技術的参考資料』
/// （令和6年4月11日改訂）§1 概要。
const Duration srevKaizouMagnitudeFinalizeHoldDuration = Duration(seconds: 10);

/// 对处理震度 I 的斜率。上游原始实现为 1.0；
/// 多语料留一(LOO)重拟合 ≈ 1/a_fit = 1/1.4334 ≈ 0.7016
/// （见 tmp/mag_scoreboard/ablation.json -> knet.fit2_in.a）。
/// 距离项系数 1.73 与 20km 下限钳位本次保持不变。
const double srevKaizouMagnitudeIntensitySlope = 0.7016;

/// 与 [srevKaizouMagnitudeIntensitySlope] 成对的重定标常数，
/// 使语料均值处整体偏差保持 ≈0（同源 knet.fit2_in.c）。
const double srevKaizouMagnitudeIntensityOffset = 0.0903;

/// 生产展开式 `M = (I_proc − 0.94) + 1.73·log10(D)` 隐含的对 I 的斜率 1.0，
/// 以及其截距常数。仅用于把「相对生产斜率的抬升量」显式写出后做 D 条件化缩放，
/// 不改变距离项。
const double srevKaizouLegacyIntensitySlope = 1.0;
const double srevKaizouLegacyIntensityOffset = 0.94;

/// D 条件化的抬升权重 `w(D) = min(1, 20/D)`。
///
/// 斜率修正（0.7016）由多语料 LOO 重拟合得出，而该语料中内陆浅震的
/// `D = 震央→最近 scratch 站距离` 有 31/52 被下限钳在 20km——距离信息已被
/// 压平进常数项（等价于生产对这批事件退化为 `M = I_proc + 1.311`）。
/// 因此该修正**只在 D 触底时成立**：D 越大，真距离项越在起作用，越应回退到
/// 生产斜率 1.0。权重在 D≤20km 时取满 1，之后按 20/D 单调衰减（D=40→0.50、
/// D=100→0.20）。
///
/// 影子验证（73 例，`tmp/mag_scoreboard/DCOND.md`）：无条件施加全量抬升时
/// rqreplay 真距组被整体推高 +0.53（宮城県沖 +0.52），本权重把该组压回
/// −0.12、宮城降到 +0.23，同时 K-NET 档间极差仍保持 1.12（不受影响）；
/// 代价是 K-NET+rqreplay 合并 RMS 由 0.499 微升到 0.528。
double srevKaizouMagnitudeDistanceWeight(double stationDistanceKm) {
  if (!stationDistanceKm.isFinite || stationDistanceKm <= 0.0) return 0.0;
  final weight = srevKaizouMinimumStationDistanceKm / stationDistanceKm;
  return weight < 1.0 ? weight : 1.0;
}

const String srevKaizouMagnitudeModelId =
    'srev_kaizou_scratch_magnitude_v3_dcond_20_over_d';
const String srevKaizouMagnitudeSourceRevision =
    't0729/srev-kaizou@fe881fe9a172c02e81c88011792af22804255a84';
const String srevKaizouMagnitudeSourceProjectSha256 =
    srevKaizouScratchProjectSha256;

class SrevKaizouMagnitudeStation {
  const SrevKaizouMagnitudeStation({
    required this.code,
    required this.latitude,
    required this.longitude,
    this.name,
  });

  final String code;
  final double latitude;
  final double longitude;
  final String? name;
}

class SrevKaizouMagnitudeResult {
  const SrevKaizouMagnitudeResult({
    required this.magnitude,
    required this.roundedSourceLatitude,
    required this.roundedSourceLongitude,
    required this.nearestStationCode,
    required this.nearestStationName,
    required this.nearestStationDistanceKm,
    required this.clampedStationDistanceKm,
    required this.inputIntensity,
    required this.processedIntensity,
    required this.multipleSources,
    required this.scannedStationCount,
  });

  final double magnitude;
  final double roundedSourceLatitude;
  final double roundedSourceLongitude;
  final String nearestStationCode;
  final String? nearestStationName;
  final double nearestStationDistanceKm;
  final double clampedStationDistanceKm;
  final double inputIntensity;
  final double processedIntensity;
  final bool multipleSources;
  final int scannedStationCount;

  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'srev_kaizou_magnitude_model': srevKaizouMagnitudeModelId,
    'srev_kaizou_magnitude_source_revision': srevKaizouMagnitudeSourceRevision,
    'srev_kaizou_magnitude_source_project_sha256':
        srevKaizouMagnitudeSourceProjectSha256,
    'srev_kaizou_magnitude_supported': true,
    'srev_kaizou_magnitude': magnitude,
    'srev_kaizou_magnitude_source_latitude_rounded_0_1': roundedSourceLatitude,
    'srev_kaizou_magnitude_source_longitude_rounded_0_1':
        roundedSourceLongitude,
    'srev_kaizou_magnitude_nearest_station_code': nearestStationCode,
    'srev_kaizou_magnitude_nearest_station_name': nearestStationName,
    'srev_kaizou_magnitude_nearest_station_distance_km':
        nearestStationDistanceKm,
    'srev_kaizou_magnitude_clamped_station_distance_km':
        clampedStationDistanceKm,
    'srev_kaizou_magnitude_input_intensity': inputIntensity,
    'srev_kaizou_magnitude_processed_intensity': processedIntensity,
    'srev_kaizou_magnitude_branch': multipleSources
        ? 'multiple_sources_detection_max'
        : 'single_source_global_max',
    'srev_kaizou_magnitude_station_count': scannedStationCount,
    'srev_kaizou_magnitude_distance_weight':
        srevKaizouMagnitudeDistanceWeight(clampedStationDistanceKm),
    'srev_kaizou_magnitude_arithmetic':
        'legacy_plus_min_1_20_over_d_times_'
        '(slope_0_7016_times_processed_plus_0_0903_minus_legacy)',
  };
}

/// Publishes the srev-kaizou magnitude following JMA's report policy.
///
/// JMA の運用（地震火山部『緊急地震速報の概要や処理手法に関する技術的参考資料』
/// 令和6年4月11日改訂 §1 概要）は「震源や M、予測震度の推定精度が良くなるたび
/// に情報を更新して発表する」。EEW の報数は推定が改善するたびに進み、M は
/// 第1報→第2報→…→最終報と更新され続ける（同資料の誤差表でも M は第1報 −0.4
/// → 第2報 +0.3 → 警報 +0.6 → 最終報 +0.4 と、第1報に凍結しない）。また
/// 気象庁マグニチュードは 5 秒周期最大振幅（＝観測のピーク）から求める。
///
/// 旧方針（HYP 報ごとに一度だけ算出し、震源が安定した最初のフレームで凍結）は、
/// 弱イベントの HYP 報が震度ピーク到着前に安定してしまうため、M をその
/// イベントで最も弱いフレームに凍結させていた（実測：紀伊水道 2026-10-13 は
/// 入力震度 0.50 で凍結、ピークは 1.715＝震度2）。
///
/// 本方針は JMA に合わせ、①推定が改善するたびに再公開し（同一 HYP 報の中でも
/// 入力震度が上がれば更新、下がっても後退させない）、②震源安定かつ観測成熟
/// （入力震度が [srevKaizouMagnitudeFinalizeHoldDuration] 以上改善しない）で
/// 確定（最終報相当）する。さらに③確定（ロック）後に新しい報で震源が動いた
/// 場合はロックの根拠（震源安定）が崩れているため、一度解除して新しい震源で
/// 再計算する（宮城県沖 2026-10-13 22:05 の実測：震央が 0.1° 格子で 141.9→141.7
/// へ収束した後も M が 141.9 基準のまま凍結し +0.22 過大だった）。
class SrevKaizouMagnitudePublicationState {
  int? _targetReportNumber;
  int? _publishedReportNumber;
  SrevKaizouMagnitudeResult? _publishedResult;
  /// 公開中の M を導いた**震度ピーク**（単調非減少）。
  /// 気象庁マグニチュードは 5 秒周期の最大振幅（観測ピーク）から求めるため、
  /// 後に震度が下がっても M は後退させない。報や震源格子が変わっても、
  /// ピーク震度は保持したまま **新しい震源** で M を再計算する。
  double _peakInputIntensity = double.negativeInfinity;
  DateTime? _lastImprovementAt;
  int _improvementCount = 0;
  bool _locked = false;
  int? _lockedReportNumber;
  String? _lockReason;

  int? get targetReportNumber => _targetReportNumber;
  int? get publishedReportNumber => _publishedReportNumber;
  SrevKaizouMagnitudeResult? get publishedResult => _publishedResult;
  bool get locked => _locked;
  int? get lockedReportNumber => _lockedReportNumber;
  double? get publishedInputIntensity =>
      _publishedResult == null ? null : _peakInputIntensity;
  int get improvementCount => _improvementCount;
  String? get lockReason => _lockReason;

  /// [observedIntensity] は**このフレームで観測した震度**（保持値）。
  /// 状態はその単調ピークを保持し、[calculate] を **ピーク震度** で呼び直して
  /// 現在の震源格子に対する M を求める。[calculate] は与えられた震度に対する
  /// 震源距離ベースの M を返す。
  SrevKaizouMagnitudeResult? update({
    required int reportNumber,
    required bool stable,
    required DateTime observedAt,
    required double? observedIntensity,
    required SrevKaizouMagnitudeResult? Function(double inputIntensity) calculate,
  }) {
    if (reportNumber <= 0) return null;
    if (_locked && reportNumber == _lockedReportNumber) return _publishedResult;

    _targetReportNumber = reportNumber;

    final improvedPeak =
        observedIntensity != null &&
        observedIntensity.isFinite &&
        observedIntensity > _peakInputIntensity;
    if (improvedPeak) {
      _peakInputIntensity = observedIntensity;
    }
    final result = _peakInputIntensity.isFinite
        ? calculate(_peakInputIntensity)
        : null;

    final sourceCellChanged =
        result != null &&
        _publishedResult != null &&
        _sourceCellDiffers(result, _publishedResult!);

    if (_locked) {
      // ロックの根拠は「震源が安定（同一震源が stableThreshold 連続）かつ観測成熟」。
      // ロック後に震源格子が動いたなら、その根拠は既に崩れている。M の距離項 D は
      // 震源を 0.1° に丸めた格子から最近站距離を取るため、格子が変われば D
      // （ひいては M）が変わる。凍結した M は破棄された震源に基づくので、格子が
      // 変わった時点で一度ロックを解除し、ピーク震度 × 新しい震源で再計算する
      // （＝JMA も最終報まで推定が改善する限り更新を続ける）。
      if (!sourceCellChanged) return _publishedResult;
      _locked = false;
      _lockedReportNumber = null;
      _lockReason = 'reopened_source_cell_changed';
    }

    // JMA：推定精度が良くなるたびに更新する。報ごとに一度ではない。
    // 入力震度がピークを更新したとき、または震源格子が動いたときに再公開する
    // （震度が下がっても M は後退させない＝観測ピークを保持）。
    if (result != null &&
        (_publishedResult == null || improvedPeak || sourceCellChanged)) {
      _publishedReportNumber = reportNumber;
      _publishedResult = result;
      _lastImprovementAt = observedAt;
      _improvementCount += 1;
    }

    // 最終報相当：震源が安定し、かつ観測（入力震度）がホールド期間
    // 改善しなくなって初めて確定する。
    if (stable &&
        _publishedResult != null &&
        _publishedReportNumber == reportNumber) {
      final lastImprovement = _lastImprovementAt;
      final matured =
          lastImprovement == null ||
          observedAt.difference(lastImprovement) >=
              srevKaizouMagnitudeFinalizeHoldDuration;
      if (matured) {
        _locked = true;
        _lockedReportNumber = reportNumber;
        _lockReason = 'stable_and_observation_matured';
      } else {
        _lockReason = 'awaiting_observation_maturity';
      }
    }
    return _publishedResult;
  }

  void copyFrom(SrevKaizouMagnitudePublicationState source) {
    _targetReportNumber = source._targetReportNumber;
    _publishedReportNumber = source._publishedReportNumber;
    _publishedResult = source._publishedResult;
    _peakInputIntensity = source._peakInputIntensity;
    _lastImprovementAt = source._lastImprovementAt;
    _improvementCount = source._improvementCount;
    _locked = source._locked;
    _lockedReportNumber = source._lockedReportNumber;
    _lockReason = source._lockReason;
  }

  Map<String, Object?> toDiagnostics() => <String, Object?>{
    'srev_kaizou_magnitude_target_report_num': _targetReportNumber,
    'srev_kaizou_magnitude_published_report_num': _publishedReportNumber,
    'srev_kaizou_magnitude_locked': _locked,
    'srev_kaizou_magnitude_locked_report_num': _lockedReportNumber,
    'srev_kaizou_magnitude_published_input_intensity':
        _publishedResult == null ? null : _peakInputIntensity,
    'srev_kaizou_magnitude_improvement_count': _improvementCount,
    'srev_kaizou_magnitude_lock_reason': _lockReason,
    'srev_kaizou_magnitude_update_policy':
        'jma_update_on_improvement_or_source_cell_'
        'lock_on_observation_matured',
  };
}

/// 距離項 D を決めるのは震源を 0.1° に丸めた格子なので、その格子が同じか比較する。
bool _sourceCellDiffers(
  SrevKaizouMagnitudeResult a,
  SrevKaizouMagnitudeResult b,
) =>
    a.roundedSourceLatitude != b.roundedSourceLatitude ||
    a.roundedSourceLongitude != b.roundedSourceLongitude;

final List<SrevKaizouMagnitudeStation> srevKaizouScratchStations =
    List<SrevKaizouMagnitudeStation>.unmodifiable(
      List<SrevKaizouMagnitudeStation>.generate(
        srevKaizouScratchStationTable.length,
        (index) {
          final station = srevKaizouScratchStationTable[index];
          return SrevKaizouMagnitudeStation(
            code: 'scratch:${(index + 1).toString().padLeft(4, '0')}',
            latitude: station.latitude,
            longitude: station.longitude,
            name: station.name,
          );
        },
        growable: false,
      ),
    );

double srevKaizouRoundCoordinate(double value) => (value * 10.0).round() / 10.0;

double srevKaizouStationDistanceKm({
  required double roundedSourceLatitude,
  required double roundedSourceLongitude,
  required double stationLatitude,
  required double stationLongitude,
}) {
  final latitudePart = (roundedSourceLatitude - stationLatitude) * 111.2;
  final longitudePart =
      6371.0 *
      (roundedSourceLongitude - stationLongitude) *
      (3.1416 / 180.0) *
      math.cos(
        ((roundedSourceLatitude + stationLatitude) / 2.0) * math.pi / 180.0,
      );
  return math.sqrt(latitudePart * latitudePart + longitudePart * longitudePart);
}

double? srevKaizouScratchConvertedShindo(double rawShindo) {
  if (!rawShindo.isFinite) return null;
  final level = JpShindoScale.levelFromShindo(rawShindo);
  if (level < 0) return null;
  return JpShindoScale.rawShindoFromLevel(level);
}

double srevKaizouProcessedIntensity(
  double inputIntensity, {
  required bool multipleSources,
}) {
  if (multipleSources && inputIntensity > 4.0) {
    return (inputIntensity - 4.0) / 2.0 + 5.0;
  }
  return inputIntensity;
}

double? srevKaizouMagnitudeFromDistanceAndIntensity({
  required double stationDistanceKm,
  required double inputIntensity,
  required bool multipleSources,
}) {
  if (!stationDistanceKm.isFinite ||
      stationDistanceKm <= 0.0 ||
      !inputIntensity.isFinite) {
    return null;
  }
  final processedIntensity = srevKaizouProcessedIntensity(
    inputIntensity,
    multipleSources: multipleSources,
  );
  // 上游等价式 M = (I_proc − 0.94) + 1.73·log10(D)（展开后对 I 的斜率恒为 1.0）。
  // 多语料 LOO 重拟合把斜率改为 slope、截距改为 offset，距离项与钳位保持原样：
  //   raised = slope·I_proc + offset + 1.73·log10(D)
  // 但该重拟合由 D 被钳 20km 的事例主导，故把「相对生产式的抬升量」按 D 条件化：
  //   magnitude = legacy + w(D)·(raised − legacy),  w(D) = min(1, 20/D)
  // w=1（D 触底）时等价于原重拟合式；w→0（远距）时回退到生产式。
  final distanceTerm = 1.73 * (math.log(stationDistanceKm) / math.ln10);
  final legacy =
      (srevKaizouLegacyIntensitySlope * processedIntensity -
          srevKaizouLegacyIntensityOffset) +
      distanceTerm;
  final raised =
      srevKaizouMagnitudeIntensitySlope * processedIntensity +
      srevKaizouMagnitudeIntensityOffset +
      distanceTerm;
  final weight = srevKaizouMagnitudeDistanceWeight(stationDistanceKm);
  final magnitude = legacy + weight * (raised - legacy);
  if (!magnitude.isFinite) return null;
  return magnitude < 0.0 ? 0.0 : magnitude;
}

SrevKaizouMagnitudeResult? calculateSrevKaizouMagnitude({
  required double sourceLatitude,
  required double sourceLongitude,
  required double inputIntensity,
  required bool multipleSources,
  List<SrevKaizouMagnitudeStation>? stations,
}) {
  if (!sourceLatitude.isFinite ||
      !sourceLongitude.isFinite ||
      !inputIntensity.isFinite) {
    return null;
  }
  final stationTable = stations ?? srevKaizouScratchStations;
  if (stationTable.isEmpty) return null;

  final roundedLatitude = srevKaizouRoundCoordinate(sourceLatitude);
  final roundedLongitude = srevKaizouRoundCoordinate(sourceLongitude);
  SrevKaizouMagnitudeStation? nearestStation;
  var nearestDistanceKm = double.infinity;
  for (final station in stationTable) {
    if (!station.latitude.isFinite || !station.longitude.isFinite) continue;
    final distanceKm = srevKaizouStationDistanceKm(
      roundedSourceLatitude: roundedLatitude,
      roundedSourceLongitude: roundedLongitude,
      stationLatitude: station.latitude,
      stationLongitude: station.longitude,
    );
    if (!distanceKm.isFinite || distanceKm >= nearestDistanceKm) continue;
    nearestDistanceKm = distanceKm;
    nearestStation = station;
  }
  if (nearestStation == null || !nearestDistanceKm.isFinite) return null;

  final clampedDistanceKm = math.max(
    nearestDistanceKm,
    srevKaizouMinimumStationDistanceKm,
  );
  final magnitude = srevKaizouMagnitudeFromDistanceAndIntensity(
    stationDistanceKm: clampedDistanceKm,
    inputIntensity: inputIntensity,
    multipleSources: multipleSources,
  );
  if (magnitude == null) return null;

  return SrevKaizouMagnitudeResult(
    magnitude: magnitude,
    roundedSourceLatitude: roundedLatitude,
    roundedSourceLongitude: roundedLongitude,
    nearestStationCode: nearestStation.code,
    nearestStationName: nearestStation.name,
    nearestStationDistanceKm: nearestDistanceKm,
    clampedStationDistanceKm: clampedDistanceKm,
    inputIntensity: inputIntensity,
    processedIntensity: srevKaizouProcessedIntensity(
      inputIntensity,
      multipleSources: multipleSources,
    ),
    multipleSources: multipleSources,
    scannedStationCount: stationTable.length,
  );
}

class SrevKaizouMagnitudeIntensityState {
  SrevKaizouMagnitudeIntensityState({
    this.holdDuration = srevKaizouMaximumShindoHoldDuration,
  });

  final Duration holdDuration;
  final Map<String, _HeldSrevKaizouShindo> _heldByStationCode =
      <String, _HeldSrevKaizouShindo>{};
  DateTime? _lastObservedAt;

  void updateFrame(
    Map<String, double?> currentRawShindoByStationCode, {
    required DateTime observedAt,
  }) {
    final previousObservedAt = _lastObservedAt;
    if (previousObservedAt != null && observedAt.isBefore(previousObservedAt)) {
      clear();
    }
    _lastObservedAt = observedAt;
    _heldByStationCode.removeWhere((_, held) {
      return observedAt.difference(held.updatedAt) > holdDuration;
    });

    for (final entry in currentRawShindoByStationCode.entries) {
      final rawShindo = entry.value;
      if (rawShindo == null) continue;
      final convertedShindo = srevKaizouScratchConvertedShindo(rawShindo);
      if (convertedShindo == null) continue;
      final held = _heldByStationCode[entry.key];
      if (held == null ||
          convertedShindo > held.value ||
          observedAt.difference(held.updatedAt) > holdDuration) {
        _heldByStationCode[entry.key] = _HeldSrevKaizouShindo(
          value: convertedShindo,
          updatedAt: observedAt,
        );
      }
    }
  }

  double? maximumFor(Iterable<String> stationCodes) {
    var maximum = double.negativeInfinity;
    var found = false;
    for (final code in stationCodes) {
      final held = _heldByStationCode[code];
      if (held == null) continue;
      found = true;
      if (held.value > maximum) maximum = held.value;
    }
    return found ? maximum : null;
  }

  void clear() {
    _heldByStationCode.clear();
    _lastObservedAt = null;
  }
}

class _HeldSrevKaizouShindo {
  const _HeldSrevKaizouShindo({required this.value, required this.updatedAt});

  final double value;
  final DateTime updatedAt;
}
