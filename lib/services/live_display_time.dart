import 'live_display_time_portable.dart'
    if (dart.library.io) 'live_display_time_io.dart'
    as platform;

enum LiveDisplayLifetime {
  usgsAutomaticProduct,
  weatherWithoutExpiry,
  jmaAdvisory,
  jmaInvestigationEnded,
  seisJsStation,
}

int liveDisplayElapsedUs() => platform.liveDisplayElapsedUs();

Duration liveDisplayLifetime(LiveDisplayLifetime kind) =>
    Duration(microseconds: platform.liveDisplayLifetimeUs(kind.index));
