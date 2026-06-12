import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../models/quake_message.dart';
import '../../../core/intensity_calculator.dart';

class CencEqlistService {
  static final CencEqlistService _instance = CencEqlistService._internal();
  factory CencEqlistService() => _instance;
  CencEqlistService._internal();

  static const String _url = 'https://api.wolfx.jp/cenc_eqlist.json';

  void Function(List<QuakeMessage>)? onListUpdated;
  Timer? _timer;

  void start() { _timer = Timer.periodic(const Duration(seconds: 120), (_) => fetch()); fetch(); }
  void stop() { _timer?.cancel(); _timer = null; }

  Future<void> fetch() async {
    try {
      final resp = await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        print('CENC HTTP ${resp.statusCode}');
        return;
      }
      final data = json.decode(resp.body) as Map?;
      if (data == null) return;

      final items = <QuakeMessage>[];
      for (int i = 1; i <= 50; i++) {
        // Wolfx uses "No1".."No50" as keys, NOT "1".."50"
        final entry = data['No$i'];
        if (entry is! Map) continue;

        final timeStr = entry['time']?.toString() ?? '';
        final eventId = entry['EventID']?.toString() ?? '';
        final md5 = entry['md5']?.toString() ?? '';
        final double magnitude = double.tryParse(entry['magnitude']?.toString() ?? '') ?? 0.0;
        final double depth = double.tryParse(entry['depth']?.toString() ?? '') ?? 0.0;
        final String reviewType = entry['type']?.toString() ?? '';

        items.add(QuakeMessage(
          source: QuakeSourceType.cenc,
          eventId: eventId.isNotEmpty ? eventId : (md5.isNotEmpty ? md5 : 'cenc_$i'),
          location: _bestStr(entry),
          magnitude: magnitude,
          latitude: double.tryParse(entry['latitude']?.toString() ?? '') ?? 0.0,
          longitude: double.tryParse(entry['longitude']?.toString() ?? '') ?? 0.0,
          depth: depth,
          originTime: DateTime.tryParse(timeStr.replaceAll(' ', 'T')) ?? DateTime.now(),
          maxIntensity: IntensityCalculator.calcCsisLevel(magnitude, depth, 0),
          reviewType: reviewType,
          isHistory: true,
        ));
      }

      if (items.isNotEmpty) {
        print('CENC eqlist: ${items.length} items');
        onListUpdated?.call(items);
      } else {
        print('CENC eqlist: 0 items parsed');
      }
    } catch (e) {
      print('CENC eqlist fetch error: $e');
    }
  }

  String _bestStr(Map entry) {
    final loc = entry['location']?.toString() ?? '';
    final pn = entry['placeName']?.toString() ?? '';
    if (loc.length >= pn.length) return loc.isNotEmpty ? loc : '未知地点';
    return pn.isNotEmpty ? pn : '未知地点';
  }
}
