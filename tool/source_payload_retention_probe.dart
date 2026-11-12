import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutterrhythmquake/models/source_payload.dart';
import 'package:flutterrhythmquake/services/sources/api_json_decoder.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  final raw=File('test/fixtures/catalog_20260917/whews_all.json').readAsBytesSync();
  final uri=(await dev.Service.getInfo()).serverUri!;
  final vm=await vmServiceConnectUri(uri.replace(scheme:'ws',path:'${uri.path}ws').toString());
  final isolate=(await vm.getVM()).isolates!.first.id!;
  Future<Map<String,dynamic>> heap() async => (await vm.getAllocationProfile(isolate,gc:true)).memoryUsage!.toJson();
  final retained=<Map<String,dynamic>>[];
  final result=<String,dynamic>{'sourceBytes':raw.length,'baseline':await heap()};
  for(var round=0;round<4;round++) {
    for(var i=0;i<100;i++) {
      final all=decodeApiJsonBytes(raw) as List;
      final frame=all.firstWhere((f)=>f['source']=='jma_eew') as Map;
      retained.add(snapshotSourcePayload(frame['Data'] as Map<String,dynamic>));
    }
    final bytes=<Object>{};
    var storage=0;
    for(final payload in retained) {
      final transport=packedSourceJsonTransport(payload);
      if(transport!=null && bytes.add(transport.$1)) storage+=transport.$1.length;
    }
    result['round$round']={'count':retained.length,'packedStorageBytes':storage,
      'selectedJsonBytes':retained.fold<int>(0,(n,v)=>n+utf8.encode(jsonEncode(v)).length),
      'heap':await heap(),'rss':ProcessInfo.currentRss};
  }
  retained.clear();disposeApiJsonResources();
  result['released']=await heap();result['releasedRss']=ProcessInfo.currentRss;
  final path=args.single;
  File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  print(path);await vm.dispose();
}
