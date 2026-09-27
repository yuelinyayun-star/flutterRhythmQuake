import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutterrhythmquake/services/sources/fdsn_metadata_routing.dart';
import 'package:flutterrhythmquake/services/sources/fdsn_channel_sensitivity.dart';

Future<void> main() async {
  final client = http.Client();
  try {
    final uri = Uri.https('geofon.gfz.de', '/eidaws/routing/1/query', {
      'service': 'station',
      'network': 'GR',
      'format': 'get',
    });
    final r = await client
        .get(
          uri,
          headers: {
            'User-Agent': 'FlutterRhythmQuake/1.0',
            'Accept': 'text/plain,*/*',
          },
        )
        .timeout(const Duration(seconds: 15));
    stdout.writeln(
      jsonEncode({
        'status': r.statusCode,
        'body': r.body.substring(0, r.body.length.clamp(0, 600)),
      }),
    );
    final routes = await FdsnMetadataRouting().resolve(client, 'GR');
    stdout.writeln('routes=$routes');
    for (final route in routes) {
      final time = DateTime.now().toUtc().subtract(const Duration(seconds: 10));
      final query = route.replace(
        queryParameters: {
          'network': 'GR',
          'station': 'FUR',
          'channel': 'HHZ',
          'location': '--',
          'starttime': time.toIso8601String(),
          'endtime': time.toIso8601String(),
          'level': 'channel',
          'format': 'text',
        },
      );
      final response = await client
          .get(query)
          .timeout(const Duration(seconds: 15));
      final parsed = FdsnChannelSensitivity.parse(
        response.body,
        network: 'GR',
        station: 'FUR',
        location: '',
        channel: 'HHZ',
        time: time,
      );
      stdout.writeln(
        jsonEncode({
          'status': response.statusCode,
          'body': response.body,
          'gain': parsed?.sensitivity,
          'lat': parsed?.latitude,
          'lon': parsed?.longitude,
        }),
      );
    }
  } finally {
    client.close();
  }
}
