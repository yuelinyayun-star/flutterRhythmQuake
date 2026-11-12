import 'fdsn_display_frame.dart';

class FdsnRealtimePipeline {
  FdsnRealtimePipeline({bool testMode = false});
  static bool get supported => false;
  static FdsnRealtimePipeline? active;
  FdsnDisplayFrame? lastFrame;
  void Function(FdsnDisplayFrame)? onFrame;
  void Function(Object)? onError;
  Future<void> connect({
    required int stationLimit,
    required Set<String> sources,
  }) async {}
  void stop() {}
  void dispose() {}
}
