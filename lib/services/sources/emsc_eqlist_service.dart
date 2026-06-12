import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/quake_message.dart';
import '../../utils/fe_regions.dart';
import '../../core/intensity_calculator.dart';

class EmscEqlistService {
  static final EmscEqlistService _instance = EmscEqlistService._internal();
  factory EmscEqlistService() => _instance;
  EmscEqlistService._internal();

  static const String _url =
      'https://www.seismicportal.eu/fdsnws/event/1/query?format=json&limit=50&orderby=time&minmag=3.0';

  Timer? _timer;
  final List<QuakeMessage> _latestList = [];
  List<QuakeMessage> get latestList => List.unmodifiable(_latestList);

  void Function(List<QuakeMessage>)? onListUpdated;

  void start({Duration interval = const Duration(seconds: 60)}) {
    _timer?.cancel();
    _fetch();
    _timer = Timer.periodic(interval, (_) => _fetch());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _fetch() async {
    try {
      final resp = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;

      final data = json.decode(resp.body);
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return;

      _latestList.clear();
      for (final f in features) {
        final props = f['properties'];
        if (props == null) continue;
        final geom = f['geometry'];
        if (geom == null) continue;

        final coords = geom['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;

        final double magnitude =
            double.tryParse(props['mag']?.toString() ?? '') ?? 0.0;
        final double longitude =
            double.tryParse(coords[0]?.toString() ?? '') ?? 0.0;
        final double latitude =
            double.tryParse(coords[1]?.toString() ?? '') ?? 0.0;
        final double depth =
            double.tryParse(props['depth']?.toString() ?? '') ?? 0.0;

        final String timeStr = props['time']?.toString() ?? '';
        final DateTime originTimeUtc = DateTime.tryParse(timeStr) ?? DateTime.now();
        final DateTime originTime = originTimeUtc.toUtc().add(const Duration(hours: 8));

        final String eventId = props['unid']?.toString() ??
            f['id']?.toString() ??
            'emsc_${originTimeUtc.millisecondsSinceEpoch}';

        final String region = props['flynn_region']?.toString() ??
            props['region']?.toString() ??
            '';
        final String cnPlace = getFEName(latitude, longitude);
        final String location = cnPlace.isNotEmpty ? cnPlace : region;

        final int maxIntensity =
            IntensityCalculator.calcCsisLevel(magnitude, depth, 0);

        final String auth = props['auth']?.toString() ?? 'EMSC';

        _latestList.add(QuakeMessage(
          source: QuakeSourceType.emsc,
          eventId: eventId,
          location: location,
          magnitude: magnitude,
          latitude: latitude,
          longitude: longitude,
          depth: depth,
          originTime: originTime,
          isHistory: true,
          maxIntensity: maxIntensity,
          reviewType: '自动测定',
          infoTypeName: auth,
          isInfoEvent: true,
        ));
      }

      onListUpdated?.call(_latestList);
    } catch (_) {}
  }
}