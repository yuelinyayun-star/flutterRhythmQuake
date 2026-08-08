/// 基于节面走向、倾角、滑动角的断层类型归类。
///
/// 这是对单个节面的几何归类，不用于判定哪一个节面是真实断层面；
/// 因此 UI 必须将结果标记为“仅供参考”。
enum CmtFaultType {
  strikeSlip,
  normal,
  reverse,
  thrust,
  obliqueNormal,
  obliqueReverse,
  unavailable,
}

class CmtFaultTypeClassifier {
  const CmtFaultTypeClassifier._();

  /// Uses the conventional 22.5-degree rake boundaries for broad mechanism
  /// classes. A low-angle reverse mechanism is labelled thrust.
  static CmtFaultType fromNodalPlane(String? nodalPlane) {
    if (nodalPlane == null) return CmtFaultType.unavailable;
    final parts = nodalPlane.split('/');
    if (parts.length != 3) return CmtFaultType.unavailable;

    final dip = double.tryParse(parts[1].trim());
    final rake = double.tryParse(parts[2].trim());
    if (dip == null || rake == null || !dip.isFinite || !rake.isFinite) {
      return CmtFaultType.unavailable;
    }

    final normalizedRake = ((rake + 180) % 360 + 360) % 360 - 180;
    final absoluteRake = normalizedRake.abs();
    if (absoluteRake <= 22.5 || absoluteRake >= 157.5) {
      return CmtFaultType.strikeSlip;
    }
    if (normalizedRake >= 67.5 && normalizedRake <= 112.5) {
      return dip <= 45 ? CmtFaultType.thrust : CmtFaultType.reverse;
    }
    if (normalizedRake >= -112.5 && normalizedRake <= -67.5) {
      return CmtFaultType.normal;
    }
    return normalizedRake > 0
        ? CmtFaultType.obliqueReverse
        : CmtFaultType.obliqueNormal;
  }

  static String label(CmtFaultType type) {
    return switch (type) {
      CmtFaultType.strikeSlip => '走滑断层型',
      CmtFaultType.normal => '正断层型',
      CmtFaultType.reverse => '逆断层型',
      CmtFaultType.thrust => '逆冲断层型',
      CmtFaultType.obliqueNormal => '斜滑断层型（正断层分量）',
      CmtFaultType.obliqueReverse => '斜滑断层型（逆断层分量）',
      CmtFaultType.unavailable => '无法根据现有节面判定',
    };
  }
}
