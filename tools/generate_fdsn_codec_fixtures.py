"""Generate deterministic codec fixtures using ObsPy/libmseed, not live stations."""
import io
import json
from pathlib import Path
import numpy as np
from obspy import Trace, UTCDateTime, read

target = Path('test/fixtures/fdsn_codec')
target.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(42)
samples = (123456 + np.cumsum(rng.integers(-300, 300, size=1600))).astype(np.int32)
expected = []
for encoding in ('INT16', 'INT32', 'STEIM1', 'STEIM2'):
    values = samples if encoding != 'INT16' else (samples - 123456).astype(np.int16)
    for byteorder in ('>', '<'):
        trace = Trace(values.copy(), header=dict(network='XX', station='TEST',
            location='00', channel='HNZ', sampling_rate=100,
            starttime=UTCDateTime('2026-09-09T00:00:00Z')))
        path = target / f'{encoding}_{"be" if byteorder == ">" else "le"}.mseed'
        trace.write(str(path), format='MSEED', encoding=encoding, reclen=512, byteorder=byteorder)
        raw = path.read_bytes()
        combined = []
        for offset in range(0, len(raw), 512):
            decoded = read(io.BytesIO(raw[offset:offset + 512]), format='MSEED')[0].data.tolist()
            combined.extend(decoded)
            expected.append(dict(file=path.name, offset=offset, samples=decoded))
        assert combined == values.tolist()
(target / 'expected.json').write_text(json.dumps(expected), encoding='utf-8')
print(f'{len(expected)} records, {len(expected) * 512} raw bytes')
