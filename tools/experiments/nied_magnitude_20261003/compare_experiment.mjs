import fs from 'node:fs';

const path = process.argv[2];
if (!path) throw new Error('Pass an experimental replay report path');
const report = JSON.parse(fs.readFileSync(path, 'utf8'));
const round = (x) => Number.isFinite(x) ? Number(x.toFixed(4)) : null;
const fields = ['associatedQuantizedLockedMagnitude', 'associatedContinuousLockedMagnitude',
  'associatedContinuousRefreshedMagnitude', 'associatedContinuousPeakMagnitude'];
const result = report.cases.map((c) => {
  const episodes = new Map();
  for (const frame of c.frames) {
    const e = frame.magnitudeAudit?.experiment;
    if (!e?.supported) continue;
    const rows = episodes.get(e.eventKey) ?? [];
    rows.push(frame);
    episodes.set(e.eventKey, rows);
  }
  return {
    id: c.id, reference: c.referenceLabel, eventLabels: c.eventLabels,
    frames: c.processedFrameCount, missing: c.missingFrameCount,
    estimateFrames: c.estimateFrameCount,
    episodes: [...episodes].map(([eventKey, rows]) => {
      const last = rows.at(-1);
      const experiment = last.magnitudeAudit.experiment;
      const variants = Object.fromEntries(fields.map((field) => [field, {
        final: round(experiment[field]),
        peak: round(Math.max(...rows.map((r) => r.magnitudeAudit.experiment[field])
          .filter(Number.isFinite))),
      }]));
      const recovered = rows.reduce((best, frame) => {
        const e = frame.magnitudeAudit.experiment;
        return e.associatedUntimedCount > (best?.magnitudeAudit.experiment.associatedUntimedCount ?? -1)
          ? frame : best;
      }, null);
      return {
        eventKey, firstJst: rows[0].observedAtJst, lastJst: last.observedAtJst,
        count: rows.length, finalLocation: [last.estimate.latitude, last.estimate.longitude],
        finalDepthKm: last.estimate.depthKm,
        publishedFinal: round(last.estimate.magnitude),
        publishedPeak: round(Math.max(...rows.map((r) => r.estimate.magnitude).filter(Number.isFinite))),
        variants,
        maxUntimedStations: recovered.magnitudeAudit.experiment.associatedUntimedCount,
        maxAmbiguousRejected: Math.max(...rows.map((r) => r.magnitudeAudit.experiment.rejectedCounts.ambiguous_owner_path ?? 0)),
        maxOtherEventRejected: Math.max(...rows.map((r) => r.magnitudeAudit.experiment.rejectedCounts.other_event ?? 0)),
        sampleRecovered: {
          timeJst: recovered.observedAtJst,
          strongest: recovered.magnitudeAudit.experiment.strongestCode,
          published: round(recovered.estimate.magnitude),
          refreshed: round(recovered.magnitudeAudit.experiment.associatedContinuousRefreshedMagnitude),
        },
      };
    }),
  };
});
const json = JSON.stringify(result, null, 2) + '\n';
if (process.argv[3]) {
  fs.writeFileSync(process.argv[3], json, {encoding: 'utf8', flag: 'wx'});
} else process.stdout.write(json);
