/// CMT moment tensor in the North-East-Down (NED) coordinate system.
///
/// Map rendering consumes this canonical form directly. Source services retain
/// their received components and the adapter performs only the documented
/// coordinate-basis conversion needed for the focal-sphere calculation.
class CmtMomentTensor {
  final double mnn;
  final double mee;
  final double mdd;
  final double mne;
  final double mnd;
  final double med;

  const CmtMomentTensor({
    required this.mnn,
    required this.mee,
    required this.mdd,
    required this.mne,
    required this.mnd,
    required this.med,
  });

  static CmtMomentTensor? fromNedMap(Map<dynamic, dynamic>? values) {
    if (values == null) return null;
    final mnn = _parse(values['mnn']);
    final mee = _parse(values['mee']);
    final mdd = _parse(values['mdd']);
    final mne = _parse(values['mne']);
    final mnd = _parse(values['mnd']);
    final med = _parse(values['med']);
    if ([mnn, mee, mdd, mne, mnd, med].any((value) => value == null)) {
      return null;
    }
    return CmtMomentTensor(
      mnn: mnn!,
      mee: mee!,
      mdd: mdd!,
      mne: mne!,
      mnd: mnd!,
      med: med!,
    );
  }

  /// Converts the standard r-theta-phi basis used by USGS and JMA CMT pages.
  ///
  /// r is Up, theta is South and phi is East. The map painter uses NED, so the
  /// off-diagonal signs are transformed while preserving the source tensor.
  static CmtMomentTensor? fromRtpMap(Map<dynamic, dynamic>? values) {
    if (values == null) return null;
    final mrr = _parse(values['mrr']);
    final mtt = _parse(values['mtt']);
    final mpp = _parse(values['mpp'] ?? values['mff']);
    final mrt = _parse(values['mrt']);
    final mrp = _parse(values['mrp'] ?? values['mrf']);
    final mtp = _parse(values['mtp'] ?? values['mtf']);
    if ([mrr, mtt, mpp, mrt, mrp, mtp].any((value) => value == null)) {
      return null;
    }
    return CmtMomentTensor(
      mnn: mtt!,
      mee: mpp!,
      mdd: mrr!,
      mne: -mtp!,
      mnd: mrt!,
      med: -mrp!,
    );
  }

  Map<String, double> toMap() => {
    'mnn': mnn,
    'mee': mee,
    'mdd': mdd,
    'mne': mne,
    'mnd': mnd,
    'med': med,
  };

  static double? _parse(dynamic value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().trim() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}
