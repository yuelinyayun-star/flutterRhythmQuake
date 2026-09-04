import math
import os
import wave

import numpy as np
from scipy.io import wavfile


RATE = 44100
LENGTH = 2.05
ROOT = os.path.join(
    os.path.dirname(__file__), "..", "tmp", "sound_libraries", "tonejs_instruments", "common", "guitar-nylon"
)
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_real_guitar")


def read_mono(name):
    rate, data = wavfile.read(os.path.join(ROOT, name))
    if rate != RATE:
        raise ValueError(f"unexpected sample rate in {name}: {rate}")
    if data.ndim > 1:
        data = data.mean(axis=1)
    return data.astype(np.float64) / 32768.0


def find_onset(data):
    window = max(1, int(RATE * 0.004))
    energy = np.convolve(np.abs(data), np.ones(window) / window, mode="valid")
    threshold = max(float(np.max(energy)) * 0.015, 0.0006)
    indexes = np.flatnonzero(energy >= threshold)
    return max(0, int(indexes[0]) - int(RATE * 0.004)) if indexes.size else 0


def place_sample(output, data, start, length, amplitude, pan, release):
    source_start = find_onset(data)
    first = int(start * RATE)
    count = min(int(length * RATE), len(data) - source_start, len(output) - first)
    if count <= 0:
        return
    source = data[source_start : source_start + count].copy()
    # Match the recorded sample levels while retaining their real attack and decay.
    level = math.sqrt(float(np.mean(source[: min(len(source), int(RATE * 0.18))] ** 2)))
    source *= min(1.0, 0.16 / max(level, 1e-6))
    fade = min(int(release * RATE), count)
    if fade:
        source[-fade:] *= np.linspace(1.0, 0.0, fade)
    left_gain = amplitude * (1.0 - pan * 0.16)
    right_gain = amplitude * (1.0 + pan * 0.16)
    output[first : first + count, 0] += source * left_gain
    output[first : first + count, 1] += source * right_gain


output = np.zeros((int(RATE * LENGTH), 2), dtype=np.float64)

# One instrument, one compact cue: three short plucks followed by one held note.
place_sample(output, read_mono("D5.wav"), 0.055, 0.30, 0.18, 0.20, 0.11)
place_sample(output, read_mono("A4.wav"), 0.205, 0.30, 0.17, -0.05, 0.11)
place_sample(output, read_mono("Fs4.wav"), 0.355, 0.34, 0.18, -0.22, 0.12)
place_sample(output, read_mono("D5.wav"), 0.535, 1.32, 0.22, 0.05, 0.46)

# Only a quiet reflection of the same notes; no second instrument or pad.
for delay, amount in ((0.09, 0.035), (0.17, 0.014)):
    offset = int(delay * RATE)
    delayed = np.zeros_like(output)
    delayed[offset:] = output[:-offset]
    output += delayed * amount

peak = float(np.max(np.abs(output)))
output *= 0.68 / max(peak, 1e-9)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_three_plucks_then_long_string.wav")
with wave.open(path, "wb") as result:
    result.setnchannels(2)
    result.setsampwidth(2)
    result.setframerate(RATE)
    pcm = np.clip(output * 32767.0, -32768, 32767).astype("<i2")
    result.writeframes(pcm.tobytes())
print(path)
