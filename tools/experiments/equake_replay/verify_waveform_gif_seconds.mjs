import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync, realpathSync, existsSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
assert.equal(args.length, 5, 'Pass waveform, extraction, first comparison, 60s comparison, new output');
const bytes = args.slice(0, 4).map(p => readFileSync(p));
const [wave, gif, original, report] = bytes.map(b => JSON.parse(b));
const sha = b => createHash('sha256').update(b).digest('hex');
const close = (a, b) => {
  if (a === null || b === null) assert.equal(a, b);
  else assert.ok(Number.isFinite(a) && Number.isFinite(b) && Math.abs(a-b) < 1e-10, `${a} != ${b}`);
};
const stats = (rows, key) => {
  const d = rows.filter(r => r.gif !== null && r[key] !== null).map(r => r.gif-r[key]);
  const mean = values => values.length ? values.reduce((a,b) => a+b, 0)/values.length : null;
  return { count:d.length, meanGifMinusWave:mean(d), mae:mean(d.map(Math.abs)),
    rmse:d.length ? Math.sqrt(mean(d.map(x=>x*x))) : null };
};
const checkStats = (rows, key, actual) => {
  for (const [k,v] of Object.entries(stats(rows, key))) close(v, actual[k]);
};
for (const [p,h] of Object.entries(gif.inputSha256)) assert.equal(sha(readFileSync(p)), h);
for (const [p,h] of Object.entries(report.inputSha256)) assert.equal(sha(readFileSync(p)), h);
assert.equal(report.feedsProduction, false);
assert.equal(report.readyForCalibration, false);
assert.equal(report.estimatedLagSeconds, null);
let rowsChecked = 0, completeRows = 0, missingHistory = 0;
for (const [ci,c] of report.cases.entries()) {
  const archive = wave.archives[ci];
  assert.equal(archive.sha256, gif.cases[ci].waveformArchiveSha256);
  assert.equal(c.caseId, gif.cases[ci].caseId);
  assert.equal(c.caseId, original.cases[ci].caseId);
  assert.equal(c.stations.length, archive.stations.length);
  for (const s of c.stations) {
    const w = archive.stations.find(r=>r.station===s.code);
    const g = gif.cases[ci].stations.find(r=>r.code===s.code);
    const old = original.cases[ci].stations.find(r=>r.code===s.code);
    const start = Date.parse(w.sampleStartJst.replaceAll('/', '-').replace(' ', 'T')+'+09:00');
    const observations = new Map(g.samples.filter(r=>r.layer==='jma_s').map(r=>[Date.parse(r.timeUtc),r]));
    assert.deepEqual(s.scanPoint,g.point);
    for (const [boundary,convention] of s.conventions.entries()) {
      assert.equal(convention.rows.length,w.seconds.length);
      for (const [i,r] of convention.rows.entries()) {
        assert.equal(r.waveformSecond,i);
        assert.equal(Date.parse(r.windowStartUtc),start+i*1000);
        assert.equal(Date.parse(r.timeUtc),start+(i+boundary)*1000);
        const observation = observations.get(Date.parse(r.timeUtc));
        assert.equal(r.gifFramePresent,observation!==undefined);
        assert.equal(r.gif,observation?.value??null);
        assert.deepEqual(r.gifRgb,observation?.rgb??null);
        assert.equal(r.hasFull60SecondHistory,i>=59);
        close(r.filtered,w.seconds[i].filtered.continuousIntensity);
        close(r.unfiltered,w.seconds[i].unfiltered.continuousIntensity);
        for (const [k,v] of Object.entries(old.conventions[boundary].rows[i])) {
          assert.deepEqual(r[k],v,'Original one-second comparison must be unchanged');
        }
        if (i<59) {assert.equal(r.filteredTrailing60,null); missingHistory++;}
        else {
          if(r.filtered!==null) assert.ok(r.filteredTrailing60>=r.filtered-1e-10);
          if(r.filteredTrailing60!==null) assert.ok(r.filteredTrailing60<=w.filteredRecord.continuousIntensity+1e-10);
          if(w.seconds.length===60) close(r.filteredTrailing60,w.filteredRecord.continuousIntensity);
          completeRows++;
        }
        rowsChecked++;
      }
      const valid = convention.rows.filter(r=>r.gifFramePresent);
      checkStats(valid,'filtered',convention.filtered);
      checkStats(valid,'unfiltered',convention.unfiltered);
      const full = valid.filter(r=>r.hasFull60SecondHistory);
      checkStats(full,'filtered',convention.completeHistory.filtered1);
      checkStats(full,'filteredTrailing60',convention.completeHistory.filtered60);
    }
  }
  for(const [b,summary] of c.summaries.entries()) {
    const rows=c.stations.filter(s=>s.scanPoint!==null).flatMap(s=>s.conventions[b].rows).filter(r=>r.gifFramePresent&&r.hasFull60SecondHistory);
    checkStats(rows,'filtered',summary.completeHistory.filtered1);
    checkStats(rows,'filteredTrailing60',summary.completeHistory.filtered60);
  }
}
for (const [i,b] of bytes.entries()) assert.equal(sha(readFileSync(args[i])),sha(b));
const output=args[4], root=realpathSync('.dart_tool'), parent=realpathSync(path.dirname(output));
const relative=path.relative(root,parent);
assert.ok(!path.isAbsolute(relative)&&relative!=='..'&&!relative.startsWith(`..${path.sep}`));
assert.equal(path.extname(output),'.json');
assert.equal(existsSync(output),false);
const result={rowsChecked,completeRows,missingHistory,
  scope:'Independent clock, exact station/RGB pairing, missing-data rules, unchanged baseline, duration-threshold bounds and statistics; not an independent FFT/GIF decoder or realtime filter oracle.',
  inputSha256:args.slice(0,4).map((file,i)=>({file,sha256:sha(bytes[i])}))};
writeFileSync(output,JSON.stringify(result,null,2)+'\n',{encoding:'utf8',flag:'wx'});
console.log(JSON.stringify(result));
