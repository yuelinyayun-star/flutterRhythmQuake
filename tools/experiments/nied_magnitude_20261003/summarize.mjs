import fs from 'node:fs';

const path = process.argv[2];
if (!path) throw new Error('Pass the read-only production audit report path');
const report = JSON.parse(fs.readFileSync(path, 'utf8'));
const round = (x) => Number.isFinite(x) ? Number(x.toFixed(4)) : null;
const maxBy = (rows, value) => rows.filter((r) => Number.isFinite(value(r)))
  .reduce((a, b) => a == null || value(b) > value(a) ? b : a, null);
const describe = (frame) => {
  if (!frame) return null;
  const a = frame.magnitudeAudit;
  const d = a.publishedDiagnostics;
  return {
    timeJst: frame.observedAtJst,
    latitude: frame.estimate.latitude,
    longitude: frame.estimate.longitude,
    depthKm: frame.estimate.depthKm,
    reportNumber: frame.estimate.diagnostics.nied_dart_hyp_report_num,
    locked: d.srev_kaizou_magnitude_locked,
    published: round(a.publishedMagnitude),
    freshHeld: round(a.freshHeldMagnitude),
    freshTimedHeld: round(a.freshTimedHeldMagnitude),
    publishedIntensity: d.srev_kaizou_magnitude_input_intensity,
    currentHeldIntensity: a.allActiveHeldConvertedIntensity,
    currentTimedHeldIntensity: a.timedActiveHeldConvertedIntensity,
    rawMaximumIntensity: a.allActiveRawMaximumIntensity,
    rawConvertedIntensity: a.rawMaximumConvertedIntensity,
    nearestDistanceKm: round(a.freshHeldDiagnostics?.srev_kaizou_magnitude_nearest_station_distance_km),
    usedDistanceKm: round(a.freshHeldDiagnostics?.srev_kaizou_magnitude_clamped_station_distance_km),
    strongestCode: a.strongestStationCode,
    strongestHasTrigger: a.strongestStationHasTrigger,
    strongestDistanceKm: round(a.strongestStationDistanceKm),
    instantaneousRawMagnitude: round(a.instantaneousRawMagnitude),
    instantaneousStrongestDistanceMagnitude: round(a.instantaneousStrongestDistanceMagnitude),
  };
};
const result = report.cases.map((c) => {
  const frames = c.frames.filter((f) => f.estimate && f.magnitudeAudit?.singleSourceComparable
    && Date.parse(f.magnitudeAudit.observedAtUtc) === Date.parse(f.observedAtJst + '+09:00'));
  const gap = (f) => f.magnitudeAudit.freshHeldMagnitude - f.magnitudeAudit.publishedMagnitude;
  return {
    id: c.id,
    reference: c.referenceLabel,
    eventLabels: c.eventLabels,
    totalFrames: c.processedFrameCount,
    estimateFrames: c.estimateFrameCount,
    comparableFrames: frames.length,
    rawInputSha256: c.rawInputSha256,
    first: describe(frames[0]),
    last: describe(frames.at(-1)),
    maximumPublished: describe(maxBy(frames, (f) => f.magnitudeAudit.publishedMagnitude)),
    maximumFreshHeld: describe(maxBy(frames, (f) => f.magnitudeAudit.freshHeldMagnitude)),
    largestSuppressedRise: describe(maxBy(frames, gap)),
    largestPublicationGap: describe(maxBy(frames, (f) =>
      f.magnitudeAudit.freshTimedHeldMagnitude - f.magnitudeAudit.publishedMagnitude)),
    largestTimingFilterGap: describe(maxBy(frames, (f) =>
      f.magnitudeAudit.freshHeldMagnitude - f.magnitudeAudit.freshTimedHeldMagnitude)),
    framesWithSuppressedRiseOverHalfMagnitude: frames.filter((f) => gap(f) > 0.5).length,
    firstLocked: describe(frames.find((f) => f.magnitudeAudit.publishedDiagnostics.srev_kaizou_magnitude_locked)),
    largestQuantizationLoss: round(frames.reduce((v, f) => Math.max(v,
      f.magnitudeAudit.allActiveRawMaximumIntensity - f.magnitudeAudit.rawMaximumConvertedIntensity), 0)),
  };
});
const json = JSON.stringify(result, null, 2) + '\n';
if (process.argv[3]) {
  if (fs.realpathSync(path) === process.argv[3]) {
    throw new Error('Summary output must not replace input');
  }
  if (fs.existsSync(process.argv[3])) {
    throw new Error('Summary output already exists; choose a new path');
  }
  fs.writeFileSync(process.argv[3], json, {encoding: 'utf8', flag: 'wx'});
} else {
  process.stdout.write(json);
}
