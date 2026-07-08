enum NiedGifLayer {
  realtimeShindo('jma'),
  peakAcceleration('acmap'),
  peakVelocity('vcmap'),
  peakDisplacement('dcmap'),
  velocityResponse0125('rsp0125'),
  velocityResponse0250('rsp0250'),
  velocityResponse0500('rsp0500'),
  velocityResponse1000('rsp1000'),
  velocityResponse2000('rsp2000'),
  velocityResponse4000('rsp4000');

  const NiedGifLayer(this.id);

  final String id;

  String imageKey({required bool borehole}) => '${id}_${borehole ? 'b' : 's'}';

  Uri imageUri(
    DateTime jstTime, {
    required bool borehole,
    String baseUrl = 'http://www.kmoni.bosai.go.jp',
  }) {
    final stamp =
        '${jstTime.year.toString().padLeft(4, '0')}'
        '${jstTime.month.toString().padLeft(2, '0')}'
        '${jstTime.day.toString().padLeft(2, '0')}'
        '${jstTime.hour.toString().padLeft(2, '0')}'
        '${jstTime.minute.toString().padLeft(2, '0')}'
        '${jstTime.second.toString().padLeft(2, '0')}';
    final date = stamp.substring(0, 8);
    final key = imageKey(borehole: borehole);
    return Uri.parse(
      '$baseUrl/data/map_img/RealTimeImg/$key/$date/$stamp.$key.gif',
    );
  }
}

class NiedGifObservation {
  final NiedGifLayer layer;
  final double? colorPosition;
  final double? shindo;
  final double? pga;
  final double? pgv;
  final double? pgd;
  final double? velocityResponse;

  const NiedGifObservation({
    this.layer = NiedGifLayer.realtimeShindo,
    this.colorPosition,
    this.shindo,
    this.pga,
    this.pgv,
    this.pgd,
    this.velocityResponse,
  });

  bool get hasIndependentPga =>
      layer == NiedGifLayer.peakAcceleration && pga != null;
  bool get hasIndependentPgv =>
      layer == NiedGifLayer.peakVelocity && pgv != null;
  bool get hasIndependentPgd =>
      layer == NiedGifLayer.peakDisplacement && pgd != null;

  NiedGifObservation copyWith({
    NiedGifLayer? layer,
    double? colorPosition,
    double? shindo,
    double? pga,
    double? pgv,
    double? pgd,
    double? velocityResponse,
  }) {
    return NiedGifObservation(
      layer: layer ?? this.layer,
      colorPosition: colorPosition ?? this.colorPosition,
      shindo: shindo ?? this.shindo,
      pga: pga ?? this.pga,
      pgv: pgv ?? this.pgv,
      pgd: pgd ?? this.pgd,
      velocityResponse: velocityResponse ?? this.velocityResponse,
    );
  }
}
