import math
import os
import wave


RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_variants_v4")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def soft_note(t, frequency, decay, brightness):
    phase = 2.0 * math.pi * frequency * t
    attack = 1.0 - math.exp(-t / 0.038)
    envelope = attack * math.exp(-t / decay)
    value = math.sin(phase)
    value += brightness * 0.16 * math.sin(phase * 2.0)
    value += brightness * 0.045 * math.sin(phase * 3.0)
    value += brightness * 0.012 * math.sin(phase * 5.0)
    return value * envelope


def quiet_foundation(t, frequency, release):
    phase = 2.0 * math.pi * frequency * t
    attack = 1.0 - math.exp(-t / 0.42)
    return math.sin(phase) * attack * math.exp(-t / release)


def render(notes, foundation, brightness, length=2.65):
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
            value = amp * soft_note(local, hz(midi), decay, brightness)
            l_value += value * (1.0 - pan * 0.16)
            r_value += value * (1.0 + pan * 0.16)
        for start, midi, amp, release in foundation:
            local = t - start
            if local >= 0:
                value = amp * quiet_foundation(local, hz(midi), release)
                l_value += value
                r_value += value * 0.94
        fade = min(1.0, t / 0.08, max(0.0, (length - t) / 0.42))
        left.append(l_value * fade)
        right.append(r_value * fade)
    return left, right


def write_wav(path, left, right):
    peak = max(max(abs(value) for value in left), max(abs(value) for value in right), 1e-9)
    gain = 0.68 / peak
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
    "01_open_c": {
        "motif": "C5-G5-E5-D5-G5",
        "notes": [(0.08, 72, 0.20, 0.78, -0.4), (0.43, 79, 0.14, 0.86, 0.3), (0.82, 76, 0.15, 0.88, -0.2), (1.25, 74, 0.11, 0.82, 0.25), (1.70, 79, 0.10, 1.08, 0.0)],
        "foundation": [(0.02, 48, 0.012, 2.1)],
        "brightness": 0.25,
    },
    "02_ripple_fsharp": {
        "motif": "F#5-C#5-A#5-F#5-C#6",
        "notes": [(0.06, 78, 0.17, 0.74, -0.2), (0.28, 73, 0.13, 0.72, 0.4), (0.66, 82, 0.12, 0.82, -0.35), (1.12, 78, 0.10, 0.92, 0.25), (1.72, 85, 0.085, 1.18, 0.0)],
        "foundation": [(0.02, 54, 0.010, 2.0)],
        "brightness": 0.42,
    },
    "03_breath_a": {
        "motif": "A4-E5-C#5-B4-E5-A5",
        "notes": [(0.10, 69, 0.22, 0.92, -0.3), (0.51, 76, 0.15, 0.84, 0.3), (0.95, 73, 0.13, 0.86, -0.25), (1.16, 71, 0.095, 0.76, 0.2), (1.64, 76, 0.11, 0.94, -0.1), (2.08, 81, 0.075, 1.24, 0.0)],
        "foundation": [(0.03, 45, 0.014, 2.2)],
        "brightness": 0.17,
    },
    "04_glass_eb": {
        "motif": "Eb5-G5-Bb5-G5-Eb5",
        "notes": [(0.07, 75, 0.18, 0.78, -0.4), (0.48, 79, 0.13, 0.84, 0.25), (0.88, 82, 0.12, 0.96, -0.2), (1.39, 79, 0.09, 0.92, 0.3), (1.90, 75, 0.075, 1.30, 0.0)],
        "foundation": [(0.02, 51, 0.010, 2.1)],
        "brightness": 0.52,
    },
    "05_return_b": {
        "motif": "B5-A#5-F#5-D#6-C#6",
        "notes": [(0.09, 83, 0.15, 0.86, -0.25), (0.34, 82, 0.11, 0.80, 0.35), (0.77, 78, 0.10, 0.90, -0.3), (1.31, 87, 0.085, 1.02, 0.2), (1.96, 85, 0.065, 1.36, 0.0)],
        "foundation": [(0.02, 59, 0.008, 2.2)],
        "brightness": 0.30,
    },
}


os.makedirs(OUT, exist_ok=True)
for name, config in VARIANTS.items():
    left, right = render(config["notes"], config["foundation"], config["brightness"])
    write_wav(os.path.join(OUT, f"info_music_{name}.wav"), left, right)
