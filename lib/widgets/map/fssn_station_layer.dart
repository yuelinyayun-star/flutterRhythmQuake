import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/background_station_connection.dart';
import '../../models/fssn_station_frame.dart';
import '../../providers/background_settings_provider.dart';
import '../../services/sources/fssn_station_map_service.dart';
import 'station_dot_painter_layer.dart';

class FssnStationLayer extends StatefulWidget {
  const FssnStationLayer({super.key, this.service});
  final FssnStationMapService? service;

  @override
  State<FssnStationLayer> createState() => _FssnStationLayerState();
}

class _FssnStationLayerState extends State<FssnStationLayer>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? FssnStationMapService();
  List<StationDot> _dots = const [];
  bool _uiHidden = false;
  bool _pauseInBackground = false;
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _service.addListener(_update);
    _dots = _makeDots(_service.value);
    if (_isAndroid) {
      final state = WidgetsBinding.instance.lifecycleState;
      _uiHidden =
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isAndroid) {
      final settings = context.watch<BackgroundSettingsProvider?>();
      _pauseInBackground =
          settings?.enabled == true &&
          !settings!.keepsStationConnected(BackgroundStationConnection.fssn);
    }
    _syncConnection();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    final hidden = state != AppLifecycleState.resumed;
    if (_uiHidden == hidden) return;
    _uiHidden = hidden;
    _syncConnection();
  }

  void _syncConnection() {
    if (_uiHidden && _pauseInBackground) {
      _service.stop();
    } else {
      _service.start();
    }
  }

  void _update() {
    final next = _makeDots(_service.value);
    // PGA changes within a color bucket do not invalidate the map layer.
    var changed = next.length != _dots.length;
    for (var i = 0; !changed && i < next.length; i++) {
      changed =
          next[i].coordinate != _dots[i].coordinate ||
          next[i].color != _dots[i].color;
    }
    if (!changed) return;
    setState(() => _dots = next);
  }

  List<StationDot> _makeDots(FssnStationFrame? frame) => [
    for (final station in frame?.stations ?? const <FssnStationReading>[])
      StationDot(
        coordinate: LatLng(station.latitude, station.longitude),
        color: Color(station.argb),
        radius: 3,
        fillOpacity: 1,
        borderOpacity: 1,
        borderWidth: 1,
      ),
  ];

  @override
  void dispose() {
    if (_isAndroid) WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_update);
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StationDotPainterLayer(dots: _dots, sizeWithCameraZoom: true);
}
