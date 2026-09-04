import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/quake_message.dart';
import '../../quake_event_adapter.dart';
import 'eqlist_http_poll_gate.dart';

class CencEqlistService {
  static final CencEqlistService _instance = CencEqlistService._internal();
  factory CencEqlistService() => _instance;
  CencEqlistService._internal();

  static const String _url = 'https://api.wolfx.jp/cenc_eqlist.json';

  void Function(List<QuakeMessage>)? onListUpdated;

  /// HTTP 轮询状态回调
  void Function(bool connected)? onStatusChanged;
  Timer? _timer;
  final EqlistHttpPollGate _pushGate = EqlistHttpPollGate();

  /// FAN/Wolfx already refreshed the CENC list — skip HTTP briefly.
  void noteExternalUpdate() => _pushGate.noteExternalUpdate();

  void start({Duration interval = const Duration(seconds: 120)}) {
    if (_timer?.isActive == true) return;
    _timer = Timer.periodic(interval, (_) => fetch());
    fetch();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> fetch() async {
    if (_pushGate.shouldSkipHttp) return;
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        onStatusChanged?.call(false);
        print('CENC HTTP ${resp.statusCode}');
        return;
      }

      final data = json.decode(resp.body);
      if (data is! Map) return;
      onStatusChanged?.call(true);

      final items = QuakeEventAdapter.convertWolfxCencEqlist(
        Map<String, dynamic>.from(data),
      );

      if (items.isNotEmpty) {
        onListUpdated?.call(items);
      }
    } catch (e) {
      onStatusChanged?.call(false);
      print('CENC eqlist fetch error: $e');
    }
  }
}
