"""Exact-clock comparison, without estimating or applying a lag from the data."""
import json
import math
from pathlib import Path
import sys
from datetime import datetime, timedelta, timezone
import zipfile

import numpy as np
from scipy import fft

from audit_knet_filtered_intensity import digest, intensity, parse_record, response


def stats(rows, key):
    differences = [r['gif'] - r[key] for r in rows if r['gif'] is not None and r[key] is not None]
    return {'count': len(differences),
            'meanGifMinusWave': float(np.mean(differences)) if differences else None,
            'mae': float(np.mean(np.abs(differences))) if differences else None,
            'rmse': float(np.sqrt(np.mean(np.square(differences)))) if differences else None}


def peak(rows, key):
    valid = [r for r in rows if r[key] is not None]
    if not valid:
        return None
    strongest = max(valid, key=lambda r: r[key])
    return {'value': strongest[key], 'timeUtc': strongest['timeUtc']}


def main():
    if len(sys.argv) != 4:
        raise ValueError('Pass waveform diagnostic, exact-station GIF extraction, new .dart_tool JSON')
    paths = [Path(p) for p in sys.argv[1:3]]
    raw = [p.read_bytes() for p in paths]
    wave, gif = [json.loads(b) for b in raw]
    output = Path(sys.argv[3])
    if output.exists() or output.suffix != '.json' or not output.parent.resolve(strict=True).is_relative_to(Path('.dart_tool').resolve(strict=True)):
        raise ValueError('New output required in existing .dart_tool directory')
    assert len(wave['archives']) == len(gif['cases'])
    # Validate the extraction's original files, scan table and input metadata.
    for filename, expected in gif['inputSha256'].items():
        assert digest(Path(filename).read_bytes()) == expected, filename
    results = []
    for archive, event in zip(wave['archives'], gif['cases'], strict=True):
        assert archive['sha256'] == event['waveformArchiveSha256']
        archive_path = Path(archive['input'])
        assert digest(archive_path.read_bytes()) == archive['sha256']
        by_code = {s['code']: s for s in event['stations']}
        assert len(by_code) == len(event['stations'])
        stations = []
        with zipfile.ZipFile(archive_path) as source:
            for station in archive['stations']:
                original = source.read(station['file'])
                assert digest(original) == station['fileSha256']
                code, samples, hz, offsets, start = parse_record(original)
                assert code == station['station'] and start == station['sampleStartJst']
                step = round(hz)
                vector = np.linalg.norm(samples - offsets, axis=1)
                pga = [float(np.max(vector[i:i+step])) for i in range(0, len(vector), step)]
                spectrum = fft.rfft(samples, axis=0)
                filtered = fft.irfft(spectrum * response(fft.rfftfreq(len(samples), 1/hz))[:, None], n=len(samples), axis=0)
                filtered_vector = np.linalg.norm(filtered, axis=1)
                trailing = []
                for sec in station['seconds']:
                    end = (sec['second'] + 1) * step
                    check = intensity(filtered_vector[end-step:end], hz)['continuousIntensity']
                    previous = sec['filtered']['continuousIntensity']
                    assert (check is None and previous is None) or (check is not None and previous is not None and abs(check-previous) < 1e-10)
                    # Fixed published Iapx history, not a window fitted to these GIFs.
                    trailing.append(intensity(filtered_vector[end-60*step:end], hz)['continuousIntensity'] if end >= 60*step else None)
                start_time = datetime.strptime(start, '%Y/%m/%d %H:%M:%S.%f').replace(tzinfo=timezone(timedelta(hours=9)))
                original_gif = by_code[code]
                series = {layer: {} for layer in ['jma_s', 'acmap_s']}
                for s in original_gif['samples']:
                    time = datetime.fromisoformat(s['timeUtc'].replace('Z', '+00:00'))
                    assert time not in series[s['layer']]
                    series[s['layer']][time] = s
                conventions = []
                # Both boundary conventions are reported; neither is chosen by fit.
                for boundary in [0, 1]:
                    rows = []
                    for sec in station['seconds']:
                        i = sec['second']
                        at = start_time + timedelta(seconds=i+boundary)
                        at_utc = at.astimezone(timezone.utc).isoformat()
                        observation = series['jma_s'].get(at)
                        acceleration = series['acmap_s'].get(at)
                        rows.append({'timeUtc': at_utc, 'waveformSecond': i,
                                     'windowStartUtc': (start_time+timedelta(seconds=i)).astimezone(timezone.utc).isoformat(),
                                     'gifFramePresent': observation is not None,
                                     'gif': observation['value'] if observation else None,
                                     'gifRgb': observation['rgb'] if observation else None,
                                     'filtered': sec['filtered']['continuousIntensity'],
                                     'filteredTrailing60': trailing[i],
                                     'hasFull60SecondHistory': i >= 59,
                                     'unfiltered': sec['unfiltered']['continuousIntensity'],
                                     'waveformPgaGal': pga[i],
                                     'gifPgaGal': acceleration['value'] if acceleration else None})
                    paired = [r for r in rows if r['gifFramePresent']]
                    full_history = [r for r in paired if r['hasFull60SecondHistory']]
                    pga_ratios = [math.log10(r['gifPgaGal']/r['waveformPgaGal']) for r in paired
                                  if r['gifPgaGal'] is not None and r['gifPgaGal'] > 0 and r['waveformPgaGal'] > 0]
                    conventions.append({'boundary': 'window_start' if boundary == 0 else 'window_end_exclusive',
                                        'missingGifFrames': sum(not r['gifFramePresent'] for r in rows),
                                        'nullGifPixels': sum(r['gif'] is None for r in paired),
                                        'filtered': stats(paired, 'filtered'), 'unfiltered': stats(paired, 'unfiltered'),
                                        'completeHistory': {'filtered1': stats(full_history, 'filtered'), 'filtered60': stats(full_history, 'filteredTrailing60')},
                                        'gifPeakInOverlap': peak(paired, 'gif'),
                                        'waveformPeakInOverlap': peak(paired, 'filtered'),
                                        'pgaPairs': len(pga_ratios),
                                        'meanLog10GifPgaOverWavePga': float(np.mean(pga_ratios)) if pga_ratios else None,
                                        'rows': rows})
                stations.append({'code': code, 'scanPoint': original_gif['point'],
                                 'waveformFileSha256': station['fileSha256'], 'conventions': conventions})
        assert digest(archive_path.read_bytes()) == archive['sha256']
        summaries = []
        for boundary in [0, 1]:
            all_rows = [r for s in stations if s['scanPoint'] is not None
                        for r in s['conventions'][boundary]['rows'] if r['gifFramePresent']]
            # Fixed value strata show weak versus stronger readings, without fitting.
            groups = {'all': all_rows,
                      'gif_below_zero': [r for r in all_rows if r['gif'] is not None and r['gif'] < 0],
                      'gif_zero_or_above': [r for r in all_rows if r['gif'] is not None and r['gif'] >= 0]}
            summaries.append({'boundary': stations[0]['conventions'][boundary]['boundary'],
                              'groups': {name: {'filtered': stats(rows, 'filtered'), 'unfiltered': stats(rows, 'unfiltered')}
                                         for name, rows in groups.items()},
                              'completeHistory': {'filtered1': stats([r for r in all_rows if r['hasFull60SecondHistory']], 'filtered'),
                                                  'filtered60': stats([r for r in all_rows if r['hasFull60SecondHistory']], 'filteredTrailing60')}})
        results.append({'caseId': event['caseId'], 'mappedStations': sum(s['scanPoint'] is not None for s in stations),
                        'unmappedStations': [s['code'] for s in stations if s['scanPoint'] is None],
                        'summaries': summaries, 'stations': stations})
    for p, b in zip(paths, raw, strict=True):
        assert digest(p.read_bytes()) == digest(b)
    report = {'feedsProduction': False, 'readyForCalibration': False, 'estimatedLagSeconds': None,
              'inputSha256': {str(p): digest(b) for p, b in zip(paths, raw, strict=True)},
              'limits': ['No event-label inference, lag fitting, interpolation, missing-pixel substitution, or input mutation.',
                         'Start versus end are explicit one-second timestamp conventions, not measured network latency.',
                         'Offline zero-phase FFT differs from causal realtime filtering; one-second duration diagnostics are not certified realtime GIF equivalents.',
                         'Trailing 60-second threshold uses the same offline FFT only, not a streaming filter. The first 59 seconds are unavailable, not shortened or padded.',
                         'Magnitude is not estimated here. Error statistics describe different measurement definitions, not magnitude accuracy.',
                         'Unmapped and absent/null GIF samples remain unavailable. Waveform edge effects and CSV precision remain.'],
              'cases': results}
    with output.open('x', encoding='utf-8') as stream:
        json.dump(report, stream, ensure_ascii=False, allow_nan=False, indent=2)
        stream.write('\n')
    print(json.dumps([{'caseId': c['caseId'], 'mapped': c['mappedStations'], 'summary': c['summaries'],
                       'examples': [{'code': s['code'], 'conventions': [{k:v for k,v in p.items() if k != 'rows'} for p in s['conventions']]}
                                    for s in c['stations'] if s['code'] in ['YMN002', 'FKS027', 'FKS028', 'GNM001']]}
                      for c in results], ensure_ascii=False))


if __name__ == '__main__':
    main()
