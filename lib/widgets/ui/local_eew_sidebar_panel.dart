import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/calculator.dart';
import '../../core/intensity_calculator.dart';
import '../../core/travel_time_service.dart';
import '../../core/utils/quake_time.dart';
import '../../models/unified_quake_data.dart';
import '../../models/sasmex_map_geometry.dart';
import '../../services/location_service.dart';
import '../../services/ntp_service.dart';

const _domesticEewSources = {
  'ceaEew',
  'scEew',
  'fjEew',
  'cqEew',
  'iclEew',
  'cwaEew',
};

bool isDomesticLocalEew(UnifiedQuakeData event) =>
    _domesticEewSources.contains(event.source);

UnifiedQuakeData? selectLocalEewSidebarEvent(
  List<UnifiedQuakeData> events,
  int currentIndex, {
  required bool domesticEnabled,
  required bool foreignEnabled,
}) {
  bool eligible(UnifiedQuakeData event) =>
      event.isEew &&
      !event.isCanceled &&
      !event.isHistory &&
      (isDomesticLocalEew(event) ? domesticEnabled : foreignEnabled);

  if (currentIndex >= 0 &&
      currentIndex < events.length &&
      eligible(events[currentIndex])) {
    return events[currentIndex];
  }
  for (final event in events) {
    if (eligible(event)) return event;
  }
  return null;
}

class LocalEewEstimate {
  final double? distanceKm;
  final String? intensity;
  final int? secondsToSWave;

  const LocalEewEstimate({
    required this.distanceKm,
    required this.intensity,
    required this.secondsToSWave,
  });
}

LocalEewEstimate calculateLocalEewEstimate(
  UnifiedQuakeData event, {
  required double? userLat,
  required double? userLng,
  required num elapsedSeconds,
  TravelTimeService? travelTimes,
}) {
  final lat = event.lat;
  final lng = event.lng;
  if (!event.isEew ||
      event.isCanceled ||
      lat == null ||
      lng == null ||
      userLat == null ||
      userLng == null ||
      !QuakeCalculator.isUsableMapCoordinate(lat, lng) ||
      !QuakeCalculator.isUsableMapCoordinate(userLat, userLng)) {
    return const LocalEewEstimate(
      distanceKm: null,
      intensity: null,
      secondsToSWave: null,
    );
  }

  final distance = QuakeCalculator.haversineDistance(
    lat,
    lng,
    userLat,
    userLng,
  );
  if (!distance.isFinite) {
    return const LocalEewEstimate(
      distanceKm: null,
      intensity: null,
      secondsToSWave: null,
    );
  }

  String? intensity;
  final hasParameters =
      event.magnitude.isFinite &&
      event.magnitude >= 0 &&
      event.depth.isFinite &&
      event.depth >= 0;
  if (hasParameters) {
    final csis = IntensityCalculator.calcCsis(
      event.magnitude,
      event.depth,
      distance,
    );
    if (csis.isFinite) {
      intensity = csis.clamp(0.0, 12.0).toStringAsFixed(1);
    }
  }

  int? countdown;
  final tables = travelTimes ?? TravelTimeService();
  if (event.source == 'sasmex' && event.originTime != null) {
    final reach = SasmexMapAnimation.sArrivalSeconds(distance);
    countdown = math.max((reach - elapsedSeconds).round(), 0);
  } else if (event.originTime != null &&
      event.depth.isFinite &&
      event.depth >= 0 &&
      tables.isLoaded) {
    final tableName = distance <= 2000 ? 'jma2001' : 'jb';
    final reach = tables.calcReachTime(tableName, false, event.depth, distance);
    if (reach.isFinite && reach > 0) {
      countdown = math.max((reach - elapsedSeconds).floor(), 0);
    }
  }

  return LocalEewEstimate(
    distanceKm: distance,
    intensity: intensity,
    secondsToSWave: countdown,
  );
}

class LocalEewSidebarPanel extends StatefulWidget {
  const LocalEewSidebarPanel({
    super.key,
    required this.event,
    required this.scale,
  });

  final UnifiedQuakeData event;
  final double Function(double) scale;

  @override
  State<LocalEewSidebarPanel> createState() => _LocalEewSidebarPanelState();
}

class _LocalEewSidebarPanelState extends State<LocalEewSidebarPanel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    LocationService().positionListenable.addListener(_refresh);
    TravelTimeService().loadedListenable.addListener(_refresh);
    TravelTimeService().ensureLoaded().catchError((Object error) {
      debugPrint('Local EEW travel times unavailable: $error');
    });
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    LocationService().positionListenable.removeListener(_refresh);
    TravelTimeService().loadedListenable.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = LocationService().currentPosition;
    final approximateLocation =
        LocationService().currentSource == LocationSource.ipFallback;
    final estimate = calculateLocalEewEstimate(
      widget.event,
      userLat: position?.latitude,
      userLng: position?.longitude,
      elapsedSeconds:
          widget.event.source == 'sasmex' && widget.event.originTime != null
          ? NtpService().now
                    .toUtc()
                    .subtract(widget.event.replayClockOffset)
                    .difference(QuakeTime.unifiedInstantUtc(widget.event))
                    .inMilliseconds /
                1000
          : QuakeTime.calcPassedSecondsUnified(widget.event),
    );
    final countdown = estimate.secondsToSWave;
    final accent = countdown == null || countdown == 0
        ? const Color(0xFF7DA7B8)
        : const Color(0xFFFFB64F);
    final scale = widget.scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 185;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                text: '本地烈度预估 · S 波倒计时',
                children: [
                  TextSpan(
                    text: '  仅供参考',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: scale(compact ? 8 : 9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              maxLines: compact ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: scale(compact ? 10 : 12),
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: scale(2)),
            Text(
              widget.event.hypocenter.trim().isEmpty
                  ? '地震预警'
                  : widget.event.hypocenter,
              key: const ValueKey('local-eew-place'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: scale(compact ? 10 : 11),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: scale(8)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _metric(
                    label: '本地预估烈度',
                    value: estimate.intensity ?? '--',
                    suffix: '',
                    scale: scale,
                    compact: compact,
                  ),
                ),
                SizedBox(width: scale(8)),
                Expanded(
                  child: _metric(
                    label: '距震中',
                    value: estimate.distanceKm == null
                        ? '--'
                        : approximateLocation
                        ? '约${estimate.distanceKm!.round()}'
                        : estimate.distanceKm! < 10
                        ? estimate.distanceKm!.toStringAsFixed(1)
                        : estimate.distanceKm!.round().toString(),
                    suffix: ' km',
                    scale: scale,
                    compact: compact,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      countdown == null ? '--' : countdown.toString(),
                      key: const ValueKey('local-eew-countdown'),
                      style: TextStyle(
                        color: accent,
                        fontSize: scale(compact ? 29 : 36),
                        height: 1,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(height: scale(3)),
                    Text(
                      countdown == null
                          ? 'S 波走时不可用'
                          : countdown == 0
                          ? 'S 波预计已到达'
                          : '秒后 S 波到达',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: scale(compact ? 9 : 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required String suffix,
    required double Function(double) scale,
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white60,
            fontSize: scale(compact ? 8 : 9),
          ),
        ),
        SizedBox(height: scale(2)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              text: value,
              children: [
                TextSpan(
                  text: suffix,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: scale(compact ? 8 : 10),
                  ),
                ),
              ],
            ),
            style: TextStyle(
              color: Colors.white,
              fontSize: scale(compact ? 16 : 20),
              height: 1.1,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
