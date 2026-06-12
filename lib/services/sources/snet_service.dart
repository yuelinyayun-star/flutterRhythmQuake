import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../models/snet_station.dart';
import 'shindo_color_util.dart';

class SnetService {
  static final SnetService _instance = SnetService._internal();
  factory SnetService() => _instance;
  SnetService._internal();

  static const String _baseUrl = 'https://www.msil.go.jp/data/tiles/smoni';
  static const int _z = 5;
  static const int _xMin = 28, _xMax = 28;
  static const int _yMin = 11, _yMax = 12;
  static const int _tileSize = 256;
  static const int _imgW = (_xMax - _xMin + 1) * _tileSize;
  static const int _imgH = (_yMax - _yMin + 1) * _tileSize;

  static const int _csvZ = 5;
  static const int _scale = 1 << (_z - _csvZ);
  static const Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://www.msil.go.jp/map/ja/',
    'Accept': 'application/json,image/*,*/*',
  };

  void Function(List<SnetStation> stations)? onDataUpdated;
  void Function(bool connected)? onStatusChanged;

  List<SnetStation> _stations = [];
  List<SnetStation> get stations => _stations;

  Timer? _updateTimer;
  bool _isMonitoring = false;
  int _consecutiveFailures = 0;

  String? _lastBasetime;

  static const List<Map<String, dynamic>> _stationDefs = [
    {"code": "N.S1N01", "lat": 35.8968, "lng": 141.0535, "x": 137, "y": 403},
    {"code": "N.S1N02", "lat": 35.8424, "lng": 141.3772, "x": 145, "y": 404},
    {"code": "N.S1N03", "lat": 35.7203, "lng": 141.6451, "x": 151, "y": 407},
    {"code": "N.S1N04", "lat": 35.6036, "lng": 141.9041, "x": 156, "y": 411},
    {"code": "N.S1N05", "lat": 35.4047, "lng": 142.0531, "x": 160, "y": 416},
    {"code": "N.S1N06", "lat": 35.2277, "lng": 141.8692, "x": 157, "y": 421},
    {"code": "N.S1N07", "lat": 35.2773, "lng": 141.5902, "x": 150, "y": 420},
    {"code": "N.S1N08", "lat": 35.4536, "lng": 141.3898, "x": 146, "y": 415},
    {"code": "N.S1N09", "lat": 35.227, "lng": 141.3068, "x": 143, "y": 421},
    {"code": "N.S1N10", "lat": 35.0925, "lng": 141.2021, "x": 141, "y": 425},
    {"code": "N.S1N11", "lat": 35.1203, "lng": 140.9682, "x": 134, "y": 424},
    {"code": "N.S1N12", "lat": 35.0228, "lng": 140.8091, "x": 131, "y": 427},
    {"code": "N.S1N13", "lat": 34.8788, "lng": 140.9627, "x": 134, "y": 430},
    {"code": "N.S1N14", "lat": 34.6407, "lng": 141.0907, "x": 138, "y": 437},
    {"code": "N.S1N15", "lat": 34.5256, "lng": 141.3512, "x": 144, "y": 441},
    {"code": "N.S1N16", "lat": 34.3686, "lng": 141.5402, "x": 149, "y": 445},
    {"code": "N.S1N17", "lat": 34.1956, "lng": 141.3341, "x": 145, "y": 450},
    {"code": "N.S1N18", "lat": 34.262, "lng": 141.0316, "x": 137, "y": 447},
    {"code": "N.S1N19", "lat": 34.2269, "lng": 140.7311, "x": 130, "y": 448},
    {"code": "N.S1N20", "lat": 34.2592, "lng": 140.4159, "x": 122, "y": 447},
    {"code": "N.S1N21", "lat": 34.4231, "lng": 140.203, "x": 117, "y": 443},
    {"code": "N.S1N22", "lat": 34.6443, "lng": 140.0906, "x": 116, "y": 437},
    {"code": "N.S2N01", "lat": 37.8428, "lng": 141.3845, "x": 146, "y": 347},
    {"code": "N.S2N02", "lat": 37.6922, "lng": 141.6387, "x": 151, "y": 350},
    {"code": "N.S2N03", "lat": 37.7073, "lng": 141.965, "x": 159, "y": 350},
    {"code": "N.S2N04", "lat": 37.6739, "lng": 142.2975, "x": 166, "y": 351},
    {"code": "N.S2N05", "lat": 37.6016, "lng": 142.6236, "x": 173, "y": 354},
    {"code": "N.S2N06", "lat": 37.5259, "lng": 142.935, "x": 180, "y": 357},
    {"code": "N.S2N07", "lat": 37.429, "lng": 143.2266, "x": 186, "y": 359},
    {"code": "N.S2N08", "lat": 37.222, "lng": 143.07, "x": 184, "y": 365},
    {"code": "N.S2N09", "lat": 37.0741, "lng": 142.8188, "x": 178, "y": 369},
    {"code": "N.S2N10", "lat": 37.0948, "lng": 142.4979, "x": 170, "y": 368},
    {"code": "N.S2N11", "lat": 37.1931, "lng": 142.1998, "x": 163, "y": 366},
    {"code": "N.S2N12", "lat": 37.2772, "lng": 141.879, "x": 157, "y": 364},
    {"code": "N.S2N13A", "lat": 37.3003, "lng": 141.5709, "x": 150, "y": 363},
    {"code": "N.S2N14", "lat": 37.0952, "lng": 141.3703, "x": 146, "y": 368},
    {"code": "N.S2N15", "lat": 36.8344, "lng": 141.3307, "x": 145, "y": 376},
    {"code": "N.S2N16", "lat": 36.662, "lng": 141.5207, "x": 149, "y": 381},
    {"code": "N.S2N17", "lat": 36.6337, "lng": 141.8389, "x": 156, "y": 382},
    {"code": "N.S2N18", "lat": 36.6824, "lng": 142.1445, "x": 162, "y": 380},
    {"code": "N.S2N19", "lat": 36.5986, "lng": 142.4389, "x": 169, "y": 382},
    {"code": "N.S2N20", "lat": 36.3885, "lng": 142.6164, "x": 173, "y": 389},
    {"code": "N.S2N21", "lat": 36.1577, "lng": 142.5553, "x": 172, "y": 394},
    {"code": "N.S2N22", "lat": 35.9463, "lng": 142.4014, "x": 169, "y": 401},
    {"code": "N.S2N23", "lat": 35.9677, "lng": 142.1138, "x": 162, "y": 400},
    {"code": "N.S2N24", "lat": 35.9976, "lng": 141.7944, "x": 155, "y": 399},
    {"code": "N.S2N25", "lat": 36.0729, "lng": 141.5095, "x": 148, "y": 397},
    {"code": "N.S2N26", "lat": 36.1442, "lng": 141.2021, "x": 141, "y": 396},
    {"code": "N.S3N01", "lat": 39.4497, "lng": 142.4578, "x": 170, "y": 299},
    {"code": "N.S3N02", "lat": 39.3746, "lng": 142.7918, "x": 176, "y": 302},
    {"code": "N.S3N03", "lat": 39.3231, "lng": 143.1206, "x": 185, "y": 303},
    {"code": "N.S3N04", "lat": 39.2958, "lng": 143.4544, "x": 192, "y": 304},
    {"code": "N.S3N05", "lat": 39.1906, "lng": 143.7499, "x": 199, "y": 307},
    {"code": "N.S3N06", "lat": 39.0459, "lng": 143.9305, "x": 204, "y": 312},
    {"code": "N.S3N07", "lat": 38.8308, "lng": 143.7846, "x": 200, "y": 318},
    {"code": "N.S3N08", "lat": 38.7826, "lng": 143.4769, "x": 192, "y": 319},
    {"code": "N.S3N09", "lat": 38.7739, "lng": 143.1437, "x": 186, "y": 320},
    {"code": "N.S3N10", "lat": 38.8668, "lng": 142.8212, "x": 178, "y": 317},
    {"code": "N.S3N11", "lat": 38.9349, "lng": 142.4873, "x": 170, "y": 315},
    {"code": "N.S3N12", "lat": 38.8412, "lng": 142.1816, "x": 163, "y": 318},
    {"code": "N.S3N13", "lat": 38.5901, "lng": 142.1816, "x": 163, "y": 325},
    {"code": "N.S3N14", "lat": 38.4993, "lng": 142.5002, "x": 171, "y": 327},
    {"code": "N.S3N15", "lat": 38.4487, "lng": 142.8376, "x": 178, "y": 329},
    {"code": "N.S3N16", "lat": 38.4262, "lng": 143.1703, "x": 186, "y": 329},
    {"code": "N.S3N17", "lat": 38.3978, "lng": 143.5139, "x": 194, "y": 330},
    {"code": "N.S3N18", "lat": 38.3063, "lng": 143.781, "x": 200, "y": 333},
    {"code": "N.S3N19", "lat": 38.0594, "lng": 143.7441, "x": 199, "y": 340},
    {"code": "N.S3N20", "lat": 37.9311, "lng": 143.5675, "x": 195, "y": 345},
    {"code": "N.S3N21", "lat": 37.9713, "lng": 143.2454, "x": 188, "y": 343},
    {"code": "N.S3N22", "lat": 37.9838, "lng": 142.9072, "x": 180, "y": 342},
    {"code": "N.S3N23", "lat": 38.027, "lng": 142.5735, "x": 172, "y": 341},
    {"code": "N.S3N24", "lat": 38.0569, "lng": 142.234, "x": 165, "y": 340},
    {"code": "N.S3N25", "lat": 38.0972, "lng": 141.8957, "x": 157, "y": 338},
    {"code": "N.S3N26", "lat": 38.106, "lng": 141.5572, "x": 149, "y": 338},
    {"code": "N.S4N01", "lat": 40.7881, "lng": 141.7895, "x": 155, "y": 259},
    {"code": "N.S4N02", "lat": 40.9069, "lng": 142.1057, "x": 162, "y": 256},
    {"code": "N.S4N03", "lat": 41.0156, "lng": 142.4314, "x": 169, "y": 253},
    {"code": "N.S4N04", "lat": 41.0762, "lng": 142.7706, "x": 177, "y": 251},
    {"code": "N.S4N05", "lat": 41.0443, "lng": 143.1138, "x": 185, "y": 253},
    {"code": "N.S4N06", "lat": 40.9718, "lng": 143.4481, "x": 192, "y": 254},
    {"code": "N.S4N07", "lat": 40.882, "lng": 143.7746, "x": 199, "y": 257},
    {"code": "N.S4N08", "lat": 40.7805, "lng": 144.0905, "x": 207, "y": 260},
    {"code": "N.S4N09", "lat": 40.5521, "lng": 144.1332, "x": 208, "y": 267},
    {"code": "N.S4N10", "lat": 40.4327, "lng": 143.8887, "x": 202, "y": 271},
    {"code": "N.S4N11", "lat": 40.4353, "lng": 143.543, "x": 195, "y": 271},
    {"code": "N.S4N12", "lat": 40.4515, "lng": 143.2015, "x": 186, "y": 270},
    {"code": "N.S4N13", "lat": 40.5196, "lng": 142.9617, "x": 181, "y": 269},
    {"code": "N.S4N14", "lat": 40.5927, "lng": 142.634, "x": 173, "y": 266},
    {"code": "N.S4N15", "lat": 40.5933, "lng": 142.2844, "x": 166, "y": 266},
    {"code": "N.S4N16", "lat": 40.3295, "lng": 142.2673, "x": 166, "y": 273},
    {"code": "N.S4N17", "lat": 40.1165, "lng": 142.3926, "x": 168, "y": 281},
    {"code": "N.S4N18", "lat": 40.1088, "lng": 142.6222, "x": 173, "y": 281},
    {"code": "N.S4N19", "lat": 40.0904, "lng": 142.9695, "x": 181, "y": 281},
    {"code": "N.S4N20", "lat": 40.0743, "lng": 143.321, "x": 189, "y": 282},
    {"code": "N.S4N21", "lat": 40.0863, "lng": 143.6572, "x": 197, "y": 281},
    {"code": "N.S4N22", "lat": 40.026, "lng": 143.9547, "x": 204, "y": 283},
    {"code": "N.S4N23", "lat": 39.7718, "lng": 143.9259, "x": 202, "y": 290},
    {"code": "N.S4N24", "lat": 39.6388, "lng": 143.7154, "x": 198, "y": 294},
    {"code": "N.S4N25", "lat": 39.6976, "lng": 143.3749, "x": 190, "y": 293},
    {"code": "N.S4N26", "lat": 39.7245, "lng": 143.0384, "x": 182, "y": 291},
    {"code": "N.S4N27", "lat": 39.7445, "lng": 142.6903, "x": 175, "y": 291},
    {"code": "N.S4N28", "lat": 39.7385, "lng": 142.3408, "x": 166, "y": 291},
    {"code": "N.S5N01", "lat": 42.7688, "lng": 145.7115, "x": 244, "y": 199},
    {"code": "N.S5N02", "lat": 42.6403, "lng": 145.4063, "x": 237, "y": 203},
    {"code": "N.S5N03", "lat": 42.4802, "lng": 145.1433, "x": 230, "y": 208},
    {"code": "N.S5N04", "lat": 42.2286, "lng": 145.204, "x": 231, "y": 217},
    {"code": "N.S5N05", "lat": 42.0615, "lng": 145.437, "x": 237, "y": 220},
    {"code": "N.S5N06", "lat": 41.884, "lng": 145.6544, "x": 243, "y": 227},
    {"code": "N.S5N07", "lat": 41.6637, "lng": 145.5291, "x": 239, "y": 233},
    {"code": "N.S5N08", "lat": 41.5301, "lng": 145.2483, "x": 232, "y": 238},
    {"code": "N.S5N09", "lat": 41.521, "lng": 144.905, "x": 225, "y": 238},
    {"code": "N.S5N10", "lat": 41.6541, "lng": 144.6716, "x": 220, "y": 235},
    {"code": "N.S5N11", "lat": 41.9072, "lng": 144.6955, "x": 220, "y": 226},
    {"code": "N.S5N12", "lat": 42.0784, "lng": 144.6375, "x": 219, "y": 220},
    {"code": "N.S5N13", "lat": 41.9792, "lng": 144.3445, "x": 212, "y": 224},
    {"code": "N.S5N14", "lat": 41.7475, "lng": 144.1779, "x": 209, "y": 231},
    {"code": "N.S5N15", "lat": 41.4961, "lng": 144.0879, "x": 207, "y": 238},
    {"code": "N.S5N16", "lat": 41.3742, "lng": 143.8006, "x": 200, "y": 242},
    {"code": "N.S5N17", "lat": 41.3643, "lng": 143.453, "x": 192, "y": 243},
    {"code": "N.S5N18", "lat": 41.4351, "lng": 143.1264, "x": 185, "y": 240},
    {"code": "N.S5N19", "lat": 41.5607, "lng": 142.8177, "x": 178, "y": 236},
    {"code": "N.S5N20", "lat": 41.6095, "lng": 142.4787, "x": 170, "y": 235},
    {"code": "N.S5N21", "lat": 41.4248, "lng": 142.2193, "x": 165, "y": 240},
    {"code": "N.S5N22", "lat": 41.1989, "lng": 142.0271, "x": 160, "y": 248},
    {"code": "N.S5N23", "lat": 40.954, "lng": 141.8762, "x": 157, "y": 255},
    {"code": "N.S6N01", "lat": 42.8064, "lng": 146.0211, "x": 250, "y": 198},
    {"code": "N.S6N02", "lat": 42.5807, "lng": 146.078, "x": 251, "y": 206},
    {"code": "N.S6N03", "lat": 42.0943, "lng": 146.2316, "x": 254, "y": 221},
    {"code": "N.S6N04", "lat": 41.6653, "lng": 146.1747, "x": 254, "y": 233},
    {"code": "N.S6N05", "lat": 41.3717, "lng": 145.6053, "x": 241, "y": 243},
    {"code": "N.S6N06", "lat": 40.8999, "lng": 145.3929, "x": 236, "y": 256},
    {"code": "N.S6N07", "lat": 40.536, "lng": 144.9381, "x": 226, "y": 267},
    {"code": "N.S6N08", "lat": 40.0319, "lng": 144.8089, "x": 222, "y": 283},
    {"code": "N.S6N09", "lat": 39.5172, "lng": 144.7191, "x": 221, "y": 297},
    {"code": "N.S6N10", "lat": 39.0072, "lng": 144.5915, "x": 218, "y": 313},
    {"code": "N.S6N11", "lat": 38.499, "lng": 144.4536, "x": 215, "y": 327},
    {"code": "N.S6N12", "lat": 37.9879, "lng": 144.3357, "x": 212, "y": 342},
    {"code": "N.S6N13", "lat": 37.4862, "lng": 144.1757, "x": 209, "y": 357},
    {"code": "N.S6N14", "lat": 37.012, "lng": 143.9557, "x": 204, "y": 370},
    {"code": "N.S6N15", "lat": 36.5748, "lng": 143.6059, "x": 196, "y": 383},
    {"code": "N.S6N16", "lat": 36.1262, "lng": 143.2823, "x": 188, "y": 396},
    {"code": "N.S6N17", "lat": 35.6745, "lng": 142.9688, "x": 181, "y": 409},
    {"code": "N.S6N18", "lat": 35.2114, "lng": 142.6799, "x": 175, "y": 422},
    {"code": "N.S6N19", "lat": 34.7118, "lng": 142.5208, "x": 171, "y": 435},
    {"code": "N.S6N20", "lat": 34.2604, "lng": 142.2389, "x": 165, "y": 447},
    {"code": "N.S6N21", "lat": 33.9619, "lng": 141.7291, "x": 153, "y": 456},
    {"code": "N.S6N22", "lat": 33.8601, "lng": 141.1281, "x": 139, "y": 459},
    {"code": "N.S6N23", "lat": 33.9448, "lng": 140.5189, "x": 124, "y": 456},
    {"code": "N.S6N24", "lat": 34.1773, "lng": 139.9814, "x": 112, "y": 449},
    {"code": "N.S6N25", "lat": 34.6696, "lng": 139.8167, "x": 109, "y": 437},
  ];

  void _initStations() {
    if (_stations.isNotEmpty) return;
    _stations = _stationDefs.map((s) {
      final csvX = (s['x'] as int);
      final csvY = (s['y'] as int);
      return SnetStation(
        code: s['code'] as String,
        name: s['code'] as String,
        coordinate: LatLng(
          (s['lat'] as num).toDouble(),
          (s['lng'] as num).toDouble(),
        ),
        depth: 0,
        network: 'S-net',
        type: 'velocity',
        pixelX: csvX * _scale,
        pixelY: csvY * _scale,
      );
    }).toList();
    debugPrint(
      '[S-net] ${_stations.length} stations initialized from tile positions',
    );
  }

  Future<void> startMonitoring({int intervalSeconds = 10}) async {
    if (_isMonitoring) return;
    _initStations();
    _isMonitoring = true;
    onStatusChanged?.call(true);
    await fetchLatestData();
    _updateTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => fetchLatestData(),
    );
    debugPrint('[S-net] Monitoring started (间隔: ${intervalSeconds}s)');
  }

  void stopMonitoring() {
    _updateTimer?.cancel();
    _updateTimer = null;
    _isMonitoring = false;
    onStatusChanged?.call(false);
    debugPrint('[S-net] Monitoring stopped');
  }

  Future<void> fetchLatestData() async {
    _initStations();
    try {
      final success = await _fetchAndParseTiles();
      if (success) {
        _consecutiveFailures = 0;
        onStatusChanged?.call(true);
        return;
      }
    } catch (e) {
      debugPrint('[S-net] 数据获取失败: $e');
    }
    _onFetchFailed();
  }

  Future<bool> _fetchAndParseTiles() async {
    final stopwatch = Stopwatch()..start();
    debugPrint('[S-net] ===== 开始新一轮数据获取 =====');
    final times = await _fetchTargetTimes();
    if (times == null) {
      debugPrint('[S-net] ✗ targetTimes.json 获取失败');
      return false;
    }
    final basetime = times['basetime'] as String;
    final validtime = times['validtime'] as String;
    debugPrint('[S-net] basetime=$basetime validtime=$validtime');
    if (basetime == _lastBasetime) {
      debugPrint('[S-net] basetime 未变化，跳过本轮');
      return true;
    }
    _lastBasetime = basetime;

    final rawRgba = await _downloadAndStitch(basetime, validtime);
    if (rawRgba == null) {
      debugPrint('[S-net] ✗ 瓦片下载/拼接失败');
      return false;
    }
    stopwatch.reset();
    _processImageData(rawRgba);
    debugPrint('[S-net] 解析像素耗时: ${stopwatch.elapsedMilliseconds}ms');
    stopwatch.stop();

    onDataUpdated?.call(_stations);
    debugPrint('[S-net] ===== 本轮完成 =====');
    return true;
  }

  Future<Map<String, String>?> _fetchTargetTimes() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/targetTimes.json'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final List<dynamic> times = jsonDecode(response.body);
      if (times.isEmpty) return null;
      final latest = times.last as Map<String, dynamic>;
      return {
        'basetime': latest['basetime'] as String,
        'validtime': latest['validtime'] as String,
      };
    } catch (e) {
      debugPrint('[S-net] targetTimes.json 请求失败: $e');
      return null;
    }
  }

  Future<Int32List?> _downloadAndStitch(
    String basetime,
    String validtime,
  ) async {
    final stopwatch = Stopwatch()..start();
    final totalTiles = (_xMax - _xMin + 1) * (_yMax - _yMin + 1);
    debugPrint(
      '[S-net] 开始下载瓦片 z=$_z x=$_xMin..$_xMax y=$_yMin..$_yMax 共$totalTiles张',
    );
    final result = Int32List(_imgW * _imgH);
    int usedTiles = 0;
    int failedTiles = 0;
    try {
      for (int y = _yMin; y <= _yMax; y++) {
        for (int x = _xMin; x <= _xMax; x++) {
          final tileData = await _downloadTile(basetime, validtime, _z, x, y);
          if (tileData == null) {
            debugPrint('[S-net] ✗ tile z=$_z x=$x y=$y 下载失败');
            failedTiles++;
            continue;
          }
          final tileX = (x - _xMin) * _tileSize;
          final tileY = (y - _yMin) * _tileSize;
          for (int py = 0; py < _tileSize; py++) {
            for (int px = 0; px < _tileSize; px++) {
              final srcIdx = (py * _tileSize + px) * 4;
              final r = tileData[srcIdx];
              final g = tileData[srcIdx + 1];
              final b = tileData[srcIdx + 2];
              final a = tileData[srcIdx + 3];
              if (a < 128) continue;
              final dstIdx = (tileY + py) * _imgW + (tileX + px);
              result[dstIdx] = (r << 16) | (g << 8) | b;
            }
          }
          usedTiles++;
        }
      }
      final elapsed = stopwatch.elapsedMilliseconds;
      debugPrint(
        '[S-net] 瓦片下载完成: $usedTiles/$totalTiles 成功, $failedTiles 失败, 耗时 ${elapsed}ms',
      );
      stopwatch.stop();
      return usedTiles > 0 ? result : null;
    } catch (e) {
      debugPrint('[S-net] 瓦片拼接异常: $e');
      stopwatch.stop();
      return null;
    }
  }

  Future<Uint8List?> _downloadTile(
    String basetime,
    String validtime,
    int z,
    int x,
    int y,
  ) async {
    try {
      final url = '$_baseUrl/tileimage/$basetime/$validtime/$z/$x/$y.png';
      final response = await http
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        debugPrint(
          '[S-net] tile HTTP ${response.statusCode} len=${response.bodyBytes.length} z=$z x=$x y=$y',
        );
        return null;
      }
      debugPrint(
        '[S-net] ✓ tile z=$z x=$x y=$y -> ${response.bodyBytes.length} bytes',
      );
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      if (byteData == null) {
        debugPrint('[S-net] ✗ tile z=$z x=$x y=$y byteData is null');
        return null;
      }
      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('[S-net] ✗ tile z=$z x=$x y=$y 异常: $e');
      return null;
    }
  }

  void _processImageData(Int32List packedRgb) {
    final stamp = DateTime.now();
    int activeCount = 0;
    final activeStations = <String>[];
    for (int i = 0; i < _stations.length; i++) {
      final s = _stations[i];
      final x = s.pixelX;
      final y = s.pixelY;
      if (x < 0 || x >= _imgW || y < 0 || y >= _imgH) {
        debugPrint('[S-net] 测站 ${s.code} 像素坐标越界 ($x,$y) 图像=$_imgW x $_imgH');
        continue;
      }
      final rgb = packedRgb[y * _imgW + x];
      if (rgb == 0) {
        s.isActive = false;
        continue;
      }
      final r = (rgb >> 16) & 0xFF;
      final g = (rgb >> 8) & 0xFF;
      final b = rgb & 0xFF;
      final shindo = ShindoColorUtil.rgbaToShindo(r, g, b);
      final rawLevel = shindo == null
          ? -1
          : ShindoColorUtil.shindoToRawLevel(shindo);
      if (rawLevel == -1) {
        s.isActive = false;
        continue;
      }
      final parsedShindo = shindo!;
      s.level = rawLevel;
      s.shindo = parsedShindo;
      s.intensity = s.shindo;
      s.lastUpdate = stamp;
      s.isActive = true;
      activeCount++;
      if (s.shindo >= 0.5) {
        activeStations.add('${s.code}(shindo ${s.shindo.toStringAsFixed(1)})');
      }
    }
    debugPrint('[S-net] 像素解析完成: $activeCount/${_stations.length} 活跃');
    if (activeStations.isNotEmpty) {
      debugPrint('[S-net] 活跃测站详情: ${activeStations.join(", ")}');
    } else {
      debugPrint('[S-net] 无显著震度测站');
    }
  }

  void _onFetchFailed() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= 3) {
      onStatusChanged?.call(false);
      debugPrint('[S-net] 连续 $_consecutiveFailures 次失败，标记为断开');
    }
    if (_consecutiveFailures % 10 == 0) {
      debugPrint('[S-net] 已累计失败 $_consecutiveFailures 次');
    }
  }

  List<SnetStation> getActiveStations() {
    return _stations.where((s) => s.isActive).toList();
  }

  double getMaxShindo() {
    final active = getActiveStations();
    if (active.isEmpty) return 0.0;
    return active.map((s) => s.shindo).reduce((a, b) => a > b ? a : b);
  }

  bool get isMonitoring => _isMonitoring;

  void dispose() {
    stopMonitoring();
    _stations.clear();
  }
}

class SnetConfig {
  static const String publicDataUrl =
      'https://www.data.jma.go.jp/svd/eqev/data/daily_map/';
  static const Map<String, String> regions = {
    'S01': '北海道东部',
    'S02': '青森县冲',
    'S03': '岩手县冲',
    'S04': '宫城县冲',
    'S05': '福岛县冲',
    'S06': '茨城县冲',
    'S07': '千叶县冲',
  };

  static String getRegion(String stationCode) {
    if (stationCode.length < 3) return '未知区域';
    final parts = stationCode.split('.');
    final code = parts.length > 1 ? parts[1] : stationCode;
    if (code.length < 3) return '未知区域';
    final regionPrefix = code.substring(0, 3);
    return regions[regionPrefix] ?? '未知区域';
  }
}
