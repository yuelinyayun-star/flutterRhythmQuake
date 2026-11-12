import 'quake_message.dart';

/// The information card's established agency/type/status labels. Manual map
/// display reuses these UI labels instead of inventing a catalogue-only title.
String catalogInformationTitle(QuakeMessage event) {
  switch (event.source) {
    case QuakeSourceType.cenc:
      return '中国地震台网地震信息';
    case QuakeSourceType.cencIr:
      return '中国地震台网烈度速报';
    case QuakeSourceType.usgs:
      final rt = event.reviewType;
      if (rt == 'reviewed' || rt == '正式测定') return 'USGS正式测定';
      if (rt != null) return 'USGS自动测定';
      return 'USGS測定';
    case QuakeSourceType.fssn:
      final rt = event.reviewType;
      if (rt == '正式(已核实)') return 'FSSN正式测定';
      if (rt == '已确认') return 'FSSN自动测定';
      return 'FSSN地震报告';
    case QuakeSourceType.fssnCmt:
      return 'FSSN 地震矩心矩张量解';
    case QuakeSourceType.cencCmt:
      return 'CENC 地震矩心矩张量解';
    case QuakeSourceType.usgsCmt:
      return 'USGS 地震矩心矩张量解';
    case QuakeSourceType.jmaCmt:
      return 'JMA 地震矩心矩张量解';
    case QuakeSourceType.fnetCmt:
      return 'F-net 地震矩心矩张量解';
    case QuakeSourceType.hinetAquaCmt:
      return 'Hi-net AQUA 地震矩心矩张量解';
    case QuakeSourceType.hko:
      final verify = event.verify;
      if (verify == 'Y') return '香港天文台已核实';
      if (verify == 'N') return '香港天文台初步报告';
      return '香港天文台地震报告';
    case QuakeSourceType.emsc:
      return '欧洲地中海地震中心';
    case QuakeSourceType.bcsf:
      return '法国中央地震研究所';
    case QuakeSourceType.gfz:
      return '德国地学研究中心';
    case QuakeSourceType.usp:
      return '巴西圣保罗大学';
    case QuakeSourceType.kma_eq:
      return '기상청 지진 정보';
    case QuakeSourceType.ningxia:
      return '宁夏地震局';
    case QuakeSourceType.guangxi:
      return '广西地震局';
    case QuakeSourceType.shanxi:
      return '山西地震局';
    case QuakeSourceType.beijing:
      return '北京地震局';
    case QuakeSourceType.yunnan:
      return '云南地震局';
    case QuakeSourceType.bmkg:
      return '印度尼西亚气象气候与地球物理局';
    case QuakeSourceType.geonet:
      return '新西兰地球科学局';
    case QuakeSourceType.tmd:
      return '泰国气象局';
    case QuakeSourceType.ingv:
      return '意大利国家地球物理与火山学研究所';
    case QuakeSourceType.nrcan:
      return '加拿大自然资源部';
    case QuakeSourceType.mmd:
      return '马来西亚气象局';
    case QuakeSourceType.phivolcs:
      return '菲律宾火山与地震研究所';
    case QuakeSourceType.sgc:
      return '哥伦比亚地质局';
    case QuakeSourceType.ga:
      return '澳大利亚地质局';
    case QuakeSourceType.cenais:
      return '古巴国家地震研究中心';
    case QuakeSourceType.unadapted:
      final title = event.infoTypeName?.trim();
      return (title != null && title.isNotEmpty) ? title : '地震信息';
    case QuakeSourceType.cwa:
    case QuakeSourceType.cwa_eew:
      return '中央氣象署地震報告';
    case QuakeSourceType.wolfx:
    case QuakeSourceType.p2p:
    case QuakeSourceType.jma_fan:
      return event.infoTypeName ?? '地震情报';
    default:
      final title = event.infoTypeName?.trim();
      return (title != null && title.isNotEmpty) ? title : '地震信息';
  }
}
