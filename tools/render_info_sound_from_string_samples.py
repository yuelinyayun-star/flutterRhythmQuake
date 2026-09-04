import math
import os
import wave

import numpy as np
from scipy.io import wavfile


RATE = 44100
LENGTH = 2.35
ROOT = os.path.join(os.path.dirname(__file__), "..", "tmp", "sound_libraries", "tonejs_instruments", "common")
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_real_strings")


def read_mono(instrument, name):
    rate, data = wavfile.read(os.path.join(ROOT, instrument, name))
    if rate != RATE:
        raise ValueError(f"unexpected rate in {instrument}/{name}: {rate}")
    if data.ndim > 1:
        data = data.mean(axis=1)
    return data.astype(np.float64) / 32768.0


def onset(data):
    window = max(1, int(RATE * 0.004))
    energy = np.convolve(np.abs(data), np.ones(window) / window, mode="valid")
    threshold = max(float(np.max(energy)) * 0.015, 0.0006)
    indexes = np.flatnonzero(energy >= threshold)
    return max(0, int(indexes[0]) - int(RATE * 0.006)) if indexes.size else 0


def layer_envelope(local, length, attack, release):
    if local < 0.0 or local > length:
        return 0.0
    rise = local / attack if attack else 1.0
    fall = (length - local) / release if release else 1.0
    return (rise * rise * (3.0 - 2.0 * rise) if rise < 1.0 else 1.0) * (
        fall * fall * (3.0 - 2.0 * fall) if fall < 1.0 else 1.0
    )


def put_layer(output, data, start, length, amplitude, pan, attack, release):
    source_start = onset(data)
    first = int(start * RATE)
    count = min(int(length * RATE), len(data) - source_start, len(output) - first)
    if count <= 0:
        return
    source = data[source_start : source_start + count].copy()
    level = math.sqrt(float(np.mean(source[: min(len(source), int(RATE * 0.25))] ** 2)))
    source *= min(1.0, 0.14 / max(level, 1e-6))
    envelope = np.array(
        [layer_envelope(i / RATE, count / RATE, attack, release) for i in range(count)],
        dtype=np.float64,
    )
    source *= envelope * amplitude
    output[first : first + count, 0] += source * (1.0 - pan * 0.16)
    output[first : first + count, 1] += source * (1.0 + pan * 0.16)


output = np.zeros((int(RATE * LENGTH), 2), dtype=np.float64)

# One instrument only: different violin registers arrive one by one and dissolve
# into a single airy information cue.
layers = [
    ("violin", "G3.wav", 0.00, 1.95, 0.60, -0.34, 0.30, 0.70),
    ("violin", "C4.wav", 0.13, 1.82, 0.54, -0.22, 0.28, 0.68),
    ("violin", "E4.wav", 0.26, 1.69, 0.50, -0.08, 0.26, 0.64),
    ("violin", "G4.wav", 0.39, 1.56, 0.45, 0.08, 0.24, 0.60),
    ("violin", "C5.wav", 0.52, 1.43, 0.40, 0.22, 0.22, 0.58),
    ("violin", "E5.wav", 0.65, 1.30, 0.36, 0.34, 0.20, 0.55),
    ("violin", "G5.wav", 0.78, 1.17, 0.31, 0.46, 0.18, 0.52),
    ("violin", "A5.wav", 0.91, 1.04, 0.26, 0.58, 0.16, 0.50),
]
for instrument, name, start, length, amplitude, pan, attack, release in layers:
    put_layer(output, read_mono(instrument, name), start, length, amplitude, pan, attack, release)

# A quiet real-sample reflection makes the final decay airy without adding a
# synthetic pad or another musical attack.
for delay, amount in ((0.10, 0.045), (0.19, 0.018)):
    offset = int(delay * RATE)
    delayed = np.zeros_like(output)
    delayed[offset:] = output[:-offset]
    output += delayed * amount

peak = float(np.max(np.abs(output)))
output *= 0.68 / max(peak, 1e-9)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_real_violin_sweep.wav")
with wave.open(path, "wb") as result:
    result.setnchannels(2)
    result.setsampwidth(2)
    result.setframerate(RATE)
    pcm = np.clip(output * 32767.0, -32768, 32767).astype("<i2")
    result.writeframes(pcm.tobytes())
print(path)
