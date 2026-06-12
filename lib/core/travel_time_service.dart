import 'dart:convert';
import 'package:flutter/services.dart';

class WaveResult {
  final double reach;
  final double radius;

  WaveResult({required this.reach, required this.radius});
}

class _TravelTable {
  final List<double> depths;
  final List<double> distances;
  final List<List<double>> pTimes;
  final List<List<double>> sTimes;

  _TravelTable({
    required this.depths,
    required this.distances,
    required this.pTimes,
    required this.sTimes,
  });
}

class TravelTimeService {
  static final TravelTimeService _instance = TravelTimeService._internal();
  factory TravelTimeService() => _instance;
  TravelTimeService._internal();

  final Map<String, _TravelTable> _tables = {};
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    if (_isLoaded) return;
    final String response =
        await rootBundle.loadString('assets/travel_times.json');
    final Map<String, dynamic> data = json.decode(response);

    data.forEach((key, value) {
      _tables[key] = _TravelTable(
        depths: (value['depths'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
        distances: (value['distances'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
        pTimes: (value['p_times'] as List)
            .map((row) => (row as List).map((e) => (e as num).toDouble()).toList())
            .toList(),
        sTimes: (value['s_times'] as List)
            .map((row) => (row as List).map((e) => (e as num).toDouble()).toList())
            .toList(),
      );
    });

    _isLoaded = true;
  }

  WaveResult calcWaveDistance(
      String tableName, bool isPWave, double depth, double time) {
    if (depth < 0) depth = 0;
    if (time < 0) time = 0;
    final table = _tables[tableName];
    if (table == null) return WaveResult(reach: 0, radius: 0);

    final data = isPWave ? table.pTimes : table.sTimes;
    final depths = table.depths;
    final distances = table.distances;

    int i = 1;
    while (i < depths.length - 1 && depths[i] < depth) {
      i++;
    }
    double k1 = depths[i] - depth;
    double k2 = depth - depths[i - 1];
    List<double> times =
        List.generate(data[0].length, (j) {
      return (k1 * data[i - 1][j] + k2 * data[i][j]) / (k1 + k2);
    });

    if (time <= times[0]) {
      return WaveResult(
          reach: times[0] > 0 ? time / times[0] : 0, radius: 0);
    }

    int j = 1;
    while (j < times.length - 1 && times[j] < time) {
      j++;
    }
    double k = (distances[j] - distances[j - 1]) / (times[j] - times[j - 1]);
    double b = distances[j] - k * times[j];
    double distance = k * time + b;

    return WaveResult(reach: 1, radius: distance);
  }

  double calcReachTime(
      String tableName, bool isPWave, double depth, double distance) {
    if (depth < 0) depth = 0;
    if (distance < 0) distance = 0;
    final table = _tables[tableName];
    if (table == null) return 0;

    final data = isPWave ? table.pTimes : table.sTimes;
    final depths = table.depths;
    final distances = table.distances;

    int i = 1;
    while (i < depths.length - 1 && depths[i] < depth) {
      i++;
    }
    double k1 = depths[i] - depth;
    double k2 = depth - depths[i - 1];
    List<double> times =
        List.generate(data[0].length, (j) {
      return (k1 * data[i - 1][j] + k2 * data[i][j]) / (k1 + k2);
    });

    int j = 1;
    while (j < distances.length - 1 && distances[j] < distance) {
      j++;
    }
    double k = (times[j] - times[j - 1]) / (distances[j] - distances[j - 1]);
    double b = times[j] - k * distances[j];
    return k * distance + b;
  }
}
