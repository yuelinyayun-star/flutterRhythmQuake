// Browser builds have no dart:io Platform. Native builds keep the original
// Platform API so existing Android/Windows behavior is unchanged.
export 'platform_info_web.dart' if (dart.library.io) 'dart:io' show Platform;
