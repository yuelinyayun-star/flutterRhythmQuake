import math
import os
import wave

import numpy as np
from scipy.io import wavfile


RATE = 44100
LENGTH = 1.20
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


def add_note(output, data, start, length, amplitude, pan):
    first_source = find_onset(data)
    first_output = int(start * RATE)
    count = min(int(length * RATE), len(data) - first_source, len(output) - first_output)
    if count <= 0:
        return
    source = data[first_source : first_source + count].copy()
    level = math.sqrt(float(np.mean(source[: min(len(source), int(RATE * 0.18))] ** 2)))
    source *= min(1.0, 0.16 / max(level, 1e-6))
    # The source cue's musical body is short; leave a soft real-string tail.
    fade = min(int(RATE * 0.18), count)
    source[-fade:] *= np.linspace(1.0, 0.0, fade)
    output[first_output:, 0][:count] += source * amplitude * (1.0 - pan * 0.14)
    output[first_output:, 1][:count] += source * amplitude * (1.0 + pan * 0.14)


output = np.zeros((int(RATE * LENGTH), 2), dtype=np.float64)

# Exact musical core extracted from assets/sounds/srev/update.mp3:
# E4 + B4, a perfect fifth, with a 10 ms stereo-safe attack difference.
add_note(output, read_mono("E4.wav"), 0.056, 0.43, 0.18, -0.12)
add_note(output, read_mono("B4.wav"), 0.066, 0.44, 0.17, 0.12)

# A reflection of the same two notes only; no added pitch or instrument.
for delay, amount in ((0.085, 0.035), (0.16, 0.014)):
    offset = int(delay * RATE)
    delayed = np.zeros_like(output)
    delayed[offset:] = output[:-offset]
    output += delayed * amount

peak = float(np.max(np.abs(output)))
output *= 0.68 / max(peak, 1e-9)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_exact_e4_b4_airy.wav")
with wave.open(path, "wb") as result:
    result.setnchannels(2)
    result.setsampwidth(2)
    result.setframerate(RATE)
    pcm = np.clip(output * 32767.0, -32768, 32767).astype("<i2")
    result.writeframes(pcm.tobytes())
print(path)
