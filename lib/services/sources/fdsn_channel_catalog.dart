import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'fdsn_channel_sensitivity.dart';
import 'fdsn_metadata_routing.dart';

/// GQ's channel-database approach: load metadata by network, not by packet.
/// The dictionary is indexed by exact NSLC and retains every returned epoch.
class FdsnChannelCatalog {
  FdsnChannelCatalog(this.client);
  final http.Client client;
  final _routing = FdsnMetadataRouting();
  final _networks =
      <String, Future<Map<String, List<FdsnChannelSensitivity>>>>{};
  final _retryAfter = <String, DateTime>{};
  bool _closed = false;
  int _active = 0;
  final _waiting = <Completer<void>>[];

  Future<Map<String, List<FdsnChannelSensitivity>>> load(
    String source,
    String network,
  ) {
    final key = '$source:$network';
    final retry = _retryAfter[key];
    if (retry != null && !DateTime.now().isBefore(retry)) {
      _networks.remove(key);
      _retryAfter.remove(key);
    }
    return _networks.putIfAbsent(
      key,
      () => _load(source, network).then((result) {
        if (result.isEmpty) {
          _retryAfter[key] = DateTime.now().add(const Duration(minutes: 1));
        }
        return result;
      }),
    );
  }

  Future<FdsnChannelSensitivity?> find({
    required String source,
    required String network,
    required String station,
    required String location,
    required String channel,
    required DateTime time,
  }) async {
    final channels = await load(source, network);
    FdsnChannelSensitivity? best;
    for (final epoch
        in channels['$network.$station.$location.$channel'] ??
            const <FdsnChannelSensitivity>[]) {
      if (epoch.covers(time) &&
          (best == null || epoch.start.isAfter(best.start))) {
        best = epoch;
      }
    }
    return best;
  }

  Future<Map<String, List<FdsnChannelSensitivity>>> _load(
    String source,
    String network,
  ) async {
    if (_closed) return {};
    if (_active >= 4) {
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    if (_closed) return {};
    try {
      final base = Uri.parse(
        source == 'GEOFON'
            ? 'https://geofon.gfz-potsdam.de/fdsnws/station/1/query'
            : 'https://service.earthscope.org/fdsnws/station/1/query',
      );
      final result = <String, List<FdsnChannelSensitivity>>{};
      Future<void> fetch(Uri endpoint) async {
        try {
          final response = await client
              .get(
                endpoint.replace(
                  queryParameters: {
                    'network': network,
                    'channel': 'HN?,HL?,HH?,BH?,EH?,SH?',
                    'level': 'channel',
                    'format': 'text',
                    'nodata': '204',
                    'endafter': DateTime.now()
                        .toUtc()
                        .subtract(const Duration(minutes: 3))
                        .toIso8601String(),
                  },
                ),
                headers: const {
                  'Accept': 'text/plain',
                  'User-Agent': 'FlutterRhythmQuake/1.0',
                },
              )
              .timeout(const Duration(seconds: 60));
          if (_closed || response.statusCode != 200) return;
          final parsed = await compute(parseFdsnChannelCatalog, (
            utf8.decode(response.bodyBytes),
            network,
          ));
          if (_closed) return;
          for (final entry in parsed.entries) {
            result.putIfAbsent(entry.key, () => []).addAll(entry.value);
          }
        } catch (error) {
          if (!_closed) {
            debugPrint('FDSN channel catalogue $source/$network: $error');
          }
        }
      }

      await fetch(base);
      if (!_closed && source == 'GEOFON') {
        for (final route in await _routing.resolve(client, network)) {
          if (_closed) return {};
          if (route.host == base.host ||
              (route.host == 'geofon.gfz.de' &&
                  base.host == 'geofon.gfz-potsdam.de')) {
            continue;
          }
          await fetch(route);
        }
      }
      if (!_closed) {
        debugPrint(
          'FDSN channel catalogue $source/$network: ${result.length} channels',
        );
      }
      return result;
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  void dispose() {
    _closed = true;
    client.close();
    for (final ready in _waiting) {
      ready.complete();
    }
    _waiting.clear();
    _networks.clear();
    _retryAfter.clear();
  }
}

Map<String, List<FdsnChannelSensitivity>> parseFdsnChannelCatalog(
  (String, String) input,
) {
  final result = <String, List<FdsnChannelSensitivity>>{};
  for (final line in const LineSplitter().convert(input.$1)) {
    if (line.startsWith('#') || line.isEmpty) continue;
    final c = line.split('|').map((v) => v.trim()).toList(growable: false);
    if (c.length < 17 || c[0] != input.$2) continue;
    final start = DateTime.tryParse(c[15].endsWith('Z') ? c[15] : '${c[15]}Z');
    if (start == null) continue;
    final response = FdsnChannelSensitivity.parse(
      line,
      network: c[0],
      station: c[1],
      location: c[2],
      channel: c[3],
      time: start,
    );
    if (response != null) {
      result
          .putIfAbsent('${c[0]}.${c[1]}.${c[2]}.${c[3]}', () => [])
          .add(response);
    }
  }
  return result;
}
