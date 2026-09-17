import 'dart:convert';
import 'package:http/http.dart' as http;

/// Resolve the owning FDSN station service for EIDA networks forwarded by a
/// SeedLink relay. Cache per network, not per packet or component.
class FdsnMetadataRouting {
  final _networks = <String, Future<List<Uri>>>{};
  final _failedUntil = <String, DateTime>{};

  Future<List<Uri>> resolve(http.Client client, String network) {
    final until = _failedUntil[network];
    if (until != null && DateTime.now().isBefore(until)) {
      return Future.value(const []);
    }
    return _networks.putIfAbsent(network, () async {
      try {
        final response = await client
            .get(
              Uri.https('geofon.gfz.de', '/eidaws/routing/1/query', {
                'service': 'station',
                'network': network,
                'format': 'get',
              }),
              headers: const {
                'User-Agent': 'FlutterRhythmQuake/1.0',
                'Accept': 'text/plain,*/*',
              },
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          _networks.remove(network);
          _failedUntil[network] = DateTime.now().add(
            const Duration(minutes: 1),
          );
          return const [];
        }
        final endpoints = <Uri>{};
        for (final line in const LineSplitter().convert(
          utf8.decode(response.bodyBytes),
        )) {
          final uri = Uri.tryParse(line.trim());
          if (uri == null ||
              !['https', 'http'].contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty ||
              !uri.path.endsWith('/fdsnws/station/1/query')) {
            continue;
          }
          endpoints.add(uri.replace(query: ''));
        }
        return endpoints.toList(growable: false);
      } catch (_) {
        _networks.remove(network);
        _failedUntil[network] = DateTime.now().add(const Duration(minutes: 1));
        return const [];
      }
    });
  }
}
