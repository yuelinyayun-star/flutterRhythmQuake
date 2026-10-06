import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';

const separator = Buffer.from('!&@^#*');
const sha = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

export function stampTime(stamp) {
  if (!/^\d{14}$/.test(stamp)) throw new Error('Invalid frame timestamp');
  const iso = `${stamp.slice(0,4)}-${stamp.slice(4,6)}-${stamp.slice(6,8)}T` +
    `${stamp.slice(8,10)}:${stamp.slice(10,12)}:${stamp.slice(12,14)}`;
  const ms = Date.parse(iso + '+09:00');
  if (!Number.isFinite(ms) || new Date(ms + 9*3600000).toISOString().slice(0,19) !== iso) {
    throw new Error('Invalid calendar timestamp');
  }
  return {wallClock: iso, utc: new Date(ms).toISOString(), ms};
}

// Walk actual GIF blocks; separator-like bytes inside compressed pixels do not
// delimit a record. The returned slice is the original byte sequence.
export function gifEnd(bytes, start) {
  let p = start;
  const need = (n) => {if (p+n > bytes.length) throw new Error(`Truncated GIF at ${p}`);};
  need(13);
  if (!['GIF87a','GIF89a'].includes(bytes.toString('ascii',p,p+6))) {
    throw new Error(`Missing GIF signature at ${p}`);
  }
  const packed = bytes[p+10];
  p += 13;
  if (packed & 128) {const n = 3*(2**((packed & 7)+1)); need(n); p+=n;}
  function subblocks() {
    for (;;) {need(1); const n=bytes[p++]; if(n===0)return; need(n); p+=n;}
  }
  for (;;) {
    need(1); const marker=bytes[p++];
    if(marker===0x3b) return p;
    if(marker===0x21) {need(1); p++; subblocks(); continue;}
    if(marker===0x2c) {
      need(9); const local=bytes[p+8]; p+=9;
      if(local & 128) {const n=3*(2**((local & 7)+1)); need(n); p+=n;}
      need(1); p++; subblocks(); continue;
    }
    throw new Error(`Unexpected GIF marker ${marker} at ${p-1}`);
  }
}

export function parseGifDat(bytes) {
  const frames=[]; let p=0;
  while(p < bytes.length) {
    const recordOffset=p;
    if(p+14 > bytes.length) throw new Error('Truncated timestamp');
    const stamp=bytes.toString('ascii',p,p+14); const time=stampTime(stamp); p+=14;
    if(frames.length && time.ms <= frames.at(-1).time.ms) throw new Error('Duplicate or reversed frame');
    const end=gifEnd(bytes,p); const gif=bytes.subarray(p,end);
    if(!bytes.subarray(end,end+separator.length).equals(separator)) throw new Error(`Missing separator at ${end}`);
    frames.push({stamp,time,recordOffset,gifOffset:p,length:gif.length,sha256:sha(gif),gif});
    p=end+separator.length;
  }
  return frames;
}

export function extract(input, output, officialCapture) {
  const destination=path.resolve(output);
  if(fs.existsSync(destination)) throw new Error('Choose a new extraction directory');
  const ini=fs.readFileSync(path.join(input,'info.ini'),'utf8');
  const info=Object.fromEntries(ini.split(/\r?\n/).filter((l)=>l.includes('='))
    .map((l)=>[l.slice(0,l.indexOf('=')),l.slice(l.indexOf('=')+1)]));
  if(info.formatVersion!=='3') throw new Error('Only observed formatVersion=3 is supported');
  const layers={};
  for(const layer of ['jma_s','acmap_s']) {
    const bytes=fs.readFileSync(path.join(input,layer+'.dat'));
    layers[layer]={sourceSha256:sha(bytes),frames:parseGifDat(bytes)};
  }
  fs.mkdirSync(destination,{recursive:true});
  const records=[]; let compared=0; let equal=0;
  for(const [layer, data] of Object.entries(layers)) {
    for(const f of data.frames) {
      const filename=`${f.stamp}.${layer}.gif`;
      fs.writeFileSync(path.join(destination,filename),f.gif,{flag:'wx'});
      let matchesOfficial=null;
      if(officialCapture && fs.existsSync(path.join(officialCapture,filename))) {
        compared++; matchesOfficial=sha(fs.readFileSync(path.join(officialCapture,filename)))===f.sha256;
        if(matchesOfficial)equal++;
      }
      const {gif,time,...metadata}=f;
      records.push({...metadata,layer,filename,observedAtJst:time.wallClock,
        observedAtUtc:time.utc,matchesOfficial});
    }
  }
  const first=layers.jma_s.frames[0]; const last=layers.jma_s.frames.at(-1);
  if(!first)throw new Error('No intensity frames');
  const result={formatVersion:3,sourceDirectory:path.resolve(input),info,
    timestampInterpretation:'JST; cross-check against original NIED GIF hashes',
    startTimeJst:first.time.wallClock,endTimeJst:last.time.wallClock,
    captureDirectory:destination,rawGifBytesPreserved:true,
    sourceHashes:Object.fromEntries(Object.entries(layers).map(([k,v])=>[k,v.sourceSha256])),
    layerCounts:Object.fromEntries(Object.entries(layers).map(([k,v])=>[k,v.frames.length])),
    missingIntensityFrames:(last.time.ms-first.time.ms)/1000+1-layers.jma_s.frames.length,
    officialComparison:{compared,equal},records};
  fs.writeFileSync(path.join(destination,'extraction-manifest.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
  return result;
}

if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  const [input,output,official]=process.argv.slice(2);
  if(!input||!output)throw new Error('Usage: node extract.mjs input-directory new-output-directory [official-capture]');
  const {records,...summary}=extract(input,output,official);
  console.log(JSON.stringify(summary,null,2));
}
