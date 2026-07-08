import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/quake_message.dart';
import '../../quake_event_adapter.dart';

class CencEqlistService {
  static final CencEqlistService _instance = CencEqlistService._internal();
  factory CencEqlistService() => _instance;
  CencEqlistService._internal();

  static const String _url = 'https://api.wolfx.jp/cenc_eqlist.json';

  void Function(List<QuakeMessage>)? onListUpdated;
  Timer? _timer;

  void start() {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(const Duration(seconds: 120), (_) => fetch());
    fetch();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        print('CENC HTTP ${resp.statusCode}');
        return;
      }

      final data = json.decode(resp.body);
      if (data is! Map) return;

      final items = QuakeEventAdapter.convertWolfxCencEqlist(
        Map<String, dynamic>.from(data),
      );

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
}
