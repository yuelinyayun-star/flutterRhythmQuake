import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

class JapanFaultLine {
  const JapanFaultLine({
    required this.name,
    required this.points,
    required this.colorArgb,
    required this.width,
  });

  final String name;
  final List<LatLng> points;
  final int colorArgb;
  final double width;
}

/// Read the GSJ KMZ unchanged, including its normal KML line styles.
List<JapanFaultLine> parseJapanFaults(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: true);
  final file = archive.findFile('doc.kml');
  if (file == null) throw const FormatException('Missing fault doc.kml');
  final document = XmlDocument.parse(utf8.decode(file.content));
  final styles = <String, XmlElement>{
    for (final node in document.descendants.whereType<XmlElement>())
      if ((node.name.local == 'Style' || node.name.local == 'StyleMap') &&
          node.getAttribute('id') != null)
        '#${node.getAttribute('id')}': node,
  };
  XmlElement lineStyle(String reference, Set<String> visited) {
    if (!visited.add(reference)) {
      throw const FormatException('Cyclic fault style');
    }
    final node = styles[reference];
    if (node == null) throw FormatException('Unknown fault style: $reference');
    if (node.name.local == 'StyleMap') {
      final normal = node
          .findElements('Pair')
          .firstWhere((pair) => pair.getElement('key')?.innerText == 'normal');
      return lineStyle(
        normal.getElement('styleUrl')!.innerText.trim(),
        visited,
      );
    }
    return node.getElement('LineStyle')!;
  }

  final result = <JapanFaultLine>[];
  for (final placemark in document.findAllElements('Placemark')) {
    final style = lineStyle(
      placemark.getElement('styleUrl')!.innerText.trim(),
      {},
    );
    final abgr = int.parse(
      style.getElement('color')!.innerText.trim(),
      radix: 16,
    );
    // KML stores alpha-blue-green-red, while Flutter uses alpha-red-green-blue.
    final argb =
        (abgr & 0xff00ff00) | ((abgr & 0xff) << 16) | ((abgr >> 16) & 0xff);
    final width = double.parse(style.getElement('width')!.innerText.trim());
    var name = placemark.getElement('name')?.innerText;
    XmlNode? parent = placemark.parent;
    while (name == null && parent is XmlElement) {
      name = parent.getElement('name')?.innerText;
      parent = parent.parent;
    }
    for (final line in placemark.findAllElements('LineString')) {
      final coordinates = line.getElement('coordinates')!.innerText.trim();
      final points = coordinates
          .split(RegExp(r'\s+'))
          .map((tuple) {
            final values = tuple.split(',');
            return LatLng(double.parse(values[1]), double.parse(values[0]));
          })
          .toList(growable: false);
      if (points.length < 2) {
        throw const FormatException('Incomplete fault line');
      }
      result.add(
        JapanFaultLine(
          name: name ?? '',
          points: List.unmodifiable(points),
          colorArgb: argb,
          width: width,
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

class JapanFaultService {
  JapanFaultService({Future<Uint8List> Function()? loadAsset})
    : _loadAsset = loadAsset ?? _readAsset;

  static const assetPath = 'assets/maps/jp.fault.kmz';
  static final instance = JapanFaultService();
  final Future<Uint8List> Function() _loadAsset;
  Future<List<JapanFaultLine>>? _loading;

  static Future<Uint8List> _readAsset() async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<List<JapanFaultLine>> load() =>
      _loading ??= _load().catchError((Object error) {
        _loading = null;
        throw error;
      });

  Future<List<JapanFaultLine>> _load() async =>
      compute(parseJapanFaults, await _loadAsset());
}
