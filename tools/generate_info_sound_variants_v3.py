import math
import os
import wave


RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_variants_v3")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def bell(t, frequency, decay, brightness):
    phase = 2.0 * math.pi * frequency * t
    value = math.sin(phase)
    value += brightness * 0.28 * math.sin(phase * 2.01)
    value += brightness * 0.10 * math.sin(phase * 3.01)
    value += brightness * 0.035 * math.sin(phase * 5.02)
    attack = min(1.0, t / 0.016)
    return value * attack * math.exp(-t / decay)


def pad(t, frequency, release):
    phase = 2.0 * math.pi * frequency * t
    attack = min(1.0, t / 0.20)
    return (math.sin(phase) + 0.16 * math.sin(phase * 2.0)) * attack * math.exp(-t / release)


def render(notes, pads, brightness, length=3.0):
    count = int(RATE * length)
    left = []
    right = []
    for index in range(count):
        t = index / RATE
        l_value = 0.0
        r_value = 0.0
        for start, midi, amp, decay, pan in notes:
            local = t - start
            if local < 0:
                continue
            value = amp * bell(local, hz(midi), decay, brightness)
            l_value += value * (1.0 - pan * 0.20)
            r_value += value * (1.0 + pan * 0.20)
        for start, midi, amp, release in pads:
            local = t - start
            if local >= 0:
                value = amp * pad(local, hz(midi), release)
                l_value += value * 0.94
                r_value += value * 0.88
        fade = min(1.0, t / 0.05, max(0.0, (length - t) / 0.38))
        left.append(l_value * fade)
        right.append(r_value * fade)
    return left, right


def write_wav(path, left, right):
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right), 1e-9)
    gain = 0.78 / peak
    with wave.open(path, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        frames = bytearray()
        for l, r in zip(left, right):
            l = max(-1.0, min(1.0, l * gain))
            r = max(-1.0, min(1.0, r * gain))
            frames += int(l * 32767).to_bytes(2, "little", signed=True)
            frames += int(r * 32767).to_bytes(2, "little", signed=True)
        output.writeframes(frames)


VARIANTS = {
    "01_arc_c": {
        "motif": "C4-G4-E4-D4-G4",
        "notes": [(0.04, 60, 0.28, 0.68, -0.5), (0.36, 67, 0.22, 0.72, 0.3), (0.70, 64, 0.24, 0.78, -0.2), (1.04, 62, 0.18, 0.82, 0.2), (1.42, 67, 0.15, 1.20, 0.0)],
        "pads": [(0.02, 48, 0.055, 2.0), (0.68, 55, 0.040, 1.8)],
        "brightness": 0.30,
    },
    "02_turn_fsharp": {
        "motif": "F#4-A#4-C#5-A#4-F#4",
        "notes": [(0.05, 66, 0.24, 0.62, -0.2), (0.25, 70, 0.19, 0.66, 0.4), (0.57, 73, 0.18, 0.76, -0.3), (0.94, 70, 0.17, 0.82, 0.2), (1.30, 66, 0.14, 1.22, 0.0)],
        "pads": [(0.01, 54, 0.045, 2.1), (0.58, 61, 0.038, 1.8)],
        "brightness": 0.54,
    },
    "03_answer_a": {
        "motif": "A3-E4-C#4-B3-E4-A4",
        "notes": [(0.06, 57, 0.30, 0.78, -0.4), (0.42, 64, 0.22, 0.72, 0.3), (0.75, 61, 0.20, 0.76, -0.2), (1.08, 59, 0.18, 0.82, 0.2), (1.48, 64, 0.16, 0.92, -0.1), (1.86, 69, 0.13, 1.30, 0.0)],
        "pads": [(0.01, 45, 0.065, 2.2), (0.76, 52, 0.045, 1.9)],
        "brightness": 0.20,
    },
    "04_window_eb": {
        "motif": "Eb4-Bb4-G4-Bb4-Eb5",
        "notes": [(0.04, 63, 0.27, 0.70, -0.3), (0.40, 70, 0.20, 0.76, 0.3), (0.78, 67, 0.22, 0.82, -0.2), (1.16, 70, 0.17, 0.88, 0.2), (1.58, 75, 0.14, 1.28, 0.0)],
        "pads": [(0.02, 51, 0.058, 2.1), (0.80, 58, 0.042, 1.9)],
        "brightness": 0.38,
    },
    "05_leap_b": {
        "motif": "B4-F#4-D#5-C#5-F#5",
        "notes": [(0.08, 71, 0.22, 0.78, -0.4), (0.31, 66, 0.18, 0.70, 0.35), (0.70, 75, 0.17, 0.84, -0.25), (1.12, 73, 0.15, 0.90, 0.25), (1.55, 78, 0.12, 1.35, 0.0)],
        "pads": [(0.02, 59, 0.040, 2.2), (0.72, 66, 0.032, 1.9)],
        "brightness": 0.25,
    },
}


os.makedirs(OUT, exist_ok=True)
for name, config in VARIANTS.items():
    left, right = render(config["notes"], config["pads"], config["brightness"])
    write_wav(os.path.join(OUT, f"info_music_{name}.wav"), left, right)
