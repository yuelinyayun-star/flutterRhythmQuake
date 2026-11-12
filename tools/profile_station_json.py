"""Generate an instrumented copy; production receives no timing branches."""
from pathlib import Path

out = Path('build/performance')
source = Path('lib/services/sources/station_json_decoder_io.dart').read_text(encoding='utf-8')
source = source.replace("'../../models/source_payload.dart'", "'package:flutterrhythmquake/models/source_payload.dart'")
source = source.replace("'native_station_core_library_io.dart'", "'package:flutterrhythmquake/services/sources/native_station_core_library_io.dart'")
source = source.replace('class StationJsonDecoder {', '''final phases = <String, int>{'inputUs':0,'nativeUs':0,'copyUs':0,'viewUs':0};
class StationJsonDecoder {''')
source = source.replace('    final encoded =', '    final timer = Stopwatch()..start();\n    final encoded =')
source = source.replace('    final status =', "    phases['inputUs'] = phases['inputUs']! + timer.elapsedMicroseconds; timer.reset();\n    final status =")
source = source.replace('    if (status != 0) {', '''    phases['nativeUs'] = phases['nativeUs']! + timer.elapsedMicroseconds; timer.reset();
    if (status != 0) {''')
source = source.replace('    return PackedSourceJson(owned).root;', '''    phases['copyUs'] = phases['copyUs']! + timer.elapsedMicroseconds; timer.reset();
    final root = PackedSourceJson(owned).root;
    phases['viewUs'] = phases['viewUs']! + timer.elapsedMicroseconds;
    return root;''')
(out/'station_json_profile_decoder.dart').write_text(source,encoding='utf-8',newline='\n')
main = '''import 'dart:io';
import 'dart:convert';
import 'station_json_profile_decoder.dart';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/station_json_values.dart';
void main() {
 final text=File('test/fixtures/whews_nied/observations.json').readAsStringSync();
 final decoder=StationJsonDecoder();
 var consumeUs=0,checksum=0.0;
 for(var i=0;i<2000;i++) {
  final root=decoder.decode(text) as Map<String,dynamic>;
  final timer=Stopwatch()..start();
  final snapshot=snapshotSourcePayload(Map<String,dynamic>.from(root));
  final data=snapshot['Data'] as Map;
  final a=readStationJsonNumbers(data['shindo'] as List,minimum:-3,maximum:7)!;
  final b=readStationJsonNumbers(data['pga'] as List,minimum:0)!;
  final c=readStationJsonNumbers(data['pgv'] as List,minimum:0)!;
  for(var j=0;j<a.length;j++){checksum+=a[j]+b[j]+c[j];}
  consumeUs+=timer.elapsedMicroseconds;
 }
 decoder.dispose();
 print(jsonEncode({...phases,'consumeUs':consumeUs,'frames':2000,'checksum':checksum}));
}
'''
(out/'station_json_phase_main.dart').write_text(main,encoding='utf-8',newline='\n')
