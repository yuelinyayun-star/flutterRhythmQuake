import 'package:flutter/services.dart';
import '../models/tsunami_gauge_plan.dart';
import '../models/tsunami_message.dart';
import 'native_jma_tsunami.dart';

/// Runs on report/geometry changes, never on map animation frames.
class TsunamiGaugeService {
  Future<TsunamiGaugePlan> prepare(
    TsunamiMessage message, {
    List<Map<String, dynamic>> regions = const [],
    DateTime? now,
  }) async {
    if (!NativeJmaTsunami.supported) return const TsunamiGaugePlan();
    final instant = now ?? DateTime.now();
    if (!message.isActive || !message.isDisplayableAt(instant)) {
      return const TsunamiGaugePlan();
    }
    final topology = message.source == TsunamiSource.jma
        ? await rootBundle.loadString(
            'assets/maps/jp.tsunami.topo.json',
            cache: false,
          )
        : null;
    return TsunamiGaugePlan.fromMap(
      await NativeJmaTsunami.prepareAsync({
        'op': 'gaugePlan',
        'message': message.toMap(),
        'regions': regions,
        'jmaTopology': topology,
        'nowMs': instant.millisecondsSinceEpoch,
      }),
    );
  }
}
