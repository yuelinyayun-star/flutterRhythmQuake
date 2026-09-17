import 'package:flutter/services.dart';

class AndroidBackgroundPowerStatus {
  const AndroidBackgroundPowerStatus({
    this.batteryOptimizationExempt,
    this.powerSaveMode,
    this.backgroundRestricted,
  });

  final bool? batteryOptimizationExempt;
  final bool? powerSaveMode;
  final bool? backgroundRestricted;

  factory AndroidBackgroundPowerStatus.fromMap(Map<Object?, Object?> values) {
    bool? read(String key) => values[key] is bool ? values[key] as bool : null;
    return AndroidBackgroundPowerStatus(
      batteryOptimizationExempt: read('batteryOptimizationExempt'),
      powerSaveMode: read('powerSaveMode'),
      backgroundRestricted: read('backgroundRestricted'),
    );
  }
}

/// Only used by the Android settings surface. Opening settings grants nothing.
class AndroidBackgroundSettings {
  static const _channel = MethodChannel('flutterrhythmquake/system_settings');

  Future<AndroidBackgroundPowerStatus> readStatus() async {
    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'getBackgroundPowerStatus',
    );
    return AndroidBackgroundPowerStatus.fromMap(values ?? const {});
  }

  Future<bool> openBatterySettings() async =>
      await _channel.invokeMethod<bool>('openBatteryOptimizationSettings') ??
      false;

  Future<bool> openAppSettings() async =>
      await _channel.invokeMethod<bool>('openAppSettings') ?? false;
}
