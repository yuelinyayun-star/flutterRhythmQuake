import 'dart:io';
import 'dart:isolate';
import 'fdsn_windows_proxy.dart';

class FdsnProxyRoute {
  const FdsnProxyRoute.direct() : host = null, port = 0;
  const FdsnProxyRoute.proxy(this.host, this.port);
  final String? host;
  final int port;
  bool get isDirect => host == null;
  String get directive => isDirect ? 'DIRECT' : 'PROXY $authority';
  String get authority => host!.contains(':') ? '[$host]:$port' : '$host:$port';

  static FdsnProxyRoute parse(String value) {
    final text = value.trim();
    if (text.isEmpty || text == 'DIRECT') return const FdsnProxyRoute.direct();
    final address = text.startsWith('PROXY ') ? text.substring(6) : text;
    final uri = Uri.tryParse(
      address.contains('://') ? address : 'http://$address',
    );
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty && uri.path != '/' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException(
        'Unsupported FDSN proxy configuration (HTTP proxy without credentials required)',
      );
    }
    return FdsnProxyRoute.proxy(uri.host, uri.port);
  }
}

bool fdsnProxyBypassed(Uri uri, String bypass) {
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      InternetAddress.tryParse(host)?.isLoopback == true) {
    return true;
  }
  for (var rule in bypass.toLowerCase().split(RegExp(r'[;,\s]+'))) {
    if (rule.isEmpty) continue;
    if (rule == '<local>') {
      if (!host.contains('.') && !host.contains(':')) return true;
      continue;
    }
    if (rule.startsWith('.')) rule = '*$rule';
    final pattern =
        '^${rule.split('*').map(RegExp.escape).join('.*')}'
        r'$';
    final regex = RegExp(pattern);
    if (regex.hasMatch(host) || regex.hasMatch('$host:${uri.port}')) {
      return true;
    }
  }
  return false;
}

FdsnProxyRoute windowsFdsnRoute(Uri uri, Map<String, Object> config) {
  if (fdsnProxyBypassed(uri, config['bypass'] as String? ?? '')) {
    return const FdsnProxyRoute.direct();
  }
  final entries = (config['proxy'] as String? ?? '').trim().split(
    RegExp(r'[;\s]+'),
  );
  String? general;
  for (final entry in entries) {
    if (entry.isEmpty) continue;
    final separator = entry.indexOf('=');
    if (separator < 0) {
      general ??= entry;
    } else if (entry.substring(0, separator).toLowerCase() == uri.scheme) {
      return FdsnProxyRoute.parse(entry.substring(separator + 1));
    }
  }
  return FdsnProxyRoute.parse(general ?? '');
}

class FdsnProxyResolver {
  FdsnProxyResolver({
    Map<String, String>? environment,
    bool? windows,
    Future<Map<String, Object>> Function()? readWindows,
    Future<Map<String, Object>> Function(String, String, bool)? resolveAuto,
    this.cacheDuration = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _environment = environment ?? Platform.environment,
       _windows = windows ?? Platform.isWindows,
       _readWindows = readWindows ?? (() => Isolate.run(readWindowsFdsnProxy)),
       _resolveAuto =
           resolveAuto ??
           ((url, pac, detect) => Isolate.run(
             () => resolveWindowsFdsnAutoProxy(url, pac, detect),
           )),
       _clock = clock ?? DateTime.now;

  final Map<String, String> _environment;
  final bool _windows;
  final Future<Map<String, Object>> Function() _readWindows;
  final Future<Map<String, Object>> Function(String, String, bool) _resolveAuto;
  final Duration cacheDuration;
  final DateTime Function() _clock;
  Future<Map<String, Object>>? _config;
  DateTime? _configAt;
  final _auto = <String, ({DateTime at, Future<Map<String, Object>> value})>{};

  Future<FdsnProxyRoute> resolve(Uri uri) async {
    if (fdsnProxyBypassed(uri, '')) return const FdsnProxyRoute.direct();
    final envKey = '${uri.scheme}_proxy';
    if ((_environment[envKey] ?? _environment[envKey.toUpperCase()] ?? '')
        .isNotEmpty) {
      // Dart supplies NO_PROXY suffix behavior, but strips URL schemes. Validate
      // the original setting so SOCKS/HTTPS proxies cannot be mistaken for HTTP.
      final value = HttpClient.findProxyFromEnvironment(
        uri,
        environment: _environment,
      );
      if (value != 'DIRECT') {
        FdsnProxyRoute.parse(
          _environment[envKey] ?? _environment[envKey.toUpperCase()]!,
        );
      }
      return FdsnProxyRoute.parse(value);
    }
    if (!_windows) return const FdsnProxyRoute.direct();
    final now = _clock();
    if (_config == null || now.difference(_configAt!) >= cacheDuration) {
      _configAt = now;
      _config = _readWindows();
      _auto.removeWhere(
        (_, entry) => now.difference(entry.at) >= cacheDuration,
      );
    }
    final config = await _config!;
    final pac = config['autoUrl'] as String? ?? '';
    final detect = config['autoDetect'] == true;
    // An explicit manual proxy is authoritative; do not perform needless WPAD.
    if (pac.isEmpty && (config['proxy'] as String? ?? '').isNotEmpty) {
      return windowsFdsnRoute(uri, config);
    }
    if (pac.isEmpty && !detect) return windowsFdsnRoute(uri, config);
    final key = '$pac|$detect|$uri';
    var cached = _auto[key];
    if (cached == null || now.difference(cached.at) >= cacheDuration) {
      cached = (at: now, value: _resolveAuto(uri.toString(), pac, detect));
      _auto[key] = cached;
    }
    return windowsFdsnRoute(uri, await cached.value);
  }
}
