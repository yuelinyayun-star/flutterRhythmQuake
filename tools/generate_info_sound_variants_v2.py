import math
import os
import wave


RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_variants_v2")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def bell(t, frequency, decay, brightness):
    phase = 2.0 * math.pi * frequency * t
    value = math.sin(phase)
    value += brightness * 0.34 * math.sin(phase * 2.0)
    value += brightness * 0.12 * math.sin(phase * 3.0)
    value += brightness * 0.05 * math.sin(phase * 5.0)
    attack = min(1.0, t / 0.012)
    return value * attack * math.exp(-t / decay)


def pad(t, frequency, release):
    phase = 2.0 * math.pi * frequency * t
    attack = min(1.0, t / 0.16)
    return math.sin(phase) * attack * math.exp(-t / release)


def render(notes, pad_notes, brightness, length=2.8):
    count = int(RATE * length)
    left = []
    right = []
    for index in range(count):
        t = index / RATE
        value = 0.0
        for start, midi, amp, decay in notes:
            local = t - start
            if local >= 0:
                value += amp * bell(local, hz(midi), decay, brightness)
        for start, midi, amp in pad_notes:
            local = t - start
            if local >= 0:
                value += amp * pad(local, hz(midi), 1.9)
        fade = min(1.0, t / 0.04, max(0.0, (length - t) / 0.32))
        value *= fade
        left.append(value * 0.92)
        right.append(value * 0.84)
    return left, right


def write_wav(path, left, right):
    with wave.open(path, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        peak = max(max(abs(value) for value in left), max(abs(value) for value in right), 1e-9)
        gain = 0.78 / peak
        frames = bytearray()
        for l, r in zip(left, right):
            l = max(-1.0, min(1.0, l * gain))
            r = max(-1.0, min(1.0, r * gain))
            frames += int(l * 32767).to_bytes(2, "little", signed=True)
            frames += int(r * 32767).to_bytes(2, "little", signed=True)
        output.writeframes(frames)


VARIANTS = {
    "01_clear_c": {
        "notes": [(0.04, 60, 0.30, 0.56), (0.34, 64, 0.26, 0.62), (0.68, 67, 0.22, 0.70), (1.06, 72, 0.18, 1.00)],
        "pad": [(0.02, 48, 0.055), (0.38, 55, 0.045)],
        "brightness": 0.28,
    },
    "02_silver_fsharp": {
        "notes": [(0.04, 66, 0.24, 0.50), (0.28, 70, 0.22, 0.56), (0.60, 73, 0.19, 0.64), (0.96, 78, 0.16, 0.92)],
        "pad": [(0.02, 54, 0.05), (0.30, 61, 0.042)],
        "brightness": 0.48,
    },
    "03_warm_a": {
        "notes": [(0.05, 57, 0.31, 0.66), (0.42, 61, 0.27, 0.72), (0.80, 64, 0.22, 0.82), (1.22, 69, 0.17, 1.12)],
        "pad": [(0.01, 45, 0.065), (0.44, 52, 0.05)],
        "brightness": 0.18,
    },
    "04_amber_eb": {
        "notes": [(0.03, 63, 0.27, 0.62), (0.38, 67, 0.24, 0.68), (0.74, 70, 0.20, 0.78), (1.14, 75, 0.15, 1.04)],
        "pad": [(0.02, 51, 0.06), (0.40, 58, 0.045)],
        "brightness": 0.36,
    },
    "05_distant_b": {
        "notes": [(0.04, 71, 0.22, 0.72), (0.46, 75, 0.20, 0.78), (0.88, 78, 0.17, 0.90), (1.34, 83, 0.13, 1.22)],
        "pad": [(0.02, 59, 0.04), (0.48, 66, 0.035)],
        "brightness": 0.22,
    },
}


os.makedirs(OUT, exist_ok=True)
for name, config in VARIANTS.items():
    left, right = render(config["notes"], config["pad"], config["brightness"])
    write_wav(os.path.join(OUT, f"info_music_{name}.wav"), left, right)
