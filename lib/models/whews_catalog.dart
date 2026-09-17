import 'quake_message.dart';

/// Catalog feeds whose WHEWS contract uses UTC+8 shockTime/updateTime.
/// Share identity across foreground, Android background, filters and speech.
const whewsCatalogSources = <String, QuakeSourceType>{
  'whews_bmkg': QuakeSourceType.bmkg,
  'whews_geonet': QuakeSourceType.geonet,
  'whews_tmd': QuakeSourceType.tmd,
  'whews_ingv': QuakeSourceType.ingv,
  'whews_nrcan': QuakeSourceType.nrcan,
  'whews_mmd': QuakeSourceType.mmd,
  'whews_phivolcs': QuakeSourceType.phivolcs,
  'whews_sgc': QuakeSourceType.sgc,
  'whews_ga': QuakeSourceType.ga,
  'whews_cenais': QuakeSourceType.cenais,
  'whews_gsras': QuakeSourceType.gsras,
  'whews_bgs': QuakeSourceType.bgs,
  'whews_ipma': QuakeSourceType.ipma,
  'whews_ssn': QuakeSourceType.ssn,
  'whews_afad': QuakeSourceType.afad,
  'whews_sed': QuakeSourceType.sed,
  'whews_noa': QuakeSourceType.noa,
  'whews_scsn': QuakeSourceType.scsn,
  'whews_iag': QuakeSourceType.iag,
  'whews_igp': QuakeSourceType.igp,
  'whews_nepal': QuakeSourceType.nepal,
};

/// Shared agency slots. Legacy WHEWS keys remain stable for saved filters/lists;
/// transport provenance is carried separately by origin/apiTypeLabel.
const unifiedCatalogSources = <String, QuakeSourceType>{
  ...whewsCatalogSources,
  'ipgp': QuakeSourceType.ipgp,
  'infp': QuakeSourceType.infp,
  'isc': QuakeSourceType.isc,
  'knmi': QuakeSourceType.knmi,
  'ncedc': QuakeSourceType.ncedc,
  'lmu': QuakeSourceType.lmu,
  'koeri': QuakeSourceType.koeri,
  'csn': QuakeSourceType.csn,
  'igepn': QuakeSourceType.igepn,
  'earlyEst': QuakeSourceType.earlyEst,
};

String whewsCatalogLabel(QuakeSourceType source) => switch (source) {
  QuakeSourceType.earlyEst => 'Early-est',
  QuakeSourceType.geonet => 'GeoNet',
  QuakeSourceType.nrcan => 'NRCan',
  _ => source.name.toUpperCase(),
};
