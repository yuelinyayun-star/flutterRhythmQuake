import 'package:flutter/foundation.dart' show kIsWeb;

/// Keep browser source requests on the app origin. The deployment Nginx
/// configuration maps each prefix to one fixed upstream host and path.
Uri sourceUri(Uri upstream) {
  if (!kIsWeb) return upstream;
  return webSourceUri(upstream, Uri.base);
}

/// Exposed separately so path mappings can be checked without a browser.
Uri webSourceUri(Uri upstream, Uri appBase) {
  final path = upstream.path;
  final prefix = switch (upstream.host) {
    'www.lmoni.bosai.go.jp' when path.startsWith('/img_svr/') =>
      '/api/lmoni/${path.substring('/img_svr/'.length)}',
    'www.lmoni.bosai.go.jp'
        when path.startsWith('/monitor/data/data/map_img/') =>
      '/api/lpgm-image/${path.substring('/monitor/data/data/map_img/'.length)}',
    'd1.weather.com.cn' => '/api/china-weather-media$path',
    'd4.weather.com.cn' when path == '/geong/v1/api' =>
      '/api/china-weather-location$path',
    'weather.cma.cn' when path.startsWith('/api/') =>
      '/api/cma-weather/${path.substring('/api/'.length)}',
    'www.jma.go.jp' when path.startsWith('/bosai/') =>
      '/api/jma-bosai/${path.substring('/bosai/'.length)}',
    'typhoon.slt.zj.gov.cn' when path.startsWith('/Api/') =>
      '/api/zhejiang-weather/${path.substring('/Api/'.length)}',
    'forecast.weather.com.cn' when path.startsWith('/api/v1/traffic/alarm/') =>
      '/api/china-weather-alert-list/${path.substring('/api/v1/traffic/alarm/'.length)}',
    'product.weather.com.cn' when path.startsWith('/alarm/webdata/') =>
      '/api/china-weather-alert-detail/${path.substring('/alarm/webdata/'.length)}',
    'www.data.jma.go.jp' when path.startsWith('/developer/xml/') =>
      '/api/jma-xml/${path.substring('/developer/xml/'.length)}',
    'data.nsmc.org.cn'
        when path.startsWith('/nsmcapi/') || path.startsWith('/NSMCAPI/') =>
      '/api/nsmc$path',
    _ => null,
  };
  if (prefix == null) return upstream;
  return appBase.resolve(prefix).replace(query: upstream.query);
}

/// Browsers own these headers; the fixed-host proxy supplies them upstream.
Map<String, String>? sourceHeaders(Map<String, String>? headers) {
  if (!kIsWeb || headers == null) return headers;
  final allowed = Map<String, String>.of(headers)
    ..removeWhere((key, _) {
      final lower = key.toLowerCase();
      return lower == 'user-agent' || lower == 'referer';
    });
  return allowed.isEmpty ? null : allowed;
}
