"""Offline JMA-filter diagnostic on unchanged original K-NET CSV archives."""
import csv
import hashlib
import io
import json
import math
from datetime import datetime
from pathlib import Path
import sys
import zipfile

import numpy as np
from scipy import fft


def digest(data):
    return hashlib.sha256(data).hexdigest()


def response(frequencies):
    # JMA's three frequency filters; the DC response is the limiting value 0.
    f = np.abs(frequencies)
    positive = f > 0
    h = np.zeros_like(f)
    x = f[positive]
    y = x / 10.0
    low = np.sqrt(-np.expm1(-(x / 0.5) ** 3))
    high = 1 / np.sqrt(1 + .694*y**2 + .241*y**4 + .0557*y**6
                       + .009664*y**8 + .00134*y**10 + .000155*y**12)
    h[positive] = low * high / np.sqrt(x)
    return h


def intensity(vector, sampling_hz):
    count = math.ceil(.3 * sampling_hz)
    if len(vector) < count:
        raise ValueError('Record too short for cumulative 0.3 second exceedance')
    a = float(np.partition(vector, len(vector) - count)[-count])
    assert np.count_nonzero(vector >= a) >= count
    assert np.count_nonzero(vector > a) < count
    return {'amplitudeGal': a, 'continuousIntensity': 2*math.log10(a) + .94 if a > 0 else None}


def filtered_rank(station):
    value = station['filteredRecord']['continuousIntensity']
    return -math.inf if value is None else value


def parse_record(data):
    rows = list(csv.reader(io.StringIO(data.decode('utf-8-sig'))))
    if rows[0] != ['#K-NET CSV']:
        raise ValueError('Not original K-NET CSV')
    markers = {row[0]: i for i, row in enumerate(rows) if row and row[0].startswith('#')}
    header_index = markers['#Time']
    expected = ['#Time', 'RelativeTime(s)', 'N-S(gal)', 'E-W(gal)', 'U-D(gal)']
    if rows[header_index] != expected:
        raise ValueError('Only complete three-component surface records supported')
    fs = float(rows[markers['#SamplingFrequency(Hz)'] + 1][0].lstrip('#'))
    duration = float(rows[markers['#DurationTime(s)'] + 1][0].lstrip('#'))
    station = rows[markers['#Station'] + 2]
    offsets = np.array([float(v.lstrip('#')) for v in rows[markers['#Offset'] + 2]])
    body = [r for r in rows[header_index + 1:] if r]
    if any(len(r) != 5 for r in body):
        raise ValueError('Incomplete waveform row')
    times = np.array([float(r[1]) for r in body])
    samples = np.array([[float(v) for v in r[2:]] for r in body])
    if not np.isfinite(samples).all() or fs <= 0 or len(samples) != round(duration * fs):
        raise ValueError('Invalid sample rate, samples or duration')
    np.testing.assert_allclose(times, np.arange(len(samples))/fs, rtol=0, atol=1e-7)
    dt = lambda s: datetime.strptime(s, '%Y/%m/%d %H:%M:%S.%f')
    assert abs((dt(body[-1][0])-dt(body[0][0])).total_seconds()-times[-1]) < 1e-6
    samples.setflags(write=False)
    return station[0].lstrip('#'), samples, fs, offsets, body[0][0]


def audit_record(name, data):
    station, samples, sampling_hz, offsets, start = parse_record(data)
    original_digest = digest(samples.tobytes())
    n = len(samples)
    spectrum = fft.rfft(samples, axis=0)
    filtered = fft.irfft(spectrum * response(fft.rfftfreq(n, 1/sampling_hz))[:, None], n=n, axis=0)
    # Different FFT implementation and full complex transform on the same real data.
    independent = np.fft.ifft(np.fft.fft(samples, axis=0)
                             * response(np.fft.fftfreq(n, 1/sampling_hz))[:, None], axis=0)
    np.testing.assert_allclose(filtered, independent.real, rtol=1e-10, atol=1e-10)
    assert float(np.max(np.abs(independent.imag))) < 1e-9
    np.testing.assert_allclose(fft.irfft(spectrum, n=n, axis=0), samples, rtol=1e-11, atol=1e-10)
    assert digest(samples.tobytes()) == original_digest
    filtered_vector = np.linalg.norm(filtered, axis=1)
    unfiltered_vector = np.linalg.norm(samples - offsets, axis=1)
    step = round(sampling_hz)
    if abs(step - sampling_hz) > 1e-9 or n % step:
        raise ValueError('One-second comparison requires integer rate and full seconds')
    seconds = [{'second': i // step,
                'filtered': intensity(filtered_vector[i:i+step], sampling_hz),
                'unfiltered': intensity(unfiltered_vector[i:i+step], sampling_hz)}
               for i in range(0, n, step)]
    return {'file': name, 'fileSha256': digest(data), 'station': station,
            'sampleStartJst': start, 'samplingHz': sampling_hz, 'sampleCount': n,
            'filteredRecord': intensity(filtered_vector, sampling_hz),
            'unfilteredRecord': intensity(unfiltered_vector, sampling_hz),
            'maximumFftDifferenceGal': float(np.max(np.abs(filtered-independent.real))),
            'seconds': seconds}


def main():
    if len(sys.argv) < 3:
        raise ValueError('Pass original ZIP(s), then new JSON output in existing .dart_tool directory')
    output = Path(sys.argv[-1])
    parent = output.parent.resolve(strict=True)
    if output.exists() or output.suffix != '.json' or not parent.is_relative_to(Path('.dart_tool').resolve(strict=True)):
        raise ValueError('Output must be a new .dart_tool JSON')
    archives = []
    for argument in sys.argv[1:-1]:
        source = Path(argument)
        data = source.read_bytes()
        rows = []
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for name in archive.namelist():
                if name.lower().endswith('.csv'):
                    rows.append(audit_record(name, archive.read(name)))
        if not rows:
            raise ValueError('No CSV records')
        assert digest(source.read_bytes()) == digest(data)
        archives.append({'input': argument, 'sha256': digest(data), 'stations': rows})
    result = {'feedsProduction': False, 'readyForCalibration': False,
              'method': 'JMA frequency response, three-component norm, 0.3-second order statistic',
              'reference': 'https://www.jma.go.jp/jma/kishou/know/jishin/kyoshin/kaisetsu/calc_sindo.html',
              'processing': 'Original CSV acceleration; no resampling, interpolation, padding or taper. DC removed by filter; unfiltered comparison subtracts declared offsets.',
              'limits': ['Finite-record FFT has periodic boundary assumptions; edge effects remain.',
                         'CSV precision is 0.01 gal; this cannot recover lost small amplitudes.',
                         'Not a certified JMA intensity or a magnitude estimate.',
                         'Record-wide and one-second diagnostics are distinct; neither is assumed identical to NIED realtime GIF intensity.',
                         'Two FFT implementations verify numerical consistency, not the measurement definition.'],
              'numpyVersion': np.__version__, 'archives': archives}
    with output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, allow_nan=False, indent=2)
        stream.write('\n')
    print(json.dumps([{'input': a['input'], 'records': len(a['stations']),
                       'maximumFftDifferenceGal': max(s['maximumFftDifferenceGal'] for s in a['stations']),
                       'strongestFiltered': max(a['stations'], key=filtered_rank)['station']}
                      for a in archives]))


if __name__ == '__main__':
    main()
