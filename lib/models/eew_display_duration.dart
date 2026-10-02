import 'unified_quake_data.dart';

Duration eewDisplayDuration(UnifiedQuakeData event) {
  if (event.isCanceled) return const Duration(seconds: 20);
  final minimum = event.isWarn ? 6 : 3;
  return Duration(
    minutes: (event.magnitude > minimum ? event.magnitude : minimum).ceil(),
  );
}
