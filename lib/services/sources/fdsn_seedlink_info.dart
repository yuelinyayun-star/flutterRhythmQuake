import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml_events.dart';

/// Parse complete stations as INFO records arrive, retaining neither the full
/// catalogue nor repeated copies of its XML. Incomplete stations are not used.
class FdsnSeedLinkInfo implements Sink<List<XmlEvent>> {
  FdsnSeedLinkInfo({required this.now, required this.limit, this.clock}) {
    _xml = XmlEventDecoder(validateNesting: true).startChunkedConversion(this);
    _utf8 = utf8.decoder.startChunkedConversion(_xml);
  }

  static const maxDataAge = Duration(minutes: 3);
  final DateTime now;
  final DateTime Function()? clock;
  final int limit;
  final stations = <({String network, String station, String selector})>[];
  final _seen = <String>{};
  final _bytes = <int>[];
  late final StringConversionSink _xml;
  late final ByteConversionSink _utf8;
  String? _network;
  String? _station;
  final _channels = <({String location, String channel, DateTime end})>[];
  bool complete = false;
  bool get enough => stations.length >= limit;

  void addBytes(List<int> bytes) {
    _bytes.addAll(bytes);
    var offset = 0;
    while (_bytes.length - offset >= 520 && !complete && !enough) {
      final packet = Uint8List(520)..setRange(0, 520, _bytes, offset);
      offset += 520;
      if (ascii.decode(packet.sublist(0, 6), allowInvalid: true) != 'SLINFO') {
        throw const FormatException('Expected SeedLink INFO record');
      }
      final data = ByteData.sublistView(packet, 8);
      final year = data.getUint16(20, Endian.big);
      final endian = year >= 1900 && year <= 2200 ? Endian.big : Endian.little;
      final begin = data.getUint16(44, endian);
      final count = data.getUint16(30, endian);
      if (begin < 48 || begin + count > 512) {
        throw const FormatException('Invalid INFO payload length');
      }
      _utf8.add(packet.sublist(8 + begin, 8 + begin + count));
      if (packet[7] == 0x20) {
        _utf8.close();
        complete = true;
      }
    }
    if (offset > 0) _bytes.removeRange(0, offset);
  }

  @override
  void add(List<XmlEvent> events) {
    for (final event in events) {
      if (enough) return;
      if (event is XmlStartElementEvent) {
        final attrs = {for (final a in event.attributes) a.name: a.value};
        if (event.name == 'station') {
          _network = attrs['network'];
          _station = attrs['name'];
          _channels.clear();
        } else if (event.name == 'stream' && _station != null) {
          final channel = attrs['seedname'] ?? '';
          // SeisComP v3 uses YYYY/MM/DD; RingServer uses ISO 8601. Both UTC.
          final rawEnd = (attrs['end_time'] ?? '').replaceAll('/', '-');
          final end = DateTime.tryParse(
            rawEnd.endsWith('Z') ? rawEnd : '${rawEnd}Z',
          );
          final current = clock?.call() ?? now;
          if (attrs['type'] == 'D' &&
              channel.length == 3 &&
              end != null &&
              !end.isAfter(current) &&
              current.difference(end) <= maxDataAge) {
            _channels.add((
              location: attrs['location'] ?? '',
              channel: channel,
              end: end,
            ));
          }
        }
      } else if (event is XmlEndElementEvent && event.name == 'station') {
        _finishStation();
      } else if (event is XmlEndElementEvent && event.name == 'seedlink') {
        complete = true;
      }
    }
  }

  void _finishStation() {
    final network = _network;
    final station = _station;
    _network = null;
    _station = null;
    if (network == null ||
        station == null ||
        network.isEmpty ||
        station.isEmpty) {
      return;
    }
    for (final family in const ['HN', 'HL', 'HH', 'BH', 'EH', 'SH']) {
      final matches =
          _channels.where((c) => c.channel.startsWith(family)).toList()
            ..sort((a, b) => b.end.compareTo(a.end));
      if (matches.isEmpty) continue;
      final location = matches.first.location;
      if (!_seen.add('$network.$station')) return;
      stations.add((
        network: network,
        station: station,
        // An omitted location matches blank locations; SeisComP's ?? does not.
        selector: '$location$family?.D',
      ));
      return;
    }
  }

  @override
  void close() {}
}
