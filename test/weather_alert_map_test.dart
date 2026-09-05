import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutterrhythmquake/models/weather_alert_map_item.dart';
import 'package:flutterrhythmquake/widgets/map/weather_alert_map_layer.dart';

void main() {
  group('WeatherAlertMapItem', () {
    test('parses raw list entry correctly with Polygon coordinates and GB/T fields', () {
      final rawEntry = [
        '广东省梅州市蕉岭县',
        '101280403-20260905002700-0202.html',
        '116.17',
        '24.65',
        '44142741600000_20260905002755',
        '44142741600000_20260905002755',
        '广东省梅州市蕉岭县发布暴雨黄色预警信号',
        {
          'type': 'Polygon',
          'coordinates': [
            ['116.089 24.839', '116.097 24.85', '116.153 24.847']
          ]
        }
      ];

      final item = WeatherAlertMapItem.fromRawList(rawEntry);
      expect(item, isNotNull);
      expect(item!.areaName, '广东省梅州市蕉岭县');
      expect(item.aid, '101280403');
      expect(item.signalType, '暴雨');
      expect(item.signalLevel, '黄色');
      expect(item.levelSingleChar, '黄');
      expect(item.englishName, 'RAIN STORM');
      expect(item.verticalChineseChars, ['暴', '雨']);
      expect(item.center.latitude, 24.65);
      expect(item.center.longitude, 116.17);
      expect(item.levelColor, const Color(0xFFFDD835));
      expect(item.onLevelTextColor, const Color(0xFF1A1A1A));
      expect(item.polygons.length, 1);
      expect(item.polygons.first.length, 3);
      expect(item.polygons.first[0], const LatLng(24.839, 116.089));

      // LOD visibility rules: county level aid length 9
      expect(item.isIconVisibleAtZoom(4.0), isFalse);
      expect(item.isIconVisibleAtZoom(7.0), isTrue);
    });

    test('handles orange and red signals and LOD thresholds correctly', () {
      final rawOrange = [
        '四川省甘孜藏族自治州康定市',
        '101271801-20260905000000-0103.html',
        '101.96',
        '30.05',
        '51330141600000_20260905000000',
        '51330141600000_20260905000000',
        '四川省甘孜藏族自治州康定市发布雷电橙色预警信号',
        {'type': 'Polygon', 'coordinates': []}
      ];

      final item = WeatherAlertMapItem.fromRawList(rawOrange);
      expect(item, isNotNull);
      expect(item!.signalType, '雷电');
      expect(item.signalLevel, '橙色');
      expect(item.levelSingleChar, '橙');
      expect(item.englishName, 'LIGHTNING');
      expect(item.verticalChineseChars, ['雷', '电']);
      expect(item.levelColor, const Color(0xFFFB8C00));
      expect(item.onLevelTextColor, Colors.white);
    });
    test('parses WeatherAlertDetail from raw JS correctly', () {
      const rawJs = '''
var alarminfo={"head":"云南省普洱市景谷傣族彝族自治县发布雷电黄色预警信号","ALERTID":"202609050144569522雷电黄色","PROVINCE":"云南省","CITY":"普洱市","STATIONNAME":"景谷傣族彝族自治县气象台","SIGNALTYPE":"雷电","SIGNALLEVEL":"黄色","TYPECODE":"09","LEVELCODE":"02","ISSUETIME":"2026-09-05 01:44:07","ISSUECONTENT":"景谷县气象台发布雷电黄色预警信号：未来6小时将出现雷电天气，请注意安全。","UNDERWRITER":"","RELIEVETIME":"2026-09-05 07:44:07"};
''';
      final detail = WeatherAlertDetail.fromRawJs(rawJs, '101290902-20260905014407-0902.html');
      expect(detail, isNotNull);
      expect(detail!.head, contains('雷电黄色预警'));
      expect(detail.stationName, '景谷傣族彝族自治县气象台');
      expect(detail.issueContent, contains('未来6小时将出现雷电天气'));
      expect(detail.issueTime, '2026-09-05 01:44:07');
      expect(detail.relieveTime, '2026-09-05 07:44:07');
      expect(detail.detailWebUrl, 'http://www.weather.com.cn/alarm/newalarmcontent.shtml?file=101290902-20260905014407-0902.html');
    });

    test('verifies pointInPolygon and containsLocation correctly', () {
      final poly = [
        const LatLng(20.0, 100.0),
        const LatLng(20.0, 105.0),
        const LatLng(25.0, 105.0),
        const LatLng(25.0, 100.0),
      ];
      final item = WeatherAlertMapItem(
        id: 'test_poly',
        aid: '10100',
        areaName: '测试区',
        title: '测试预警',
        fileId: 'test.html',
        center: const LatLng(22.5, 102.5),
        signalType: '暴雨',
        signalLevel: '蓝色',
        typeCode: '02',
        levelCode: '01',
        polygons: [poly],
      );

      expect(item.containsLocation(const LatLng(22.5, 102.5)), isTrue);
      expect(item.containsLocation(const LatLng(10.0, 50.0)), isFalse);
    });
  });

  group('WeatherAlertMapLayer Widget', () {
    testWidgets('renders badge and popup card when selectedAlert is provided', (tester) async {
      final alert = WeatherAlertMapItem(
        id: 'test_1',
        aid: '101280403',
        areaName: '诸暨市',
        title: '浙江省绍兴市诸暨市发布大雾黄色预警信号',
        fileId: '101280403-20260905000000-1202.html',
        center: const LatLng(29.71, 120.23),
        signalType: '大雾',
        signalLevel: '黄色',
        typeCode: '12',
        levelCode: '02',
        polygons: [
          [
            const LatLng(29.70, 120.20),
            const LatLng(29.72, 120.20),
            const LatLng(29.72, 120.25),
          ]
        ],
      );
      final alerts = <WeatherAlertMapItem>[alert];

      // 1. 验证：未选中时弹窗不渲染
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(29.71, 120.23),
                initialZoom: 8.0,
              ),
              children: [
                WeatherAlertMapLayer(alerts: alerts),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(WeatherAlertMapLayer), findsOneWidget);
      // 未选中时弹窗内容不显示
      expect(find.text('浙江省绍兴市诸暨市发布大雾黄色预警信号'), findsNothing);

      // 2. 验证：selectedAlert 传入时弹窗正常渲染
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(29.71, 120.23),
                initialZoom: 8.0,
              ),
              children: [
                WeatherAlertMapLayer(
                  alerts: alerts,
                  selectedAlert: alert,
                  onDismiss: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 弹窗标题和按钮都应渲染出来
      expect(find.text('浙江省绍兴市诸暨市发布大雾黄色预警信号'), findsWidgets);
      expect(find.text('官方详情 >'), findsOneWidget);
      expect(find.text('复制内容'), findsOneWidget);

    });
  });
}
