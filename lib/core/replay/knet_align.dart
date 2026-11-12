import 'knet_align_stub.dart' if (dart.library.io) 'knet_align_io.dart' as impl;

List<double>? nativeAlignKnetChannel(
  List<double> samples,
  int offset,
  int count,
  double offsetGal,
) => impl.align(samples, offset, count, offsetGal);
