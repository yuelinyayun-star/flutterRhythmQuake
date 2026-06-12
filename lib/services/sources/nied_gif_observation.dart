class NiedGifObservation {
  final double? colorPosition;
  final double? shindo;
  final double? pga;
  final double? pgv;
  final double? pgd;

  const NiedGifObservation({
    this.colorPosition,
    this.shindo,
    this.pga,
    this.pgv,
    this.pgd,
  });

  NiedGifObservation copyWith({
    double? colorPosition,
    double? shindo,
    double? pga,
    double? pgv,
    double? pgd,
  }) {
    return NiedGifObservation(
      colorPosition: colorPosition ?? this.colorPosition,
      shindo: shindo ?? this.shindo,
      pga: pga ?? this.pga,
      pgv: pgv ?? this.pgv,
      pgd: pgd ?? this.pgd,
    );
  }
}
