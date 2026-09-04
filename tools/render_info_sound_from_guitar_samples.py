import math
import os
import wave

import numpy as np
from scipy.io import wavfile


RATE = 44100
LENGTH = 1.85
SAMPLE_ROOT = os.path.join(
    os.path.dirname(__file__), "..", "tmp", "sound_libraries", "tonejs_instruments", "common", "guitar-nylon"
)
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_real_guitar")


def read_mono(name):
    rate, data = wavfile.read(os.path.join(SAMPLE_ROOT, name))
    if rate != RATE:
        raise ValueError(f"unexpected sample rate for {name}: {rate}")
    if data.ndim > 1:
        data = data.mean(axis=1)
    return data.astype(np.float64) / 32768.0


def find_onset(data):
    window = max(1, int(RATE * 0.004))
    energy = np.convolve(np.abs(data), np.ones(window) / window, mode="valid")
    threshold = max(float(np.max(energy)) * 0.018, 0.0008)
    indexes = np.flatnonzero(energy >= threshold)
    return max(0, int(indexes[0]) - int(RATE * 0.004)) if indexes.size else 0


def place_sample(output, data, start_seconds, amplitude, pan):
    onset = find_onset(data)
    start = int(start_seconds * RATE)
    available = min(len(data) - onset, len(output) - start)
    if available <= 0:
        return
    source = data[onset : onset + available]
    # Keep the natural recorded decay, with only a final fade to prevent a hard cut.
    if available > int(RATE * 0.12):
        fade_start = available - int(RATE * 0.12)
        source = source.copy()
        source[fade_start:] *= np.linspace(1.0, 0.0, available - fade_start)
    left_gain = amplitude * (1.0 - pan * 0.18)
    right_gain = amplitude * (1.0 + pan * 0.18)
    output[start : start + available, 0] += source * left_gain
    output[start : start + available, 1] += source * right_gain


output = np.zeros((int(RATE * LENGTH), 2), dtype=np.float64)

# Four-note notification cue: a short two-note pickup, then a clear musical
# answer that resolves back toward the opening note.
strings = [
    ("A4.wav", 0.000, 0.19, -0.38),
    ("B4.wav", 0.105, 0.17, -0.18),
    ("D5.wav", 0.315, 0.16, 0.08),
    ("A4.wav", 0.505, 0.18, 0.28),
]
for name, start, amplitude, pan in strings:
    place_sample(output, read_mono(name), 0.040 + start, amplitude, pan)

# Real-sample reflections only, kept quiet so the sound remains a cue rather
# than turning into a guitar bed.
for delay, amount in ((0.082, 0.055), (0.161, 0.022)):
    delayed = np.zeros_like(output)
    offset = int(delay * RATE)
    delayed[offset:] = output[:-offset]
    output += delayed * amount

peak = float(np.max(np.abs(output)))
output = output * (0.70 / max(peak, 1e-9))
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_real_nylon_four_note_cue.wav")
with wave.open(path, "wb") as result:
    result.setnchannels(2)
    result.setsampwidth(2)
    result.setframerate(RATE)
    pcm = np.clip(output * 32767.0, -32768, 32767).astype("<i2")
    result.writeframes(pcm.tobytes())
print(path)
