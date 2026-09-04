import json
import math
import os
import wave

import numpy as np
from scipy.signal import find_peaks


SOURCE = r"C:\Users\Rhythm\AppData\Local\Programs\WQuake\web\audio\VXSE52.ogg"
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "vxse52_analysis", "vxse52_midi_like.json")
RATE = 48000
WINDOW = 4096
NFFT = 8192
HOP = 480

# These are measured spectral bands in VXSE52, not an invented replacement
# melody. Each band is reported separately because the source is polyphonic.
NOTE_BANDS = [
    ("D3", 146.83),
    ("D4", 293.66),
    ("A4", 440.00),
    ("D5", 587.33),
    ("E5", 659.26),
    ("F#5", 739.99),
    ("A5", 880.00),
    ("C6", 1046.50),
    ("D6", 1174.66),
    ("E6", 1318.51),
]


def nearest_midi(frequency):
    return int(round(69.0 + 12.0 * math.log2(frequency / 440.0)))


def load_source():
    with wave.open(SOURCE, "rb") as source:
        rate = source.getframerate()
        channels = source.getnchannels()
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64)
    if channels > 1:
        samples = samples.reshape(-1, channels).mean(axis=1)
    return rate, samples / 32768.0


def analyze(rate, samples):
    if rate != RATE:
        raise ValueError(f"expected {RATE} Hz, got {rate} Hz")
    frequencies = np.fft.rfftfreq(NFFT, 1.0 / rate)
    window = np.hanning(WINDOW)
    times = []
    spectra = []
    for start in range(0, len(samples) - WINDOW, HOP):
        frame = samples[start : start + WINDOW] * window
        spectra.append(np.abs(np.fft.rfft(np.pad(frame, (0, NFFT - WINDOW)))))
        times.append((start + WINDOW / 2.0) / rate)
    spectra = np.asarray(spectra)
    times = np.asarray(times)

    tracks = []
    for name, target in NOTE_BANDS:
        band = (frequencies >= target - 10.0) & (frequencies <= target + 10.0)
        envelope = spectra[:, band].max(axis=1)
        normalized = envelope / max(float(envelope.max()), 1e-12)
        peak_index = int(np.argmax(envelope))
        active = np.flatnonzero(normalized >= 0.10)
        strong = np.flatnonzero(normalized >= 0.50)
        tracks.append(
            {
                "note": name,
                "frequency_hz": target,
                "midi": nearest_midi(target),
                "onset_s_at_10pct": float(times[active[0]]) if len(active) else None,
                "strong_start_s_at_50pct": float(times[strong[0]]) if len(strong) else None,
                "peak_s": float(times[peak_index]),
                "strong_end_s_at_50pct": float(times[strong[-1]]) if len(strong) else None,
                "tail_end_s_at_10pct": float(times[active[-1]]) if len(active) else None,
                "relative_peak": 1.0,
            }
        )

    normalized_spectra = spectra / (spectra.sum(axis=1, keepdims=True) + 1e-12)
    flux = np.sqrt(np.sum(np.maximum(0.0, normalized_spectra[1:] - normalized_spectra[:-1]) ** 2, axis=1))
    peaks, properties = find_peaks(flux, distance=2, prominence=max(float(flux.max()) * 0.12, 0.001))
    attacks = [
        {"time_s": float(times[index + 1]), "spectral_flux": float(flux[index])}
        for index in peaks
        if times[index + 1] <= 1.0
    ]

    return {
        "source": SOURCE,
        "format": {"sample_rate_hz": int(rate), "channels": 1, "duration_s": len(samples) / rate},
        "method": {
            "window_ms": WINDOW / rate * 1000.0,
            "hop_ms": HOP / rate * 1000.0,
            "note": "Spectral-band transcription. Because VXSE52 is polyphonic and processed, these are frequency-layer events rather than a guaranteed original MIDI track.",
        },
        "attack_events_first_second": attacks,
        "frequency_layers": tracks,
    }


rate, samples = load_source()
result = analyze(rate, samples)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as output:
    json.dump(result, output, ensure_ascii=False, indent=2)
print(OUT)
