import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/utils/geo_loader.dart';
import '../../providers/map_state_provider.dart';
import 'map_sources.dart';

class ComplianceMapView extends StatelessWidget {
  const ComplianceMapView({super.key});

  @override
  Widget build(BuildContext context) {
    const String tdtKey = ChinaMapSources.tdtKey;

    return FutureBuilder<List<List<LatLng>>>(
      future: GeoLoader.loadChinaBoundary(),
      builder: (context, snapshot) {
        final mapState = context.watch<MapStateProvider>();
        return FlutterMap(
          options: MapOptions(
            initialCenter: mapState.defaultCenter,
            initialZoom: mapState.defaultZoom,
          ),
          children: [
            // 1. 底图层 (天地图矢量)
            TileLayer(
              urlTemplate: ChinaMapSources.tiandituVec(tdtKey),
              subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
              userAgentPackageName: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            ),
            // 矢量注记
            TileLayer(
              urlTemplate: ChinaMapSources.tiandituCva(tdtKey),
              subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
              userAgentPackageName: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            ),

            // 2. 行政边界纠偏层 (使用 GeoJSON)
            if (snapshot.hasData)
              PolygonLayer(
                polygons: snapshot.data!.map((polyPoints) => Polygon(
                  points: polyPoints,
                  color: Colors.transparent,
                  borderColor: Colors.blueGrey.withValues(alpha: 0.8), // 边界线颜色
                  borderStrokeWidth: 1.5,
                )).toList(),
              ),
          ],
        );
      },
    );
  }
}
