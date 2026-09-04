import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// 地理数据加载器
///
/// 该类提供地理数据文件的加载和解析功能。
/// 主要用于加载GeoJSON格式的边界数据。
///
/// 主要功能：
/// - 加载中国边界GeoJSON数据
/// - 解析Polygon和MultiPolygon类型
/// - 转换坐标格式
class GeoLoader {
  /// 加载并解析中国边界GeoJSON数据
  ///
  /// 从assets目录加载中华人民共和国边界数据。
  /// 支持Polygon和MultiPolygon两种几何类型。
  ///
  /// GeoJSON结构说明：
  /// - Polygon: 单个多边形，坐标为三维数组 [[[lng, lat], ...]]
  /// - MultiPolygon: 多个多边形，坐标为四维数组 [[[[lng, lat], ...], ...], ...]
  ///
  /// 返回所有多边形的顶点列表
  /// 每个多边形由一组LatLng坐标点组成
  static Future<List<List<LatLng>>> loadChinaBoundary() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/maps/中华人民共和国.geojson',
      );
      final Map<String, dynamic> data = json.decode(response);

      List<List<LatLng>> allPolygons = [];

      var features = data['features'] as List;
      for (var feature in features) {
        var geometry = feature['geometry'];
        var type = geometry['type'];
        var coordinates = geometry['coordinates'];

        if (type == 'Polygon') {
          allPolygons.add(_convertCoords(coordinates[0]));
        } else if (type == 'MultiPolygon') {
          for (var polygonCoords in coordinates) {
            allPolygons.add(_convertCoords(polygonCoords[0]));
          }
        }
      }
      return allPolygons;
    } catch (e) {
      print("GeoJSON 解析错误: $e");
      return [];
    }
  }

  /// 将GeoJSON坐标数组转换为LatLng列表
  ///
  /// GeoJSON使用 [lng, lat] 格式存储坐标，
  /// 需要转换为 [lat, lng] 格式的LatLng对象。
  ///
  /// [coords] GeoJSON坐标数组 [[lng, lat], ...]
  /// 返回LatLng列表
  static List<LatLng> _convertCoords(List coords) {
    return coords.map<LatLng>((point) {
      return LatLng(point[1].toDouble(), point[0].toDouble());
    }).toList();
  }
}
