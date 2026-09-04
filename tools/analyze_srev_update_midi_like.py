import json
import math
import os

import miniaudio
import numpy as np


SOURCE = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds", "srev", "update.mp3")
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "srev_update_analysis", "srev_update_midi_like.json")
WINDOW = 4096
NFFT = 8192
HOP = 441

# The first two are the musical notes. The remaining bands are reported as
# transient/upper partials, not falsely promoted to additional melody notes.
BANDS = [
    ("E4", 329.63, "main_note"),
    ("B4", 493.88, "main_note"),
    ("A4", 440.00, "upper_transient"),
    ("E5", 659.26, "upper_transient"),
    ("G#5", 830.61, "upper_transient"),
    ("D#6", 1244.51, "upper_transient"),
]


def load_source():
    decoded = miniaudio.decode_file(SOURCE)
    samples = np.asarray(decoded.samples, dtype=np.float64).reshape(-1, decoded.nchannels)
    return decoded.sample_rate, samples.mean(axis=1) / 32768.0


def midi_number(frequency):
    return int(round(69.0 + 12.0 * math.log2(frequency / 440.0)))


def analyze(rate, samples):
    frequencies = np.fft.rfftfreq(NFFT, 1.0 / rate)
    window = np.hanning(WINDOW)
    times = []
    values = []
    for start in range(0, len(samples) - WINDOW, HOP):
        frame = samples[start : start + WINDOW] * window
        spectrum = np.abs(np.fft.rfft(np.pad(frame, (0, NFFT - WINDOW))))
        times.append((start + WINDOW / 2.0) / rate)
        values.append(
            [
                float(spectrum[(frequencies >= target - 10.0) & (frequencies <= target + 10.0)].max())
                for _, target, _ in BANDS
            ]
        )
    times = np.asarray(times)
    values = np.asarray(values)
    bands = []
    for index, (name, target, role) in enumerate(BANDS):
        envelope = values[:, index]
        normalized = envelope / max(float(envelope.max()), 1e-12)
        active = np.flatnonzero(normalized >= 0.10)
        strong = np.flatnonzero(normalized >= 0.50)
        peak = int(np.argmax(envelope))
        bands.append(
            {
                "note": name,
                "midi": midi_number(target),
                "frequency_hz": target,
                "role": role,
                "onset_s_at_10pct": float(times[active[0]]) if len(active) else None,
                "strong_start_s_at_50pct": float(times[strong[0]]) if len(strong) else None,
                "peak_s": float(times[peak]),
                "strong_end_s_at_50pct": float(times[strong[-1]]) if len(strong) else None,
                "tail_end_s_at_10pct": float(times[active[-1]]) if len(active) else None,
            }
        )
    return {
        "source": os.path.abspath(SOURCE),
        "format": {"sample_rate_hz": int(rate), "channels": 2, "duration_s": len(samples) / rate},
        "musical_core": {
            "main_notes": ["E4", "B4"],
            "interval": "perfect fifth",
            "description": "A two-note E4-B4 cue with upper transient partials; upper bands are not separate melody notes.",
        },
        "frequency_bands": bands,
    }


rate, samples = load_source()
result = analyze(rate, samples)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as output:
    json.dump(result, output, ensure_ascii=False, indent=2)
print(OUT)
