import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../../providers/quake_provider.dart';
import '../../providers/map_state_provider.dart';
import '../../models/intensity_theme.dart';
import '../../models/quake_message.dart';
import '../../models/unified_quake_data.dart';
import '../../models/unified_event_presentation.dart';
import '../../models/weather_alarm.dart';
import '../../core/intensity_calculator.dart';
import '../../core/source_estimation/source_estimate_quality.dart';
import '../../core/source_estimation/source_estimation_models.dart';
import '../../core/source_estimation/source_station_phase_classifier.dart';
import '../../core/source_estimation/station_event_tracker.dart';
import '../../core/utils/quake_time.dart';
import 'ui_scale.dart';

class AlertModule extends StatefulWidget {
  const AlertModule({super.key});

  @override
  State<AlertModule> createState() => _AlertModuleState();
}

class _AlertModuleState extends State<AlertModule> {
  Timer? _unifiedPageTimer;
  Timer? _ashfallWindowTimer;
  final ValueNotifier<double> _flashLevel = ValueNotifier<double>(0);
  int _unifiedPageIndex = 0;
  String _unifiedPageSignature = '';
  static const String _sourceEstimationUnifiedSource = 'nied_source_estimation';
  static const List<String> _jmaShindoLabels = [
    '0',
    '1',
    '2',
    '3',
    '4',
    '5-',
    '5+',
    '6-',
    '6+',
    '7',
  ];
  static const SourceEstimateQualityCalculator _sourceQualityCalculator =
      SourceEstimateQualityCalculator();
  static const SourceStationPhaseClassifier _sourcePhaseClassifier =
      SourceStationPhaseClassifier();
  static const int _unifiedPageSize = 4;

  static const double _refWidth = 1700.0;

  double _scale(BuildContext c) {
    if (UiScale.isPhone(c)) return UiScale.phone(c);
    final w = MediaQuery.of(c).size.width;
    return (w / _refWidth).clamp(0.55, 1.0);
  }

  double _s(double v, BuildContext c) => v * _scale(c);

  /// 获取 EEW 顶栏颜色类
  ///
  /// 参考 kanameishi 的 getBarClass：
  /// - 取消报：深灰
  /// - 警报级 (isWarn)：红色
  /// - 普通：橙色
  Color _eewBarColor(QuakeMessage event) {
    if (event.isCanceled) return const Color(0xFF555555);
    if (event.isWarn) return Colors.red;
    return const Color(0xFFE67E22);
  }

  /// 获取 EEW 顶栏文本颜色
  Color _eewBarTextColor(QuakeMessage event) {
    if (event.isCanceled) return Colors.white54;
    if (event.isWarn) return Colors.redAccent;
    return const Color(0xFFFF9800);
  }

  @override
  void dispose() {
    _stopUnifiedPageTimer();
    _stopAshfallWindowTimer();
    _flashLevel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<QuakeProvider, int>(
      selector: (context, provider) => _alertUiSignature(provider),
      builder: (context, signature, child) {
        return ValueListenableBuilder<SeismicActiveEvent?>(
          valueListenable: StationEventTracker.instance.currentNiedEvent,
          builder: (context, sourceEvent, child) {
            final provider = context.read<QuakeProvider>();
            _syncAshfallWindowTimer(provider.unifiedEvents);
            final showSourceEstimationUi = context
                .watch<MapStateProvider>()
                .showEstimatedEpicenter;
            final sourceUnified = showSourceEstimationUi
                ? _sourceEstimationUnifiedEventV2(sourceEvent)
                : null;
            final unifiedCount =
                provider.unifiedEvents.length + (sourceUnified == null ? 0 : 1);
            final bool hasUnified = unifiedCount > 0;
            final Widget alertContent = _buildAlertContent(
              provider,
              sourceUnified,
            );

            if (!hasUnified) return alertContent;

            final pageIndicator = unifiedCount > _unifiedPageSize
                ? '${_unifiedPageIndex + 1}/${_unifiedPageCount(unifiedCount)}'
                : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: _s(6, context)),
                alertContent,
                SizedBox(height: _s(6, context)),
                _bottomStrip(context, pageText: pageIndicator),
              ],
            );
          },
        );
      },
    );
  }

  int _alertUiSignature(QuakeProvider provider) {
    final unifiedEvents = provider.unifiedEvents;
    return Object.hash(
      Object.hashAll(unifiedEvents.map((event) => event.hashCode)),
      provider.currentUnifiedIndex,
      provider.currentEvent?.hashCode,
      provider.currentDistance,
      provider.estimatedIntensity,
      provider.sCountdown,
      provider.activeWarningCount,
      provider.activeInfoEventCount,
      provider.currentWarningIndex,
      provider.isShowingTempInfo,
      provider.isShowingInfoEvent,
      provider.weatherAlarm?.hashCode,
      provider.shouldShowWeatherAlarm,
    );
  }

  /// 底部分隔条带：双线中间夹页码（如 1/3）
  Widget _bottomStrip(BuildContext context, {String? pageText}) {
    final line = Container(
      width: _s(420, context),
      height: 1,
      color: const Color(0xCC0D0D0D),
    );

    if (pageText == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line,
          SizedBox(height: _s(3, context)),
          line,
        ],
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            line,
            SizedBox(height: _s(3, context)),
            line,
          ],
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: _s(10, context)),
          decoration: BoxDecoration(
            color: const Color(0xCC0D0D0D),
            borderRadius: BorderRadius.circular(_s(4, context)),
          ),
          child: Text(
            pageText,
            style: TextStyle(
              color: Colors.white54,
              fontSize: _s(8, context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertContent(
    QuakeProvider provider,
    UnifiedQuakeData? sourceUnified,
  ) {
    final hasUnified =
        provider.unifiedEvents.isNotEmpty || sourceUnified != null;

    if (hasUnified) {
      _syncFlashController(false);
      return _buildStackedUnifiedView(provider, sourceUnified);
    }

    _stopUnifiedPageTimer();

    final event = provider.currentEvent;
    final warningCount = provider.activeWarningCount;
    final isShowingTempInfo = provider.isShowingTempInfo;
    final isShowingInfoEvent = provider.isShowingInfoEvent;

    if (event == null) {
      _syncFlashController(false);
      if (provider.shouldShowWeatherAlarm) {
        return _buildWeatherAlarmCard(context, provider.weatherAlarm!);
      }
      return _buildStandbyState(context, provider);
    }

    if (isShowingTempInfo || (isShowingInfoEvent && warningCount == 0)) {
      final double intensity = _badgeIntensity(event);
      final Color themeColor = IntensityTheme.getColor(intensity);
      final bool isSerious = intensity >= 5.0;
      final int totalCount = provider.totalDisplayCount;

      _syncFlashController(false);
      return _buildInfoEventCard(
        context,
        event,
        intensity,
        themeColor,
        isSerious,
        totalCount,
        provider,
      );
    }

    final int countdown = provider.sCountdown;
    final double distance = provider.currentDistance;

    if (countdown < -60 && warningCount == 0) {
      _syncFlashController(false);
      return _buildStandbyState(context, provider);
    }

    final double intensity = _badgeIntensity(event);
    final Color themeColor = IntensityTheme.getColor(intensity);
    final bool isSerious = intensity >= 5.0;
    _syncFlashController(isSerious);

    // 有效预警卡（带闪烁边框）渲染分支。
    return AnimatedBuilder(
      animation: _flashLevel,
      builder: (context, child) {
        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_s(10, context)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: _s(420, context),
                decoration: BoxDecoration(
                  color: const Color(0xCC0D0D0D),
                  borderRadius: BorderRadius.circular(_s(10, context)),
                  border: Border.all(
                    color: isSerious
                        ? Color.lerp(
                            Colors.red.withValues(alpha: 0.3),
                            Colors.red.withValues(alpha: 0.9),
                            _flashLevel.value,
                          )!
                        : themeColor.withValues(alpha: 0.35),
                    width: _s(1.2, context),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSerious
                          ? Colors.red.withValues(
                              alpha: _flashLevel.value * 0.3,
                            )
                          : themeColor.withValues(alpha: 0.08),
                      blurRadius: _s(20, context),
                      spreadRadius: _s(1, context),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(
            context,
            event,
            themeColor,
            isSerious,
            warningCount,
            provider,
          ),
          _buildBody(
            context,
            event,
            intensity,
            themeColor,
            countdown,
            distance,
          ),
        ],
      ),
    );
  }

  void _syncFlashController(bool shouldFlash) {
    final next = shouldFlash ? 1.0 : 0.0;
    if (_flashLevel.value != next) {
      _flashLevel.value = next;
    }
  }

  UnifiedQuakeData? _sourceEstimationUnifiedEventV2(
    SeismicActiveEvent? sourceEvent,
  ) {
    final estimate = sourceEvent?.estimate;
    if (sourceEvent == null || estimate == null) return null;

    final isKotoho7Js = estimate.method == 'nied_gif_kotoho7_js_receiver_v1';
    final originTime = estimate.originTime ?? sourceEvent.startedAt;
    final estimatedShindo = isKotoho7Js
        ? (_sourceDiagnosticDouble(
                estimate,
                'js_map_max_shindo_class',
              )?.floor() ??
              -1)
        : sourceEvent.maxShindo;
    final estimatedShindoIndex = _sourceEstimatedJmaIndex(
      sourceEvent,
      estimate,
      isKotoho7Js: isKotoho7Js,
    );
    final supportCount = _sourceDisplaySupportCount(estimate);
    final shindoText = estimatedShindoIndex == null
        ? (estimatedShindo >= 0 ? '$estimatedShindo' : '?')
        : _jmaShindoLabels[estimatedShindoIndex];
    final qualityText =
        _sourceDartHypResultText(estimate) ??
        _sourceJsQualityText(estimate) ??
        '';
    final candidateRegionText = isKotoho7Js
        ? null
        : _sourceCandidateRegionText(sourceEvent.metadata);
    final apiTypeLabel = [
      if (qualityText.isNotEmpty) qualityText,
      ?candidateRegionText,
    ].join(' \u00b7 ');
    final triggerText = _sourceTriggerText(sourceEvent, estimate);

    return UnifiedQuakeData(
      source: _sourceEstimationUnifiedSource,
      origin: originTime.millisecondsSinceEpoch ~/ 1000,
      eventId: sourceEvent.eventId,
      isEew: false,
      timeZone: 9,
      titleText: '\u9707\u6e90\u672c\u5730\u63a8\u7b97',
      reportNumText: '',
      useShindo: true,
      maxIntensity: shindoText,
      className: estimatedShindoIndex == null
          ? _sourceShindoClassName(estimatedShindo)
          : _sourceJmaIndexClassName(estimatedShindoIndex),
      hypocenter:
          '${estimate.latitude.toStringAsFixed(3)}\u00b0N, '
          '${estimate.longitude.toStringAsFixed(3)}\u00b0E',
      originTime: originTime,
      reportTime: sourceEvent.updatedAt,
      magnitude: estimate.magnitude ?? -1,
      depth: estimate.depthKm ?? -1,
      depthText: estimate.depthKm == null
          ? '\u6df1\u5ea6 -- \u00b7 '
                '\u652f\u6301 $supportCount\u7ad9 '
                '\u00b7 ${_sourceMethodLabelV2(estimate.method)}'
          : '\u6df1\u5ea6 ${estimate.depthKm!.round()}km \u00b7 '
                '\u652f\u6301 $supportCount\u7ad9 '
                '\u00b7 ${_sourceMethodLabelV2(estimate.method)}',
      lat: estimate.latitude,
      lng: estimate.longitude,
      isFinal: sourceEvent.isClosed,
      apiTypeLabel: apiTypeLabel,
      warnArea: triggerText,
      arrivedAt: sourceEvent.updatedAt,
    );
  }

  String? _sourceCandidateRegionText(Map<String, Object?> metadata) {
    final candidateRegion = metadata['candidate_region'];
    if (candidateRegion is! Map) return null;
    final allowsCoordinateSwitch =
        candidateRegion['production_coordinate_switch_allowed'] == true;
    if (allowsCoordinateSwitch) return null;
    final status = candidateRegion['status']?.toString();
    final delay = candidateRegion['confirmation_delay_seconds'];
    final delayText = delay is num && delay > 0
        ? ' ${delay.toStringAsFixed(1)}s'
        : '';
    final statusText = switch (status) {
      'pending' => '\u5019\u9009\u533a\u57df \u5f85\u786e\u8ba4',
      'confirmedDelayed' =>
        '\u5019\u9009\u533a\u57df \u5ef6\u8fdf\u786e\u8ba4$delayText',
      'confirmedImmediate' => '\u5019\u9009\u533a\u57df \u5df2\u786e\u8ba4',
      'expired' => null,
      _ => null,
    };
    if (statusText == null) return null;
    final localSupportText = _sourceCandidateLocalSupportText(metadata);
    return localSupportText == null
        ? statusText
        : '$statusText \u00b7 $localSupportText';
  }

  String? _sourceJsQualityText(SourceEstimate estimate) {
    if (estimate.method != 'nied_gif_kotoho7_js_receiver_v1') return null;
    final error = _sourceDiagnosticDouble(estimate, 'best_source_error');
    final support =
        _sourceDiagnosticInt(estimate, 'best_source_applied_count') ??
        _sourceDiagnosticInt(estimate, 'peak_estimated_station_count');
    final processed = _sourceDiagnosticInt(estimate, 'processed_frame_count');
    final detectionIds = _sourceDiagnosticInt(
      estimate,
      'peak_detection_id_count',
    );
    final elapsedMs = _sourceDiagnosticInt(estimate, 'bridge_elapsed_ms');
    final parts = <String>[
      if (error != null) 'JS\u8bef\u5dee ${error.toStringAsFixed(3)}',
      if (support != null) '\u652f\u6301 $support\u7ad9',
      if (processed != null) '\u7b2c$processed\u5e27',
      if (detectionIds != null) 'ID $detectionIds',
      if (elapsedMs != null) '${elapsedMs}ms',
    ];
    return parts.join(' / ');
  }

  String? _sourceDartHypResultText(SourceEstimate estimate) {
    if (estimate.method != 'nied_dart_hyp_v1') return null;
    final errorLevel = _sourceDiagnosticDouble(estimate, 'error_level');
    final qualityRank = estimate.diagnostics['quality_rank']?.toString();
    final parts = <String>[
      if (errorLevel != null) '误差 ${errorLevel.toStringAsFixed(2)}',
      if (qualityRank != null && qualityRank.isNotEmpty) '质量 $qualityRank',
    ];
    return parts.join(' · ');
  }

  String _sourceTriggerText(
    SeismicActiveEvent sourceEvent,
    SourceEstimate estimate,
  ) {
    if (estimate.method == 'nied_dart_hyp_v1') {
      final waveCounts = estimate.diagnostics['wave_counts'];
      if (waveCounts is Map) {
        final p = _nonNegativeSourceCount(waveCounts['P']);
        final s = _nonNegativeSourceCount(waveCounts['S']);
        final other = _nonNegativeSourceCount(waveCounts['O']);
        if (p != null && s != null && other != null) {
          return '触发 ${p + s + other}站 (P: $p | S: $s | O: $other)';
        }
      }
      return '触发数据不可用';
    }

    final phases = _sourcePhaseClassifier.classify(sourceEvent);
    return '触发 ${phases.stations.length}站 '
        '(P: ${phases.count(EstimatedStationPhase.p)} | '
        'S: ${phases.count(EstimatedStationPhase.s)} | '
        'O: ${phases.count(EstimatedStationPhase.other)})';
  }

  int? _nonNegativeSourceCount(Object? value) {
    final parsed = switch (value) {
      int value => value,
      num value when value.isFinite => value.round(),
      String value => int.tryParse(value),
      _ => null,
    };
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  double? _sourceDiagnosticDouble(SourceEstimate estimate, String key) {
    final value = estimate.diagnostics[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _sourceDiagnosticInt(SourceEstimate estimate, String key) {
    final value = estimate.diagnostics[key];
    if (value is int) return value;
    if (value is num && value.isFinite) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  int _sourceDisplaySupportCount(SourceEstimate estimate) {
    if (estimate.method != 'nied_gif_kotoho7_js_receiver_v1') {
      return estimate.supportingStationCount;
    }
    return _sourceDiagnosticInt(estimate, 'best_source_applied_count') ??
        _sourceDiagnosticInt(estimate, 'peak_estimated_station_count') ??
        _sourceDiagnosticInt(estimate, 'js_applied_count') ??
        0;
  }

  String? _sourceCandidateLocalSupportText(Map<String, Object?> metadata) {
    final gate = metadata['candidate_region_local_support_gate'];
    if (gate is! Map) return null;
    final memberCount = gate['member_count'];
    final memberGrowth = gate['member_count_growth'];
    final estimateMemberDistance = gate['estimate_member_centroid_distance_km'];
    final convergence = gate['convergence_km'];
    if (memberCount is! num) return null;

    final growthText = memberGrowth is num
        ? ' ${_formatSignedSourceCount(memberGrowth.round())}'
        : '';
    final distanceText = estimateMemberDistance is num
        ? ' / ${estimateMemberDistance.round()}km'
        : '';
    final convergenceText = convergence is num
        ? ' / \u6536\u655b${convergence.round()}km'
        : '';
    return '\u672c\u5730\u652f\u6301 ${memberCount.round()}\u7ad9'
        '$growthText$distanceText$convergenceText';
  }

  String _formatSignedSourceCount(int value) {
    if (value > 0) return '+$value';
    return '$value';
  }

  String _sourceShindoClassName(int shindo) {
    if (shindo >= 7) return 'purple';
    if (shindo >= 6) return 'red';
    if (shindo >= 5) return 'orange';
    if (shindo >= 4) return 'yellow';
    if (shindo >= 3) return 'green';
    if (shindo >= 2) return 'blue';
    if (shindo >= 1) return 'gray';
    if (shindo == 0) return 'dark-gray';
    return 'gray';
  }

  int? _sourceEstimatedJmaIndex(
    SeismicActiveEvent sourceEvent,
    SourceEstimate estimate, {
    required bool isKotoho7Js,
  }) {
    final raw = isKotoho7Js
        ? estimate.diagnostics['js_map_max_shindo_index']
        : sourceEvent.metadata['nied_max_jma_shindo_index'];
    final index = switch (raw) {
      int value => value,
      num value => value.round(),
      String value => int.tryParse(value),
      _ => null,
    };
    return index != null && index >= 0 && index < _jmaShindoLabels.length
        ? index
        : null;
  }

  String _sourceJmaIndexClassName(int index) {
    if (index >= 9) return 'purple';
    if (index >= 8) return 'dark-red';
    if (index >= 7) return 'red';
    if (index >= 6) return 'dark-orange';
    if (index >= 5) return 'orange';
    if (index >= 4) return 'yellow';
    if (index >= 3) return 'green';
    if (index >= 2) return 'blue';
    if (index >= 1) return 'gray';
    return 'dark-gray';
  }

  String _sourceMethodLabelV2(String method) => switch (method) {
    'nied_gif_kotoho7_js_receiver_v1' => 'kotoho7 JS',
    'nied_dart_hyp_v1' => 'Dart HYP',
    'nied_gif_hybrid_v1' => 'GIF\u6df7\u5408',
    'trigger_time_grid_v2' => '\u5230\u65f6\u7f51\u683c',
    'trigger_time_depth_grid_v3' => '\u6df1\u5ea6\u7f51\u683c',
    'weighted_centroid_baseline' => '\u52a0\u6743\u8d28\u5fc3',
    _ => method,
  };

  UnifiedQuakeData? sourceEstimationUnifiedEventLegacy(
    SeismicActiveEvent? sourceEvent,
  ) {
    final estimate = sourceEvent?.estimate;
    if (sourceEvent == null || estimate == null) return null;

    final quality = _sourceQualityCalculator.calculate(sourceEvent);
    final phases = _sourcePhaseClassifier.classify(sourceEvent);
    final reportNumber = _sourceEstimationReportNumber(sourceEvent, estimate);
    final originTime = estimate.originTime ?? sourceEvent.startedAt;
    final grade = quality?.grade ?? '?';
    final qualityText = quality == null
        ? '质量 --'
        : '质量 ${quality.grade} - '
              '${(quality.confidence * 100).toStringAsFixed(1)}% / '
              '${_formatSourceResidual(quality.rmsResidualSeconds)} / '
              '${_formatSourceGap(quality.azimuthalGapDegrees)} / '
              '${_formatSourceUncertainty(quality.horizontalUncertaintyP90Km)}';
    final triggerText =
        '触发 ${phases.stations.length}站 '
        '(P: ${phases.count(EstimatedStationPhase.p)} | '
        'S: ${phases.count(EstimatedStationPhase.s)} | '
        'O: ${phases.count(EstimatedStationPhase.other)})';

    return UnifiedQuakeData(
      source: _sourceEstimationUnifiedSource,
      origin: originTime.millisecondsSinceEpoch ~/ 1000,
      eventId: sourceEvent.eventId,
      isEew: false,
      timeZone: 9,
      titleText: '震源本地推算',
      reportNumText: '第$reportNumber报',
      useShindo: false,
      maxIntensity: grade,
      className: _sourceQualityClass(grade),
      hypocenter:
          '${estimate.latitude.toStringAsFixed(3)}°N, '
          '${estimate.longitude.toStringAsFixed(3)}°E',
      originTime: originTime,
      reportTime: sourceEvent.updatedAt,
      magnitude: estimate.magnitude ?? -1,
      depth: estimate.depthKm ?? -1,
      depthText: estimate.depthKm == null
          ? '深度 -- · 支持 ${estimate.supportingStationCount}站 · '
                '${_sourceMethodLabel(estimate.method)}'
          : '深度 ${estimate.depthKm!.round()}km · '
                '支持 ${estimate.supportingStationCount}站 · '
                '${_sourceMethodLabel(estimate.method)}',
      lat: estimate.latitude,
      lng: estimate.longitude,
      isFinal: sourceEvent.isClosed,
      apiTypeLabel: qualityText,
      warnArea: triggerText,
      arrivedAt: sourceEvent.updatedAt,
    );
  }

  bool _isSourceEstimationUnified(UnifiedQuakeData event) =>
      event.source == _sourceEstimationUnifiedSource;

  int _sourceEstimationReportNumber(
    SeismicActiveEvent sourceEvent,
    SourceEstimate estimate,
  ) {
    final metadataReport = _positiveInt(
      sourceEvent.metadata['kotoho7_js_receiver_report_number'],
    );
    if (metadataReport != null) return metadataReport;

    final processedFrameCount = _positiveInt(
      estimate.diagnostics['processed_frame_count'],
    );
    if (processedFrameCount != null) return processedFrameCount;

    final historyFrameCount = _positiveInt(
      estimate.diagnostics['history_frame_count'],
    );
    if (historyFrameCount != null) return historyFrameCount;

    final revision = sourceEvent.metadata['estimate_revision'];
    return revision is int && revision > 0 ? revision : 1;
  }

  int? _positiveInt(Object? value) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  String _sourceQualityClass(String grade) => switch (grade) {
    'S' || 'A' => 'green',
    'B' => 'yellow',
    'C' => 'orange',
    _ => 'red',
  };

  String _formatSourceResidual(double? value) =>
      value == null ? '--s' : '${value.toStringAsFixed(2)}s';

  String _formatSourceGap(double? value) =>
      value == null ? '--°' : '${value.round()}°';

  String _formatSourceUncertainty(double? value) =>
      value == null ? 'P90 --km' : 'P90 ${value.round()}km';

  String _sourceMethodLabel(String method) => switch (method) {
    'nied_dart_hyp_v1' => 'Dart HYP',
    'nied_gif_hybrid_v1' => 'GIF混合',
    'trigger_time_grid_v2' => '到时网格',
    'trigger_time_depth_grid_v3' => '深度网格',
    'weighted_centroid_baseline' => '加权质心',
    _ => method,
  };

  Widget _buildStackedUnifiedView(
    QuakeProvider provider,
    UnifiedQuakeData? sourceUnified,
  ) {
    final events = [...provider.unifiedEvents, ?sourceUnified];
    final eew = events.where((e) => e.isEew).toList();
    final info = events.where((e) => !e.isEew).toList();
    final ordered = [...eew, ...info];
    final visibleEvents = _visibleUnifiedPage(ordered);

    // 轮播模式：每页固定 _unifiedPageSize 槽位，不足用 null 占位，防止高度跳动
    final paddedEvents = ordered.length > _unifiedPageSize
        ? [
            ...visibleEvents,
            for (int i = visibleEvents.length; i < _unifiedPageSize; i++) null,
          ]
        : visibleEvents;

    final slotHeight = _compactUnifiedSlotHeight(context);

    return SizedBox(
      width: _s(420, context),
      child: KeyedSubtree(
        key: ValueKey(
          'unified_page_${_unifiedPageIndex}_${visibleEvents.map((e) => '${e.source}:${e.eventId}:${e.reportNumText}').join('|')}',
        ),
        child: _buildCardColumn(paddedEvents, slotHeight),
      ),
    );
  }

  List<UnifiedQuakeData> _visibleUnifiedPage(List<UnifiedQuakeData> ordered) {
    _syncUnifiedPagination(ordered);

    if (ordered.length <= _unifiedPageSize) {
      return ordered;
    }

    final pageCount = _unifiedPageCount(ordered.length);
    final pageIndex = _unifiedPageIndex.clamp(0, pageCount - 1);
    final start = pageIndex * _unifiedPageSize;
    final end = (start + _unifiedPageSize).clamp(0, ordered.length);
    return ordered.sublist(start, end);
  }

  void _syncUnifiedPagination(List<UnifiedQuakeData> ordered) {
    final signature = ordered
        .map(
          (e) =>
              '${e.source}:${e.eventId}:${e.reportNumText}:${e.arrivedAt?.millisecondsSinceEpoch ?? 0}',
        )
        .join('|');

    if (signature != _unifiedPageSignature) {
      _unifiedPageSignature = signature;
      _unifiedPageIndex = 0;
    }

    if (ordered.length <= _unifiedPageSize) {
      _stopUnifiedPageTimer();
      _unifiedPageIndex = 0;
      return;
    }

    final pageCount = _unifiedPageCount(ordered.length);
    if (_unifiedPageIndex >= pageCount) {
      _unifiedPageIndex = pageCount - 1;
    }

    if (_unifiedPageTimer?.isActive == true) return;
    _unifiedPageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final showSourceEstimationUi = context
          .read<MapStateProvider>()
          .showEstimatedEpicenter;
      final sourceUnified = showSourceEstimationUi
          ? _sourceEstimationUnifiedEventV2(
              StationEventTracker.instance.currentNiedEvent.value,
            )
          : null;
      final count =
          context.read<QuakeProvider>().unifiedEvents.length +
          (sourceUnified == null ? 0 : 1);
      final nextPageCount = _unifiedPageCount(count);
      if (nextPageCount <= 1) {
        _stopUnifiedPageTimer();
        if (mounted) {
          setState(() {
            _unifiedPageIndex = 0;
          });
        }
        return;
      }
      setState(() {
        _unifiedPageIndex = (_unifiedPageIndex + 1) % nextPageCount;
      });
    });
  }

  int _unifiedPageCount(int itemCount) {
    return (itemCount / _unifiedPageSize).ceil();
  }

  void _stopUnifiedPageTimer() {
    _unifiedPageTimer?.cancel();
    _unifiedPageTimer = null;
  }

  void _syncAshfallWindowTimer(List<UnifiedQuakeData> events) {
    final needsRefresh = events.any(
      (event) => event.volcanoEvent?.hasAshfallForecast ?? false,
    );
    if (!needsRefresh) {
      _stopAshfallWindowTimer();
      return;
    }
    _ashfallWindowTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopAshfallWindowTimer() {
    _ashfallWindowTimer?.cancel();
    _ashfallWindowTimer = null;
  }

  double _compactUnifiedSlotHeight(BuildContext context) {
    return _s(148, context);
  }

  Widget _buildCardColumn(List<UnifiedQuakeData?> events, double slotHeight) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: events.asMap().entries.map((entry) {
        final event = entry.value;
        final isLast = entry.key == events.length - 1;

        // 透明占位：保持每页固定高度，防止列表跳动
        if (event == null) {
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : _s(4, context)),
            child: SizedBox(height: slotHeight),
          );
        }

        final card = _buildCompactUnifiedCard(event);
        return Padding(
          key: ValueKey(
            'unified_card_${event.source}_${event.eventId}_${event.reportNumText}',
          ),
          padding: EdgeInsets.only(bottom: isLast ? 0 : _s(4, context)),
          child: SizedBox(height: slotHeight, child: card),
        );
      }).toList(),
    );
  }

  Widget _buildCompactUnifiedCard(UnifiedQuakeData event) {
    final color = _uicColorFromClass(event.className);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_s(10, context)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xCC0D0D0D),
              borderRadius: BorderRadius.circular(_s(10, context)),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: _s(1.2, context),
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: _s(20, context),
                  spreadRadius: _s(1, context),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactTopBar(event),
                _buildCompactBottomSection(event),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTopBar(UnifiedQuakeData event) {
    final color = _uicColorFromClass(event.className);
    final presentation = UnifiedEventPresentation.fromEvent(event);
    return Container(
      height: _s(32, context),
      decoration: BoxDecoration(
        color: color.withAlpha(200),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: _s(10, context)),
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: _s(8, context)),
          Expanded(
            child: Text(
              presentation.title,
              style: TextStyle(
                color: Colors.white,
                fontSize: _s(12.5, context),
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: _s(10, context)),
        ],
      ),
    );
  }

  Widget _buildCompactBottomSection(UnifiedQuakeData event) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _s(10, context),
        vertical: _s(6, context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildCompactBadge(event),
          SizedBox(width: _s(12, context)),
          Expanded(child: _buildCompactInfoColumn(event)),
        ],
      ),
    );
  }

  Widget _buildSourceEstimationBadge(UnifiedQuakeData event, Color color) {
    return _buildUnifiedListStyleBadge(
      color: color,
      value: event.maxIntensity,
      label: '检出震度',
      useShindo: true,
    );
  }

  Widget _buildCompactBadge(UnifiedQuakeData event) {
    final color = _uicColorFromClass(event.className);
    if (_isSourceEstimationUnified(event)) {
      return _buildSourceEstimationBadge(event, color);
    }
    if (event.isVolcanoEvent) {
      return _buildVolcanoBadge(color);
    }

    final presentation = UnifiedEventPresentation.fromEvent(event);
    return _buildUnifiedListStyleBadge(
      color: color,
      value: presentation.intensityValue,
      label: presentation.intensityLabel,
      useShindo: event.useShindo,
    );
  }

  Widget _buildVolcanoBadge(Color color) {
    return Container(
      width: _s(72, context),
      height: _s(72, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_s(10, context)),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_fire_department,
            size: _s(34, context),
            color: color,
          ),
          Text(
            '火山',
            style: TextStyle(
              fontSize: _s(10.5, context),
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedListStyleBadge({
    required Color color,
    required String value,
    required String label,
    required bool useShindo,
  }) {
    final hasShindoSuffix =
        useShindo &&
        value.length > 1 &&
        (value.contains('+') ||
            value.contains('-') ||
            value.contains('弱') ||
            value.contains('強'));
    final mainLabel = hasShindoSuffix ? value.substring(0, 1) : value;
    final suffixLabel = hasShindoSuffix ? value.substring(1) : '';

    return Container(
      width: _s(72, context),
      height: _s(72, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_s(10, context)),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasShindoSuffix)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mainLabel,
                  style: TextStyle(
                    fontSize: _s(34, context),
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.0,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: _s(1, context)),
                  child: Text(
                    suffixLabel,
                    style: TextStyle(
                      fontSize: _s(24, context),
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                mainLabel,
                style: TextStyle(
                  fontSize: useShindo ? _s(29, context) : _s(34, context),
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.0,
                ),
              ),
            ),
          Text(
            label,
            style: TextStyle(
              fontSize: _s(10.5, context),
              color: color.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoColumn(UnifiedQuakeData event) {
    if (_isSourceEstimationUnified(event)) {
      final timeStr = _formatUnifiedEventClock(event);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.hypocenter,
            style: TextStyle(
              color: Colors.white,
              fontSize: _s(14.5, context),
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: _s(3, context)),
          Text(
            event.depthText,
            style: TextStyle(
              color: Colors.white70,
              fontSize: _s(12, context),
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: _s(3, context)),
          Text(
            '$timeStr  ${event.apiTypeLabel}',
            style: TextStyle(
              color: Colors.white54,
              fontSize: _s(11, context),
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: _s(2, context)),
          Text(
            event.warnArea,
            style: TextStyle(
              color: const Color(0xFF72F5B2),
              fontSize: _s(10, context),
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    final presentation = UnifiedEventPresentation.fromEvent(event);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          presentation.primaryText,
          style: TextStyle(
            color: Colors.white,
            fontSize: _s(14.5, context),
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: _s(3, context)),
        Text(
          presentation.secondaryText,
          style: TextStyle(
            color: Colors.white70,
            fontSize: _s(12, context),
            fontWeight: FontWeight.w600,
          ),
          maxLines: event.isVolcanoEvent ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: _s(3, context)),
        Text(
          presentation.timeText,
          style: TextStyle(
            color: Colors.white54,
            fontSize: _s(11, context),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (presentation.apiTypeLabel.isNotEmpty) ...[
          SizedBox(height: _s(2, context)),
          Text(
            presentation.apiTypeLabel,
            style: TextStyle(
              color: Colors.white38,
              fontSize: _s(9, context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  String _formatUnifiedEventClock(UnifiedQuakeData event) {
    final originTime = event.originTime;
    if (originTime == null) return '--:--:--';
    final sourceClock = originTime.toUtc().add(Duration(hours: event.timeZone));
    return sourceClock
        .toIso8601String()
        .substring(5, 19)
        .replaceFirst('T', ' ');
  }

  Color _uicColorFromClass(String className) {
    switch (className) {
      case 'purple':
        return const Color(0xFF7F007F);
      case 'dark-red':
        return const Color(0xFFAF0000);
      case 'red':
        return const Color(0xFFDF0F0F);
      case 'dark-orange':
        return const Color(0xFFFF4F00);
      case 'orange':
        return const Color(0xFFFF8F00);
      case 'yellow':
        return const Color(0xFFF7E757);
      case 'green':
        return const Color(0xFF5FDF8F);
      case 'blue':
        return const Color(0xFF3FAFFF);
      case 'sky-blue':
        return const Color(0xFF5FCFFF);
      case 'dark-gray':
        return const Color(0xFF9F9F9F);
      case 'gray':
      default:
        return const Color(0xFFCFCFCF);
    }
  }

  Widget _buildWeatherAlarmCard(BuildContext context, WeatherAlarm alarm) {
    final themeColor = alarm.levelColor;
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_s(10, context)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: _s(420, context),
            decoration: BoxDecoration(
              color: const Color(0xCC0D0D0D),
              borderRadius: BorderRadius.circular(_s(10, context)),
              border: Border.all(
                color: themeColor.withValues(alpha: 0.3),
                width: _s(1.2, context),
              ),
              boxShadow: [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.1),
                  blurRadius: _s(20, context),
                  spreadRadius: _s(1, context),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildWeatherHeader(context, alarm),
                _buildWeatherBody(context, alarm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherHeader(BuildContext context, WeatherAlarm alarm) {
    final themeColor = alarm.levelColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(16, context),
        vertical: _s(6, context),
      ),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
        border: Border(
          bottom: BorderSide(
            color: themeColor.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: themeColor,
              boxShadow: [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.6),
                  blurRadius: _s(4, context),
                ),
              ],
            ),
          ),
          SizedBox(width: _s(10, context)),
          Expanded(
            child: Text(
              '中国气象局气象预警',
              style: TextStyle(
                fontSize: _s(12, context),
                fontWeight: FontWeight.w700,
                color: themeColor,
                letterSpacing: _s(1.5, context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherBody(BuildContext context, WeatherAlarm alarm) {
    final themeColor = alarm.levelColor;
    final disasterType = alarm.disasterType;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _s(16, context),
        _s(10, context),
        _s(16, context),
        _s(12, context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: _s(48, context),
                height: _s(48, context),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(_s(8, context)),
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.4),
                    width: _s(1.2, context),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  alarm.levelLabel,
                  style: TextStyle(
                    fontSize: _s(16, context),
                    fontWeight: FontWeight.w900,
                    color: themeColor,
                  ),
                ),
              ),
              SizedBox(width: _s(12, context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (disasterType.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: _s(6, context),
                          vertical: _s(1, context),
                        ),
                        margin: EdgeInsets.only(bottom: _s(4, context)),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(_s(3, context)),
                        ),
                        child: Text(
                          disasterType,
                          style: TextStyle(
                            fontSize: _s(9, context),
                            color: themeColor.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Text(
                      alarm.headline,
                      style: TextStyle(
                        fontSize: _s(15, context),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: _s(8, context)),
          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: _s(12, context),
                color: Colors.white38,
              ),
              SizedBox(width: _s(6, context)),
              Text(
                alarm.effective,
                style: TextStyle(
                  fontSize: _s(12, context),
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandbyState(BuildContext context, QuakeProvider provider) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_s(10, context)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: _s(420, context),
            padding: EdgeInsets.symmetric(vertical: _s(39, context)),
            decoration: BoxDecoration(
              color: const Color(0xCC0D0D0D),
              borderRadius: BorderRadius.circular(_s(10, context)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
            child: Center(
              child: Text(
                '当前无预警信息',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: _s(14, context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    QuakeMessage event,
    Color themeColor,
    bool isSerious,
    int warningCount,
    QuakeProvider provider,
  ) {
    final sourceLabel = _sourceLabel(event, includeProvince: true);
    final barColor = _eewBarColor(event);
    final barTextColor = _eewBarTextColor(event);
    final titleText = event.isCanceled
        ? '${_safeWarningLabel(event)} (已取消)'
        : '${_safeWarningLabel(event)}${event.reportNumText != null ? ' ${event.reportNumText}' : ''}';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(16, context),
        vertical: _s(6, context),
      ),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
        border: Border(
          bottom: BorderSide(
            color: barColor.withValues(alpha: 0.25),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: barColor,
              boxShadow: [
                BoxShadow(
                  color: barColor.withValues(alpha: 0.6),
                  blurRadius: _s(4, context),
                ),
              ],
            ),
          ),
          SizedBox(width: _s(10, context)),
          Expanded(
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: _s(12, context),
                fontWeight: FontWeight.w700,
                color: barTextColor,
                letterSpacing: _s(1.5, context),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (warningCount > 1) ...[
            _buildCarouselNav(context, provider, warningCount, barColor),
            SizedBox(width: _s(6, context)),
          ],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _s(6, context),
              vertical: _s(2, context),
            ),
            decoration: BoxDecoration(
              color: barColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(_s(4, context)),
              border: Border.all(
                color: barColor.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _s(98, context)),
              child: Text(
                sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _s(10, context),
                  color: barColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: _s(0.5, context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarouselNav(
    BuildContext context,
    QuakeProvider provider,
    int total,
    Color themeColor,
  ) {
    final current = provider.currentWarningIndex + 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: provider.prevWarning,
          child: Icon(
            Icons.chevron_left,
            size: _s(14, context),
            color: themeColor.withValues(alpha: 0.7),
          ),
        ),
        Text(
          '$current/$total',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: _s(10, context),
            color: themeColor.withValues(alpha: 0.8),
            fontWeight: FontWeight.w700,
          ),
        ),
        GestureDetector(
          onTap: provider.nextWarning,
          child: Icon(
            Icons.chevron_right,
            size: _s(14, context),
            color: themeColor.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    QuakeMessage event,
    double intensity,
    Color themeColor,
    int countdown,
    double distance,
  ) {
    final double localIntensity = IntensityCalculator.calculate(
      mag: event.magnitude,
      distance: distance,
    );
    final displayTime = QuakeTime.displayClock(event);
    final displayTimeText =
        '${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')}:${displayTime.second.toString().padLeft(2, '0')} ${QuakeTime.zoneLabel(event)}';
    final reportText = _reportText(event);
    final useShindoBadge = _useShindo(event);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _s(16, context),
        _s(10, context),
        _s(16, context),
        _s(10, context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (useShindoBadge && event.jmaShindo != null)
                _buildShindoBadge(context, event.jmaShindo!, themeColor)
              else
                _buildIntensityBadge(context, intensity, themeColor),
              SizedBox(width: _s(12, context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.location,
                      style: TextStyle(
                        fontSize: _s(18, context),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: _s(4, context)),
                    Text(
                      'M${event.magnitude.toStringAsFixed(1)}  ·  深度 ${event.depth.toStringAsFixed(0)} km',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: _s(12, context),
                      ),
                    ),
                    SizedBox(height: _s(4, context)),
                    Wrap(
                      spacing: _s(6, context),
                      runSpacing: _s(4, context),
                      children: [
                        _metaChip(
                          context,
                          Icons.access_time,
                          '发震 $displayTimeText',
                        ),
                        _metaChip(context, Icons.receipt_long, reportText),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: _s(8, context)),
          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Text(
                'S 娉㈡姷杈? ',
                style: TextStyle(
                  fontSize: _s(12, context),
                  color: Colors.white54,
                ),
              ),
              Expanded(
                child: Text(
                  countdown > 0
                      ? '${countdown.toString().padLeft(2, '0')} 秒'
                      : '已到达',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: _s(22, context),
                    fontWeight: FontWeight.w900,
                    color: countdown > 0 ? themeColor : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Text(
                '鏈湴鐑堝害  ',
                style: TextStyle(
                  fontSize: _s(10, context),
                  color: Colors.white38,
                ),
              ),
              Text(
                '${localIntensity.toStringAsFixed(2)} 度',
                style: TextStyle(
                  fontSize: _s(14, context),
                  fontWeight: FontWeight.w700,
                  color: IntensityTheme.getColor(localIntensity),
                ),
              ),
            ],
          ),
          SizedBox(height: _s(6, context)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: _s(6, context)),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(_s(6, context)),
              border: Border.all(
                color: themeColor.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: Text(
              IntensityTheme.getAction(intensity),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeColor,
                fontSize: _s(12, context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _safeWarningLabel(QuakeMessage event) {
    try {
      return event.source.warningLabel;
    } catch (_) {
      return '鍦伴渿棰勮';
    }
  }

  /// 判断是否使用 JMA 震度显示
  bool _useShindo(QuakeMessage event) {
    return event.jmaShindo != null && event.jmaShindo!.isNotEmpty;
  }

  bool _isScalePrompt(QuakeMessage event) => event.infoTypeName == '震度速報';

  String _infoEventMaxIntensityText(
    QuakeMessage event,
    double intensity,
    bool useShindo,
  ) {
    if (useShindo) {
      final shindo = event.jmaShindo?.trim();
      if (shindo != null && shindo.isNotEmpty && shindo != '-') {
        return '最大震度 $shindo';
      }
      return '最大震度: 不明';
    }
    return '预估最大烈度 ${intensity.toStringAsFixed(2)}';
  }

  /// 生成信息事件标题
  ///
  /// 参考 kanameishi 的 setEqMessage 标题生成逻辑
  String _infoEventTitle(QuakeMessage event) {
    switch (event.source) {
      case QuakeSourceType.cenc:
        return '中国地震台网地震信息';
      case QuakeSourceType.cencIr:
        return '中国地震台网烈度速报';
      case QuakeSourceType.usgs:
        final rt = event.reviewType;
        if (rt == 'reviewed' || rt == '正式测定') return 'USGS正式测定';
        if (rt != null) return 'USGS自动测定';
        return 'USGS測定';
      case QuakeSourceType.fssn:
        final rt = event.reviewType;
        if (rt == '正式(已核实)') return 'FSSN正式测定';
        if (rt == '已确认') return 'FSSN自动测定';
        return 'FSSN地震报告';
      case QuakeSourceType.fssnCmt:
        return 'FSSN 地震矩心矩张量解';
      case QuakeSourceType.cencCmt:
        return 'CENC 地震矩心矩张量解';
      case QuakeSourceType.usgsCmt:
        return 'USGS 地震矩心矩张量解';
      case QuakeSourceType.jmaCmt:
        return 'JMA 地震矩心矩张量解';
      case QuakeSourceType.fnetCmt:
        return 'F-net 地震矩心矩张量解';
      case QuakeSourceType.hinetAquaCmt:
        return 'Hi-net AQUA 地震矩心矩张量解';
      case QuakeSourceType.hko:
        final verify = event.verify;
        if (verify == 'Y') return '香港天文台已核实';
        if (verify == 'N') return '香港天文台初步报告';
        return '香港天文台地震报告';
      case QuakeSourceType.emsc:
        return '欧洲地中海地震中心';
      case QuakeSourceType.bcsf:
        return '法国中央地震研究所';
      case QuakeSourceType.gfz:
        return '德国地学研究中心';
      case QuakeSourceType.usp:
        return '巴西圣保罗大学';
      case QuakeSourceType.kma_eq:
        return '기상청 지진 정보';
      case QuakeSourceType.ningxia:
        return '宁夏地震局';
      case QuakeSourceType.guangxi:
        return '广西地震局';
      case QuakeSourceType.shanxi:
        return '山西地震局';
      case QuakeSourceType.beijing:
        return '北京地震局';
      case QuakeSourceType.yunnan:
        return '云南地震局';
      case QuakeSourceType.bmkg:
        return '印度尼西亚气象气候与地球物理局';
      case QuakeSourceType.geonet:
        return '新西兰 GeoNet';
      case QuakeSourceType.tmd:
        return '泰国气象局';
      case QuakeSourceType.ingv:
        return '意大利国家地球物理与火山学研究所';
      case QuakeSourceType.nrcan:
        return '加拿大自然资源部';
      case QuakeSourceType.mmd:
        return '马来西亚气象局';
      case QuakeSourceType.phivolcs:
        return '菲律宾火山与地震研究所';
      case QuakeSourceType.cwa:
      case QuakeSourceType.cwa_eew:
        return '中央氣象署地震報告';
      case QuakeSourceType.wolfx:
      case QuakeSourceType.p2p:
      case QuakeSourceType.jma_fan:
        return event.infoTypeName ?? '鍦伴渿鎯呭牨';
      default:
        return '鍦伴渿鎯呭牨';
    }
  }

  /// 获取数据源类型标签
  ///
  /// 参考 kanameishi 的 sourceTypes 映射
  String _sourceTypeLabel(QuakeMessage event) {
    if (event.source == QuakeSourceType.wolfx) return 'Wolfx';
    if (event.source == QuakeSourceType.p2p) return 'P2PQ';
    if (event.source == QuakeSourceType.jma_fan) return 'FAN';
    if (event.source == QuakeSourceType.cwa ||
        event.source == QuakeSourceType.cwa_eew) {
      return 'FAN';
    }
    if (event.source == QuakeSourceType.cenc) return 'FAN';
    if (event.source == QuakeSourceType.cencIr) return 'NowQuake';
    if (event.source == QuakeSourceType.fssn ||
        event.source == QuakeSourceType.fssnCmt) {
      return 'FAN';
    }
    if (event.source == QuakeSourceType.usgs) return 'FAN';
    if (event.source == QuakeSourceType.hinetAquaCmt) return 'Hi-net';
    if (event.source == QuakeSourceType.hko) return 'FAN';
    if (event.source == QuakeSourceType.emsc) return 'FAN';
    if (event.source == QuakeSourceType.bcsf) return 'FAN';
    if (event.source == QuakeSourceType.gfz) return 'FAN';
    if (event.source == QuakeSourceType.usp) return 'FAN';
    if (event.source == QuakeSourceType.bmkg ||
        event.source == QuakeSourceType.geonet ||
        event.source == QuakeSourceType.tmd ||
        event.source == QuakeSourceType.ingv ||
        event.source == QuakeSourceType.nrcan ||
        event.source == QuakeSourceType.mmd ||
        event.source == QuakeSourceType.phivolcs) {
      return 'WHEWS';
    }
    if (event.source == QuakeSourceType.kma_eq ||
        event.source == QuakeSourceType.kma_eew_fan) {
      return 'KMA';
    }
    if (event.source == QuakeSourceType.sa) return 'FAN';
    return '';
  }

  /// 获取徽章烈度/震度值
  ///
  /// 优先级：API 原始值 > 当地标准震中(距离=0)公式
  /// 注意：本方法不用于"本地烈度"行，本地烈度在 _buildBody 中单独计算
  double _badgeIntensity(QuakeMessage event) {
    if (event.maxIntensity != null) {
      return event.maxIntensity!.clamp(0.0, 12.0).toDouble();
    }

    // 无 API 值：按当地标准计算震中(距离=0)烈度
    switch (event.source) {
      case QuakeSourceType.cenc:
      case QuakeSourceType.cencIr:
      case QuakeSourceType.cea:
      case QuakeSourceType.cea_pr:
      case QuakeSourceType.sc_eew:
      case QuakeSourceType.fj_eew:
      case QuakeSourceType.cq_eew:
      case QuakeSourceType.sa:
        return IntensityCalculator.calcCsisLevel(
          event.magnitude,
          event.depth,
          0,
        ).toDouble();
      case QuakeSourceType.cwa_eew:
      case QuakeSourceType.cwa:
        return IntensityCalculator.calcCwbLevel(
          event.magnitude,
          event.depth,
          0,
        ).toDouble();
      default:
        // JMA 公式计算震中震度 (distance=1 最小值)
        return IntensityCalculator.calculate(mag: event.magnitude, distance: 1);
    }
  }

  Widget _buildIntensityBadge(
    BuildContext context,
    double intensity,
    Color color,
  ) {
    return Container(
      width: _s(58, context),
      height: _s(64, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: _s(1.2, context),
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: _s(3, context),
          horizontal: _s(2, context),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                intensity >= 0 ? intensity.toStringAsFixed(2) : '?',
                style: TextStyle(
                  fontSize: _s(22, context),
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.0,
                ),
              ),
            ),
            SizedBox(height: _s(1, context)),
            Text(
              '浼版祴鐑堝害',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _s(8, context),
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建震度徽章
  ///
  /// 用于显示 JMA 震度 (如 "5-", "6+", "7")
  /// 参考 kanameishi 的 shindo 显示样式
  Widget _buildShindoBadge(BuildContext context, String shindo, Color color) {
    final display = shindo;
    final mainChar = display.isNotEmpty ? display[0] : '?';
    final subChar = display.length > 1 ? display.substring(1) : '';

    return Container(
      width: _s(58, context),
      height: _s(64, context),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(_s(8, context)),
        border: Border.all(
          color: color.withValues(alpha: 0.4),
          width: _s(1.2, context),
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (subChar.isEmpty)
            Text(
              mainChar,
              style: TextStyle(
                fontSize: _s(28, context),
                fontWeight: FontWeight.w900,
                color: color,
                height: 1.0,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mainChar,
                  style: TextStyle(
                    fontSize: _s(28, context),
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.0,
                  ),
                ),
                Text(
                  subChar,
                  style: TextStyle(
                    fontSize: _s(20, context),
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          SizedBox(height: _s(1, context)),
          Text(
            '最大震度',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _s(8, context),
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoEventCard(
    BuildContext context,
    QuakeMessage event,
    double intensity,
    Color themeColor,
    bool isSerious,
    int totalCount,
    QuakeProvider provider,
  ) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_s(10, context)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: _s(420, context),
            decoration: BoxDecoration(
              color: const Color(0xCC0D0D0D),
              borderRadius: BorderRadius.circular(_s(10, context)),
              border: Border.all(
                color: _isScalePrompt(event)
                    ? const Color(0xFF666666).withValues(alpha: 0.35)
                    : themeColor.withValues(alpha: 0.35),
                width: _s(1.2, context),
              ),
              boxShadow: [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.08),
                  blurRadius: _s(20, context),
                  spreadRadius: _s(1, context),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoEventHeader(
                  context,
                  event,
                  themeColor,
                  totalCount,
                  provider,
                ),
                _buildInfoEventBody(context, event, intensity, themeColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoEventHeader(
    BuildContext context,
    QuakeMessage event,
    Color themeColor,
    int totalCount,
    QuakeProvider provider,
  ) {
    final title = _infoEventTitle(event);
    final sourceLabel = _sourceLabel(event, includeProvince: true);
    final typeLabel = _sourceTypeLabel(event);
    final isScale = _isScalePrompt(event);
    final barColor = isScale ? const Color(0xFF666666) : themeColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _s(16, context),
        vertical: _s(6, context),
      ),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_s(9, context)),
        ),
        border: Border(
          bottom: BorderSide(
            color: barColor.withValues(alpha: 0.2),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: _s(6, context),
            height: _s(6, context),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: barColor,
              boxShadow: [
                BoxShadow(
                  color: barColor.withValues(alpha: 0.6),
                  blurRadius: _s(4, context),
                ),
              ],
            ),
          ),
          SizedBox(width: _s(10, context)),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: _s(12, context),
                      fontWeight: FontWeight.w700,
                      color: barColor,
                      letterSpacing: _s(1.5, context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (typeLabel.isNotEmpty) ...[
                  SizedBox(width: _s(6, context)),
                  _buildTopChip(context, typeLabel, barColor),
                ],
              ],
            ),
          ),
          if (totalCount > 1) ...[
            _buildCarouselNav(context, provider, totalCount, barColor),
            SizedBox(width: _s(6, context)),
          ],
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: _s(6, context),
              vertical: _s(2, context),
            ),
            decoration: BoxDecoration(
              color: barColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(_s(4, context)),
              border: Border.all(
                color: barColor.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _s(98, context)),
              child: Text(
                sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _s(10, context),
                  color: barColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                  letterSpacing: _s(0.5, context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoEventBody(
    BuildContext context,
    QuakeMessage event,
    double intensity,
    Color themeColor,
  ) {
    final displayTime = QuakeTime.displayClock(event);
    final useShindo = _useShindo(event);
    final isScale = _isScalePrompt(event);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _s(16, context),
        _s(10, context),
        _s(16, context),
        _s(10, context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (useShindo && event.jmaShindo != null)
                _buildShindoBadge(context, event.jmaShindo!, themeColor)
              else
                _buildIntensityBadge(context, intensity, themeColor),
              SizedBox(width: _s(12, context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isScale ? '震源地: 調査中' : event.location,
                      style: TextStyle(
                        fontSize: _s(18, context),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: _s(4, context)),
                    if (!isScale)
                      Text(
                        'M${event.magnitude.toStringAsFixed(1)}  ·  深度 ${event.depth.toStringAsFixed(0)} km',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: _s(12, context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: _s(8, context)),
          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          SizedBox(height: _s(6, context)),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: _s(14, context),
                color: Colors.white38,
              ),
              SizedBox(width: _s(6, context)),
              Text(
                '${displayTime.hour.toString().padLeft(2, '0')}:${displayTime.minute.toString().padLeft(2, '0')}:${displayTime.second.toString().padLeft(2, '0')} ${QuakeTime.zoneLabel(event)}',
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: _s(15, context),
                  fontWeight: FontWeight.w900,
                  color: themeColor,
                ),
              ),
            ],
          ),
          SizedBox(height: _s(6, context)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: _s(6, context)),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(_s(6, context)),
              border: Border.all(
                color: themeColor.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: Text(
              _infoEventMaxIntensityText(event, intensity, useShindo),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: themeColor,
                fontSize: _s(12, context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _reportText(QuakeMessage event) {
    final n = event.reportNumber;
    if (n != null && n > 0) return '第$n报';
    return '第?报';
  }

  String _sourceLabel(QuakeMessage event, {bool includeProvince = false}) {
    // /cea-pr 顶部来源标签要求带省级分中心字段。
    if (includeProvince && event.source == QuakeSourceType.cea_pr) {
      final province = _provinceLabel(event);
      if (province != null && province.isNotEmpty) {
        return '省级网/$province';
      }
      return '省级网';
    }
    return event.source.displayName;
  }

  String? _provinceLabel(QuakeMessage event) {
    // 仅从注册字段 province 读取，不再从 location 兜底推断。
    if (event.source == QuakeSourceType.cea_pr &&
        event.province != null &&
        event.province!.isNotEmpty) {
      return event.province;
    }
    return null;
  }

  Widget _buildTopChip(BuildContext context, String text, Color themeColor) {
    return Container(
      constraints: BoxConstraints(maxWidth: _s(88, context)),
      padding: EdgeInsets.symmetric(
        horizontal: _s(5, context),
        vertical: _s(2, context),
      ),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(_s(3, context)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: _s(9, context),
          color: themeColor.withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String text) {
    return Container(
      constraints: BoxConstraints(maxWidth: _s(195, context)),
      padding: EdgeInsets.symmetric(
        horizontal: _s(6, context),
        vertical: _s(2, context),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_s(4, context)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _s(11, context), color: Colors.white54),
          SizedBox(width: _s(4, context)),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _s(10, context),
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
