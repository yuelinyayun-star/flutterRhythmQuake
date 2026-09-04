enum QuakeSourceType { wolfx, nied, p2p, cenc, usgs }

class QuakeMessage {
  final QuakeSourceType source;
  final String eventId;
  final String location;
  final double magnitude;
  final double latitude;
  final double longitude;
  final double depth;
  final DateTime originTime;
  final bool isTest; // 过滤测试报文
  final int? maxIntensity; // 预估烈度

  QuakeMessage({
    required this.source,
    required this.eventId,
    required this.location,
    required this.magnitude,
    required this.latitude,
    required this.longitude,
    required this.depth,
    required this.originTime,
    this.isTest = false,
    this.maxIntensity,
  });
}
