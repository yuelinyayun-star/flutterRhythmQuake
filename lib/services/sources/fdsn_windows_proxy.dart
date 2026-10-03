import 'dart:ffi';
import 'package:ffi/ffi.dart';

final class _UserProxy extends Struct {
  @Int32()
  external int autoDetect;
  external Pointer<Utf16> autoUrl;
  external Pointer<Utf16> proxy;
  external Pointer<Utf16> bypass;
}

final class _AutoOptions extends Struct {
  @Uint32()
  external int flags;
  @Uint32()
  external int detectFlags;
  external Pointer<Utf16> url;
  external Pointer<Void> reserved;
  @Uint32()
  external int reservedFlags;
  @Int32()
  external int autoLogon;
}

final class _ProxyInfo extends Struct {
  @Uint32()
  external int accessType;
  external Pointer<Utf16> proxy;
  external Pointer<Utf16> bypass;
}

final _winhttp = DynamicLibrary.open('winhttp.dll');
final _kernel = DynamicLibrary.open('kernel32.dll');
final _getConfig = _winhttp
    .lookupFunction<
      Int32 Function(Pointer<_UserProxy>),
      int Function(Pointer<_UserProxy>)
    >('WinHttpGetIEProxyConfigForCurrentUser');
final _free = _kernel
    .lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)
    >('GlobalFree');
final _lastError = _kernel.lookupFunction<Uint32 Function(), int Function()>(
  'GetLastError',
);
final _open = _winhttp
    .lookupFunction<
      Pointer<Void> Function(
        Pointer<Utf16>,
        Uint32,
        Pointer<Utf16>,
        Pointer<Utf16>,
        Uint32,
      ),
      Pointer<Void> Function(
        Pointer<Utf16>,
        int,
        Pointer<Utf16>,
        Pointer<Utf16>,
        int,
      )
    >('WinHttpOpen');
final _close = _winhttp
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'WinHttpCloseHandle',
    );
final _timeouts = _winhttp
    .lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32),
      int Function(Pointer<Void>, int, int, int, int)
    >('WinHttpSetTimeouts');
final _getProxy = _winhttp
    .lookupFunction<
      Int32 Function(
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<_AutoOptions>,
        Pointer<_ProxyInfo>,
      ),
      int Function(
        Pointer<Void>,
        Pointer<Utf16>,
        Pointer<_AutoOptions>,
        Pointer<_ProxyInfo>,
      )
    >('WinHttpGetProxyForUrl');

String _string(Pointer<Utf16> value) =>
    value == nullptr ? '' : value.toDartString();
void _release(Pointer<Utf16> value) {
  if (value != nullptr) _free(value.cast());
}

/// WinHTTP returns only the enabled manual proxy, not the stale registry value
/// left behind when Windows' system-proxy switch is turned off.
Map<String, Object> readWindowsFdsnProxy() {
  final config = calloc<_UserProxy>();
  try {
    if (_getConfig(config) == 0) {
      final error = _lastError();
      if (error == 2) return const {};
      throw StateError('Windows proxy configuration error $error');
    }
    return {
      'proxy': _string(config.ref.proxy),
      'bypass': _string(config.ref.bypass),
      'autoUrl': _string(config.ref.autoUrl),
      'autoDetect': config.ref.autoDetect != 0,
    };
  } finally {
    _release(config.ref.proxy);
    _release(config.ref.bypass);
    _release(config.ref.autoUrl);
    calloc.free(config);
  }
}

/// Called in a worker isolate: PAC/WPAD resolution can perform network I/O.
Map<String, Object> resolveWindowsFdsnAutoProxy(
  String url,
  String autoUrl,
  bool autoDetect,
) {
  final agent = 'RhythmQuake/FDSN'.toNativeUtf16();
  final target = url.toNativeUtf16();
  final pac = autoUrl.toNativeUtf16();
  final options = calloc<_AutoOptions>();
  final result = calloc<_ProxyInfo>();
  Pointer<Void> session = nullptr;
  try {
    session = _open(agent, 1, nullptr, nullptr, 0);
    if (session == nullptr) {
      throw StateError('WinHTTP open error ${_lastError()}');
    }
    _timeouts(session, 3000, 3000, 3000, 3000);
    options.ref
      ..flags = autoUrl.isNotEmpty ? 2 : 1
      ..detectFlags = autoDetect ? 3 : 0
      ..url = autoUrl.isNotEmpty ? pac : nullptr
      ..autoLogon = 0;
    if (_getProxy(session, target, options, result) == 0) {
      final error = _lastError();
      // WPAD is often enabled on networks with no advertised proxy.
      if (autoUrl.isEmpty && error == 12180) return const {};
      throw StateError('Windows auto proxy error $error');
    }
    return {
      'proxy': result.ref.accessType == 1 ? '' : _string(result.ref.proxy),
      'bypass': _string(result.ref.bypass),
    };
  } finally {
    if (session != nullptr) _close(session);
    _release(result.ref.proxy);
    _release(result.ref.bypass);
    calloc.free(result);
    calloc.free(options);
    calloc.free(agent);
    calloc.free(target);
    calloc.free(pac);
  }
}
