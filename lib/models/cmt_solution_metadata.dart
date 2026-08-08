/// 可选的 CMT 解元数据。
///
/// 这些字段保留上游 CMT 产品给出的原始解信息，不参与震源、震级或震源球计算。
class CmtSolutionMetadata {
  /// 上游文本中的质心时刻，保持原始时区/精度文本，不在这里二次换算。
  final String? centroidTime;
  final double? centroidLatitude;
  final double? centroidLongitude;

  /// 上游给出的标量矩文本及单位/指数，避免把不同来源的表示方式强行合并。
  final String? scalarMoment;
  final int? scalarMomentExponent;
  final String? scalarMomentUnit;

  /// 上游质量字段。比例保持来源本身的量纲（例如 0.04 或 0.9417）。
  final double? varianceReduction;
  final int? stationCount;
  final double? nonDoubleCoupleRatio;
  final double? doubleCoupleRatio;

  /// 原始张量分量及其坐标约定。
  ///
  /// 地图会将部分来源的 RTP 分量转换为 NED 后绘制；这里保留上游值，
  /// 供原始 CMT 数据展示使用，不能以计算后的绘图分量替代。
  final Map<String, String>? rawMomentTensor;
  final String? momentTensorConvention;

  const CmtSolutionMetadata({
    this.centroidTime,
    this.centroidLatitude,
    this.centroidLongitude,
    this.scalarMoment,
    this.scalarMomentExponent,
    this.scalarMomentUnit,
    this.varianceReduction,
    this.stationCount,
    this.nonDoubleCoupleRatio,
    this.doubleCoupleRatio,
    this.rawMomentTensor,
    this.momentTensorConvention,
  });

  static CmtSolutionMetadata? fromMap(Map<dynamic, dynamic>? values) {
    if (values == null) return null;

    double? asDouble(dynamic value) => switch (value) {
      num() => value.toDouble(),
      _ => double.tryParse(value?.toString() ?? ''),
    };
    int? asInt(dynamic value) => switch (value) {
      int() => value,
      num() => value.toInt(),
      _ => int.tryParse(value?.toString() ?? ''),
    };
    Map<String, String>? asRawTensor(dynamic value) {
      if (value is! Map) return null;
      final result = <String, String>{};
      for (final entry in value.entries) {
        final key = entry.key.toString().trim();
        final text = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && text.isNotEmpty) result[key] = text;
      }
      return result.isEmpty ? null : Map.unmodifiable(result);
    }

    final result = CmtSolutionMetadata(
      centroidTime: values['centroidTime']?.toString(),
      centroidLatitude: asDouble(values['centroidLatitude']),
      centroidLongitude: asDouble(values['centroidLongitude']),
      scalarMoment: values['scalarMoment']?.toString(),
      scalarMomentExponent: asInt(values['scalarMomentExponent']),
      scalarMomentUnit: values['scalarMomentUnit']?.toString(),
      varianceReduction: asDouble(values['varianceReduction']),
      stationCount: asInt(values['stationCount']),
      nonDoubleCoupleRatio: asDouble(values['nonDoubleCoupleRatio']),
      doubleCoupleRatio: asDouble(values['doubleCoupleRatio']),
      rawMomentTensor: asRawTensor(values['rawMomentTensor']),
      momentTensorConvention: values['momentTensorConvention']?.toString(),
    );
    return result.isEmpty ? null : result;
  }

  bool get isEmpty =>
      centroidTime == null &&
      centroidLatitude == null &&
      centroidLongitude == null &&
      scalarMoment == null &&
      scalarMomentExponent == null &&
      scalarMomentUnit == null &&
      varianceReduction == null &&
      stationCount == null &&
      nonDoubleCoupleRatio == null &&
      doubleCoupleRatio == null &&
      rawMomentTensor == null &&
      momentTensorConvention == null;

  Map<String, dynamic> toMap() => {
    'centroidTime': centroidTime,
    'centroidLatitude': centroidLatitude,
    'centroidLongitude': centroidLongitude,
    'scalarMoment': scalarMoment,
    'scalarMomentExponent': scalarMomentExponent,
    'scalarMomentUnit': scalarMomentUnit,
    'varianceReduction': varianceReduction,
    'stationCount': stationCount,
    'nonDoubleCoupleRatio': nonDoubleCoupleRatio,
    'doubleCoupleRatio': doubleCoupleRatio,
    'rawMomentTensor': rawMomentTensor,
    'momentTensorConvention': momentTensorConvention,
  };
}
