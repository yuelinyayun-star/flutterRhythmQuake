"""Compare explicit causal-filter starts against unchanged exact-clock GIF pairs."""
import json
import math
from pathlib import Path
import sys
import zipfile

import numpy as np

from audit_knet_filtered_intensity import digest, parse_record
from compare_waveform_gif_seconds import stats
from kunugi_2013_reference import filter_samples, sos_coefficients, trailing_intensity_report, PARAMETERS


def verify_transfer_functions(hz):
    """Independently substitute the paper's s^-1/s^-2 transforms in A1-A8."""
    f = np.geomspace(.001, hz*.499, 10000)
    q = np.exp(-2j*np.pi*f/hz)
    l = (1+q)/(1-q)/(2*hz)
    r = (1+10*q+q*q)/(1-q)**2/(12*hz*hz)
    w0, w1, w2 = 2*np.pi*np.array([.45,7,.5])
    expected = [1/(1+w0*l)*(1+w1*l)/(2+w1*l),
                (1+4*w1*l)/(8+w1*l)*(1+.25*w1*l)/(.5+w1*l),
                (1+2*1.0*w2*l+w2*w2*r)/(1+2*.75*w2*l+w2*w2*r)]
    for frequency, damping in [(12,.9),(20,.6),(30,.6)]:
        w=2*np.pi*frequency
        expected.append(w*w*r/(1+2*damping*w*l+w*w*r))
    errors=[]
    for row, target in zip(sos_coefficients(hz),expected,strict=True):
        actual=(row[0]+row[1]*q+row[2]*q*q)/(row[3]+row[4]*q+row[5]*q*q)
        np.testing.assert_allclose(actual,target,rtol=1e-8,atol=1e-10)
        errors.append(float(np.max(np.abs(actual-target))))
    assert PARAMETERS['gain']==1.262
    return {'samplingHz':hz,'frequencies':len(f),'maxComplexTransferDifferenceBySection':errors}


def main():
    if len(sys.argv) != 4:
        raise ValueError('Pass waveform diagnostic, exact-clock 60s comparison, new .dart_tool JSON')
    output = Path(sys.argv[3])
    if output.exists() or output.suffix != '.json' or not output.parent.resolve(strict=True).is_relative_to(Path('.dart_tool').resolve(strict=True)):
        raise ValueError('New .dart_tool JSON required')
    sources = [Path(p) for p in sys.argv[1:3]] + [Path(__file__),
        Path(__file__).with_name('kunugi_2013_reference.py'),
        Path(__file__).with_name('audit_knet_filtered_intensity.py')]
    hashes = {str(p): digest(p.read_bytes()) for p in sources}
    wave, prior = [json.loads(p.read_bytes()) for p in sources[:2]]
    assert len(wave['archives']) == len(prior['cases'])
    for p, h in prior['inputSha256'].items():
        assert digest(Path(p).read_bytes()) == h
    modes = ['zero', 'steady_first_sample']
    results, verified_records, verified_windows = [], 0, 0
    max_chunk_error, max_prefix_error = 0.0, 0.0
    transfer_checks = {}
    for archive, case in zip(wave['archives'], prior['cases'], strict=True):
        archive_path = Path(archive['input'])
        assert digest(archive_path.read_bytes()) == archive['sha256']
        hashes[str(archive_path)] = archive['sha256']
        by_code = {s['code']: s for s in case['stations']}
        stations = []
        with zipfile.ZipFile(archive_path) as source:
            for record in archive['stations']:
                original = source.read(record['file'])
                assert digest(original) == record['fileSha256']
                code, samples, hz, _, start = parse_record(original)
                assert code == record['station'] and start == record['sampleStartJst']
                assert record['samplingHz'] == hz and record['sampleCount'] == len(samples)
                before = digest(samples.tobytes())
                if hz not in transfer_checks:
                    transfer_checks[hz] = verify_transfer_functions(hz)
                sos = sos_coefficients(hz)
                # Each low-pass section must have unit DC gain before final gain.
                np.testing.assert_allclose(sos[3:, :3].sum(axis=1)/sos[3:, 3:].sum(axis=1), 1, rtol=0, atol=1e-10)
                assert all(np.max(np.abs(np.roots(row[3:]))) < 1 for row in sos)
                previous = by_code[code]['conventions'][1]
                assert previous['boundary'] == 'window_end_exclusive'
                assert len(previous['rows']) == len(record['seconds'])
                reports = {}
                for mode in modes:
                    filtered, final = filter_samples(samples, hz, initialization=mode)
                    # Real prefix/chunk checks: no made-up signal and no future samples.
                    split = len(samples)//2
                    prefix, state = filter_samples(samples[:split], hz, initialization=mode)
                    suffix, chunk_final = filter_samples(samples[split:], hz, zi=state)
                    chunked = np.concatenate([prefix, suffix])
                    np.testing.assert_allclose(prefix, filtered[:split], rtol=0, atol=1e-10)
                    np.testing.assert_allclose(chunked, filtered, rtol=0, atol=1e-10)
                    np.testing.assert_allclose(chunk_final, final, rtol=0, atol=1e-10)
                    max_prefix_error = max(max_prefix_error, float(np.max(np.abs(prefix-filtered[:split]))))
                    max_chunk_error = max(max_chunk_error, float(np.max(np.abs(chunked-filtered))))
                    report = trailing_intensity_report(filtered, hz, initialization=mode)
                    assert len(report['rows']) == len(previous['rows'])
                    vector = np.linalg.norm(filtered, axis=1)
                    rows = []
                    for i, (r, old) in enumerate(zip(report['rows'], previous['rows'], strict=True)):
                        end = (i+1)*round(hz)
                        assert r['endSampleExclusive'] == end
                        assert r['hasFullHistory'] == old['hasFull60SecondHistory'] == (i>=59)
                        if i<59:
                            assert r['continuousIntensity'] is None and r['amplitudeGal'] is None
                        else:
                            # Independent full sort verifies the partition order statistic.
                            threshold = float(np.sort(vector[end-60*round(hz):end])[-math.ceil(.3*hz)])
                            assert abs(threshold-r['amplitudeGal']) < 1e-10
                            expected = 2*math.log10(threshold)+.94 if threshold>0 else None
                            assert (expected is None and r['continuousIntensity'] is None) or abs(expected-r['continuousIntensity'])<1e-10
                            verified_windows += 1
                        rows.append({'timeUtc': old['timeUtc'], 'second': i,
                                     'gifFramePresent': old['gifFramePresent'], 'gif': old['gif'],
                                     'hasFullHistory': r['hasFullHistory'],
                                     'fft60': old['filteredTrailing60'],
                                     'causal60': r['continuousIntensity']})
                    valid = [r for r in rows if r['hasFullHistory'] and r['gifFramePresent']]
                    reports[mode] = {'causal60': stats(valid, 'causal60'), 'fft60': stats(valid, 'fft60'), 'rows': rows}
                assert digest(samples.tobytes()) == before
                verified_records += 1
                stations.append({'code': code, 'scanPoint': by_code[code]['scanPoint'],
                                 'fileSha256': record['fileSha256'], 'modes': reports})
        summaries = {}
        for mode in modes:
            rows = [r for s in stations if s['scanPoint'] is not None for r in s['modes'][mode]['rows']
                    if r['gifFramePresent'] and r['hasFullHistory']]
            summaries[mode] = {'causal60': stats(rows, 'causal60'), 'fft60': stats(rows, 'fft60'),
                               'negativeGifPairs': sum(r['gif'] is not None and r['gif']<0 for r in rows)}
        initialization_differences = [abs(z['causal60']-s['causal60']) for station in stations
            for z,s in zip(station['modes']['zero']['rows'],station['modes']['steady_first_sample']['rows'],strict=True)
            if z['causal60'] is not None and s['causal60'] is not None]
        results.append({'caseId': case['caseId'], 'summaries': summaries, 'stations': stations,
                        'initializationImpact': {'fullHistoryPairsAllWaveformStations': len(initialization_differences),
                            'maxAbsIntensityDifference': max(initialization_differences, default=None),
                            'pairsAbovePointOne': sum(d>.1 for d in initialization_differences)}})
    for p,h in hashes.items():
        assert digest(Path(p).read_bytes()) == h, f'Input changed: {p}'
    result = {'feedsProduction': False, 'readyForCalibration': False,
              'reference': 'https://doi.org/10.4294/zisin.65.223', 'parameters': PARAMETERS,
              'sourceSha256': hashes, 'records': verified_records,
              'verifiedDurationWindows': verified_windows,
              'transferFunctionChecks': list(transfer_checks.values()),
              'maxChunkErrorGal': max_chunk_error, 'maxPrefixErrorGal': max_prefix_error,
              'limits': ['No fitting, pixel or time shift, padding, or original-data changes.',
                         'Both zero and steady-first-sample starts are assumptions, not recovered instrument history.',
                         'Reference causal filter is not proof of the GIF upstream algorithm/version.',
                         'Same mapped stations and right-end timestamps as preceding comparison; no outlier exclusions.',
                         'CSV precision, unknown prehistory and unverified historical pixel identity remain.',
                         'No magnitude model fitted or changed.'], 'cases': results}
    with output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, allow_nan=False, indent=2)
        stream.write('\n')
    print(json.dumps({'records': verified_records, 'verifiedWindows': verified_windows,
                     'maxChunkErrorGal': max_chunk_error, 'maxPrefixErrorGal': max_prefix_error,
                     'cases': [{'caseId': c['caseId'], 'summary': c['summaries'], 'initializationImpact': c['initializationImpact'],
                                'examples': [{ 'code': s['code'], 'modes': {m:{k:v for k,v in r.items() if k!='rows'} for m,r in s['modes'].items()}}
                                             for s in c['stations'] if s['code'] in ['AIC010','SZO025','YMN002','SIT005']]}
                               for c in results]}, ensure_ascii=False))


if __name__ == '__main__':
    main()
