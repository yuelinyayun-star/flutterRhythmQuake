import 'knet_duration_proxy_stub.dart'
    if (dart.library.io) 'knet_duration_proxy_io.dart'
    as implementation;

double? nativeKnetDurationProxy(
  List<double> values,
  double hz,
  double duration,
) => implementation.calculate(values, hz, duration);
