import json
import math
import os
import struct
import wave


ROOT = os.path.join(os.path.dirname(__file__), "..")
SREV_ANALYSIS = os.path.join(ROOT, "tmp", "srev_update_analysis", "srev_update_midi_like.json")
VX_ANALYSIS = os.path.join(ROOT, "tmp", "vxse52_analysis", "vxse52_midi_like.json")
OUT_DIR = os.path.join(ROOT, "tmp", "reference_sound_reconstructions")


def midi_hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def band_envelope(t, band):
    onset = band.get("onset_s_at_10pct")
    strong_start = band.get("strong_start_s_at_50pct")
    peak = band.get("peak_s")
    strong_end = band.get("strong_end_s_at_50pct")
    tail_end = band.get("tail_end_s_at_10pct")
    if None in (onset, strong_start, peak, strong_end, tail_end):
        return 0.0
    if t < onset or t > tail_end:
        return 0.0
    if t < strong_start:
        span = max(strong_start - onset, 1e-5)
        return 0.1 + 0.4 * smoothstep((t - onset) / span)
    if t < peak:
        span = max(peak - strong_start, 1e-5)
        return 0.5 + 0.5 * smoothstep((t - strong_start) / span)
    if t < strong_end:
        span = max(strong_end - peak, 1e-5)
        return 1.0 - 0.5 * smoothstep((t - peak) / span)
    span = max(tail_end - strong_end, 1e-5)
    return 0.5 * (1.0 - smoothstep((t - strong_end) / span))


def write_pcm(path, rate, channels, samples):
    peak = max(max(abs(value) for value in frame) for frame in samples)
    gain = 0.82 / max(peak, 1e-9)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(rate)
        frames = bytearray()
        for frame in samples:
            for value in frame:
                sample = int(clamp(value * gain, -1.0, 1.0) * 32767.0)
                frames.extend(struct.pack("<h", sample))
        output.writeframes(frames)


def load_json(path):
    with open(path, "r", encoding="utf-8") as source:
        return json.load(source)


def reconstruct_srev(data):
    rate = data["format"]["sample_rate_hz"]
    length = data["format"]["duration_s"]
    bands = data["frequency_bands"]
    phases = [0.0] * len(bands)
    samples = []
    # The two main bands form one coherent interval. Upper bands are only the
    # short transient layer reported by the analysis, not extra melody notes.
    weights = {"main_note": 1.0, "upper_transient": 0.22}
    for index in range(round(rate * length)):
        t = index / rate
        value = 0.0
        for band_index, band in enumerate(bands):
            envelope = band_envelope(t, band)
            if envelope == 0.0:
                continue
            frequency = band["frequency_hz"]
            phases[band_index] += 2.0 * math.pi * frequency / rate
            phase = phases[band_index]
            # The source has a glassy, processed partial structure rather than
            # the attack/noise profile of a plucked acoustic instrument.
            harmonic = math.sin(phase) + 0.11 * math.sin(2.0 * phase)
            value += weights[band["role"]] * envelope * harmonic
        samples.append((value, value))
    path = os.path.join(OUT_DIR, "srev_update_reconstruction.wav")
    write_pcm(path, rate, 2, samples)
    return path


def reconstruct_vx(data):
    rate = data["format"]["sample_rate_hz"]
    length = data["format"]["duration_s"]
    bands = data["frequency_layers"]
    phases = [0.0] * len(bands)
    # Relative levels keep D3/D4 as the body while the upper D-add9 layers
    # provide the rising, air-like sweep heard in the reference.
    weights = [0.28, 0.25, 0.22, 0.18, 0.21, 0.20, 0.15, 0.09, 0.12, 0.10]
    samples = []
    for index in range(round(rate * length)):
        t = index / rate
        value = 0.0
        for band_index, band in enumerate(bands):
            envelope = band_envelope(t, band)
            if envelope == 0.0:
                continue
            phases[band_index] += 2.0 * math.pi * band["frequency_hz"] / rate
            phase = phases[band_index]
            # Gentle FM and a small upper partial preserve the processed,
            # non-acoustic character without inventing a separate melody.
            modulation = 0.0015 * math.sin(2.0 * math.pi * 3.1 * t)
            value += weights[band_index] * envelope * (
                math.sin(phase * (1.0 + modulation))
                + 0.08 * math.sin(2.0 * phase)
            )
        samples.append((value,))
    path = os.path.join(OUT_DIR, "vxse52_reconstruction.wav")
    write_pcm(path, rate, 1, samples)
    return path


if __name__ == "__main__":
    srev = reconstruct_srev(load_json(SREV_ANALYSIS))
    vx = reconstruct_vx(load_json(VX_ANALYSIS))
    print(srev)
    print(vx)
