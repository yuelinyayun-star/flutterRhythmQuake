import 'package:flutter_test/flutter_test.dart';
import 'package:flutterrhythmquake/services/sources/jma_ashfall_forecast_service.dart';

void main() {
  test('parses JMA AshInfo windows without inventing optional values', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<Report>
  <Head><EventID>506</EventID></Head>
  <Body>
    <AshInfo type="予報　３時間後">
      <StartTime>2026-08-07T14:00:00+09:00</StartTime>
      <EndTime>2026-08-07T17:00:00+09:00</EndTime>
      <Item>
        <Kind>
          <Name>降灰</Name><Code>70</Code>
          <Property>
            <jmx_eb:Polygon>+30.10+129.20/+30.30+129.40/+30.20+129.60/+30.10+129.20/</jmx_eb:Polygon>
            <jmx_eb:PlumeDirection>西</jmx_eb:PlumeDirection>
            <Distance unit="km">100</Distance>
          </Property>
        </Kind>
        <Areas>
          <Area><Name>鹿児島県屋久島町</Name><Code>4650500</Code></Area>
        </Areas>
      </Item>
      <Item>
        <Kind>
          <Name>小さな噴石の落下</Name><Code>75</Code>
          <Property>
            <Size unit="cm">1</Size>
            <jmx_eb:Polygon>+31.50+130.60/+31.60+130.70/+31.55+130.80/+31.50+130.60/</jmx_eb:Polygon>
            <Distance unit="km">6</Distance>
          </Property>
        </Kind>
        <Areas><Area><Name>鹿児島市</Name><Code>4620100</Code></Area></Areas>
      </Item>
    </AshInfo>
  </Body>
</Report>''';

    final windows = JmaAshfallForecastService().parseDetailForTesting(xml);

    expect(windows, hasLength(1));
    final window = windows.single;
    expect(window.label, '予報　３時間後');
    expect(window.startTime?.toUtc().hour, 5);
    expect(window.endTime?.toUtc().hour, 8);
    expect(window.items, hasLength(2));

    final ashfall = window.items.first;
    expect(ashfall.phenomenon, '降灰');
    expect(ashfall.phenomenonCode, '70');
    expect(ashfall.areaNames, ['鹿児島県屋久島町']);
    expect(ashfall.areaCodes, ['4650500']);
    expect(ashfall.plumeDirection, '西');
    expect(ashfall.distanceKm, 100);
    expect(ashfall.sizeCm, isNull);
    expect(ashfall.polygons.single.first.latitude, 30.10);
    expect(ashfall.polygons.single[1].longitude, 129.40);

    final pyroclast = window.items.last;
    expect(pyroclast.phenomenon, '小さな噴石の落下');
    expect(pyroclast.distanceKm, 6);
    expect(pyroclast.sizeCm, 1);
    expect(pyroclast.plumeDirection, isEmpty);
    expect(pyroclast.polygons.single, hasLength(4));
  });
}
