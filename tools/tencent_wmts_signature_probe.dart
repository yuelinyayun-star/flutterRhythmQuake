// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const _path = '/maptile/base/wmts';
const _baseUrl = 'https://apis.map.qq.com$_path';

void main() async {
  final apiKey = _readSecret('TENCENT_WMTS_KEY');
  final sk = _readSecret('TENCENT_WMTS_SK');
  final client = http.Client();
  try {
    final variants = _buildVariants(apiKey);
    for (final variant in variants) {
      await _probe(client, variant, sk);
    }
  } finally {
    client.close();
  }
}

String _readSecret(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    throw StateError('Missing environment variable: $name');
  }
  return value.trim();
}

List<_Variant> _buildVariants(String apiKey) {
  final upperKeyParams = <String, String>{
    'SERVICE': 'WMTS',
    'REQUEST': 'GetTile',
    'VERSION': '1.0.0',
    'LAYER': 'default',
    'STYLE': 'default',
    'FORMAT': 'image/png',
    'TILEMATRIXSET': 'EPSG:3857',
    'TILEMATRIX': '4',
    'TILEROW': '3',
    'TILECOL': '8',
    'key': apiKey,
  };
  final lowerAllParams = {
    for (final entry in upperKeyParams.entries)
      entry.key.toLowerCase(): entry.value,
  };
  return [
    _Variant(
      name: 'official-ordinal-raw-sign-encoded-send-header',
      params: upperKeyParams,
      sort: _SortMode.ordinal,
      signEncode: false,
      sendEncode: true,
      legacyHeader: true,
      pathForSig: _path,
    ),
    _Variant(
      name: 'official-ci-raw-sign-encoded-send-header',
      params: upperKeyParams,
      sort: _SortMode.caseInsensitive,
      signEncode: false,
      sendEncode: true,
      legacyHeader: true,
      pathForSig: _path,
    ),
    _Variant(
      name: 'request-order-raw-sign-encoded-send-header',
      params: upperKeyParams,
      sort: _SortMode.insertion,
      signEncode: false,
      sendEncode: true,
      legacyHeader: true,
      pathForSig: _path,
    ),
    _Variant(
      name: 'lowercase-params-raw-sign-encoded-send-header',
      params: lowerAllParams,
      sort: _SortMode.ordinal,
      signEncode: false,
      sendEncode: true,
      legacyHeader: true,
      pathForSig: _path,
    ),
    _Variant(
      name: 'official-ordinal-encoded-sign-encoded-send-header',
      params: upperKeyParams,
      sort: _SortMode.ordinal,
      signEncode: true,
      sendEncode: true,
      legacyHeader: true,
      pathForSig: _path,
    ),
    _Variant(
      name: 'official-ordinal-raw-sign-raw-send-no-header',
      params: upperKeyParams,
      sort: _SortMode.ordinal,
      signEncode: false,
      sendEncode: false,
      legacyHeader: false,
      pathForSig: _path,
    ),
    _Variant(
      name: 'trailing-slash-path-raw-sign-encoded-send-header',
      params: upperKeyParams,
      sort: _SortMode.ordinal,
      signEncode: false,
      sendEncode: true,
      legacyHeader: true,
      pathForSig: '$_path/',
    ),
  ];
}

Future<void> _probe(http.Client client, _Variant variant, String sk) async {
  final entries = _sortedEntries(variant.params, variant.sort);
  final signQuery = _query(entries, encode: variant.signEncode);
  final signatureSource = '${variant.pathForSig}?$signQuery$sk';
  final sig = md5.convert(utf8.encode(signatureSource)).toString();
  final sendQuery = _query(entries, encode: variant.sendEncode);
  final url = Uri.parse('$_baseUrl?$sendQuery&sig=$sig');
  final response = await client.get(
    url,
    headers: {
      if (variant.legacyHeader) 'x-legacy-url-decode': 'no',
      'User-Agent': 'FlutterRhythmQuake WMTS probe',
    },
  );
  final contentType = response.headers['content-type'] ?? 'unknown';
  final body = utf8.decode(response.bodyBytes, allowMalformed: true);
  final imageLike =
      response.statusCode == 200 && contentType.startsWith('image/');
  print('--- ${variant.name}');
  print(
    'sig=${_short(sig)} status=${response.statusCode} contentType=$contentType bytes=${response.bodyBytes.length} image=$imageLike',
  );
  print('source=${_redact(signatureSource)}');
  print('url=${_redact(url.toString())}');
  if (!imageLike && body.isNotEmpty) {
    print('body=${_redact(body.length > 500 ? body.substring(0, 500) : body)}');
  }
}

List<MapEntry<String, String>> _sortedEntries(
  Map<String, String> params,
  _SortMode mode,
) {
  final entries = params.entries.toList();
  switch (mode) {
    case _SortMode.insertion:
      return entries;
    case _SortMode.ordinal:
      entries.sort((a, b) => a.key.compareTo(b.key));
      return entries;
    case _SortMode.caseInsensitive:
      entries.sort((a, b) {
        final folded = a.key.toLowerCase().compareTo(b.key.toLowerCase());
        return folded != 0 ? folded : a.key.compareTo(b.key);
      });
      return entries;
  }
}

String _query(List<MapEntry<String, String>> entries, {required bool encode}) {
  return entries
      .map((entry) {
        if (!encode) return '${entry.key}=${entry.value}';
        return '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}';
      })
      .join('&');
}

String _short(String value) =>
    '${value.substring(0, 4)}...${value.substring(value.length - 4)}';

String _redact(String value) {
  final key = Platform.environment['TENCENT_WMTS_KEY'] ?? '';
  final sk = Platform.environment['TENCENT_WMTS_SK'] ?? '';
  return value.replaceAll(key, _mask(key)).replaceAll(sk, '<SK>');
}

String _mask(String value) {
  if (value.length <= 8) return '***';
  return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
}

enum _SortMode { insertion, ordinal, caseInsensitive }

class _Variant {
  const _Variant({
    required this.name,
    required this.params,
    required this.sort,
    required this.signEncode,
    required this.sendEncode,
    required this.legacyHeader,
    required this.pathForSig,
  });

  final String name;
  final Map<String, String> params;
  final _SortMode sort;
  final bool signEncode;
  final bool sendEncode;
  final bool legacyHeader;
  final String pathForSig;
}
