import 'quake_message.dart';

/// Mechanism solutions have their own rows, independent of origin catalogues.
const cmtCatalogSources = <String, QuakeSourceType>{
  'fssnCmt': QuakeSourceType.fssnCmt,
  'cencCmt': QuakeSourceType.cencCmt,
  'usgsCmt': QuakeSourceType.usgsCmt,
  'jmaCmt': QuakeSourceType.jmaCmt,
  'fnetCmt': QuakeSourceType.fnetCmt,
  'hinetAquaCmt': QuakeSourceType.hinetAquaCmt,
};

String cmtCatalogLabel(QuakeSourceType source) => switch (source) {
  QuakeSourceType.fssnCmt => 'FSSN-CMT',
  QuakeSourceType.cencCmt => 'CENC-CMT',
  QuakeSourceType.usgsCmt => 'USGS-CMT',
  QuakeSourceType.jmaCmt => 'JMA-CMT',
  QuakeSourceType.fnetCmt => 'F-net-CMT',
  QuakeSourceType.hinetAquaCmt => 'Hi-net-CMT',
  _ => source.displayName,
};
