import 'dart:async';

class FdsnMotionSample {
  final String source;
  final String network;
  final String station;
  final String channel;
  final double? pga;
  final double? pgv;
  final double? intensity;
  final bool active;
  final DateTime timestamp;

  const FdsnMotionSample({
    required this.source,
    required this.network,
    required this.station,
    required this.channel,
    required this.timestamp,
    this.pga,
    this.pgv,
    this.intensity,
    this.active = false,
  });

  String get code => '$network.$station';
}

class FdsnMotionService {
  static final FdsnMotionService _instance = FdsnMotionService._();
  factory FdsnMotionService() => _instance;
  FdsnMotionService._();

  final _controller = StreamController<FdsnMotionSample>.broadcast();
  Stream<FdsnMotionSample> get sampleStream => _controller.stream;

  void Function(bool connected)? onStatusChanged;

  void connect() {
    onStatusChanged?.call(false);
  }

  void disconnect() {
    onStatusChanged?.call(false);
  }

  void dispose() {
    _controller.close();
  }
}
