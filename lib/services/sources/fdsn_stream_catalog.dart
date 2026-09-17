import 'dart:convert';

import 'fdsn_seedlink_info.dart';

typedef FdsnAvailableStation = ({
  String network,
  String station,
  String selector,
});

/// Ringserver /streams: source ID, first sample time, last sample time.
/// FDSN Source Identifiers separate band/source/subsource with underscores.
List<FdsnAvailableStation> parseFdsnStreamCatalog(
  (String, DateTime, int) input,
) {
  if (input.$3 <= 0) return const [];
  final groups =
      <String, List<({String location, String channel, DateTime end})>>{};
  final names = <String, (String, String)>{};
  for (final line in const LineSplitter().convert(input.$1)) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length != 3) continue;
    final id = fields[0].split('/');
    if (id.length != 2 || id[1] != 'MSEED' || !id[0].startsWith('FDSN:')) {
      continue;
    }
    final codes = id[0].substring(5).split('_');
    if (codes.length != 6 ||
        codes[0].isEmpty ||
        codes[1].isEmpty ||
        codes.skip(3).any((code) => code.length != 1)) {
      continue;
    }
    final end = DateTime.tryParse(fields[2]);
    if (end == null ||
        !end.isUtc ||
        end.isAfter(input.$2) ||
        input.$2.difference(end) > FdsnSeedLinkInfo.maxDataAge) {
      continue;
    }
    final key = '${codes[0]}.${codes[1]}';
    names[key] = (codes[0], codes[1]);
    groups.putIfAbsent(key, () => []).add((
      location: codes[2],
      channel: '${codes[3]}${codes[4]}${codes[5]}',
      end: end,
    ));
  }
  final result = <FdsnAvailableStation>[];
  for (final entry in groups.entries) {
    for (final family in const ['HN', 'HL', 'HH', 'BH', 'EH', 'SH']) {
      final matches =
          entry.value.where((c) => c.channel.startsWith(family)).toList()
            ..sort((a, b) => b.end.compareTo(a.end));
      if (matches.isEmpty) continue;
      final name = names[entry.key]!;
      result.add((
        network: name.$1,
        station: name.$2,
        selector: '${matches.first.location}$family?.D',
      ));
      break;
    }
    if (result.length >= input.$3) break;
  }
  return result;
}
