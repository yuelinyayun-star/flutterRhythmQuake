import math
import os
import wave


RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_variants_v5")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def crossfade(t, start, end):
    if t <= start:
        return 0.0
    if t >= end:
        return 1.0
    return smoothstep((t - start) / (end - start))


def envelope(t, start, end, attack, release, length):
    local = t - start
    if local < 0 or local > length:
        return 0.0
    in_level = smoothstep(local / attack) if attack else 1.0
    out_level = smoothstep((length - local) / release) if release else 1.0
    return in_level * out_level


def piano_tone(t, frequency, brightness):
    phase = 2.0 * math.pi * frequency * t
    value = math.sin(phase)
    value += 0.20 * math.sin(phase * 2.0)
    value += brightness * 0.07 * math.sin(phase * 3.0)
    value += brightness * 0.025 * math.sin(phase * 5.0)
    attack = 1.0 - math.exp(-t / 0.085)
    return value * attack * math.exp(-t / 1.15)


def string_tone(t, frequency, vibrato):
    wobble = 0.004 * math.sin(2.0 * math.pi * vibrato * t)
    phase = 2.0 * math.pi * frequency * (1.0 + wobble) * t
    attack = 1.0 - math.exp(-t / 0.34)
    return (math.sin(phase) + 0.12 * math.sin(phase * 2.0)) * attack


def air_tone(t, frequency, brightness):
    phase = 2.0 * math.pi * frequency * t
    attack = 1.0 - math.exp(-t / 0.18)
    value = math.sin(phase) + brightness * 0.18 * math.sin(phase * 2.0)
    return value * attack * math.exp(-t / 1.7)


def chord_weight(t, chord_start, chord_end, total):
    fade_in = crossfade(t, chord_start, chord_start + 0.36)
    fade_out = 1.0 - crossfade(t, chord_end - 0.42, chord_end)
    body = smoothstep((t - chord_start) / total)
    return fade_in * fade_out * (0.72 + 0.28 * body)


def render_felt(chords, melody, length=3.2):
    samples = []
    for i in range(int(RATE * length)):
        t = i / RATE
        value = 0.0
        for start, end, notes in chords:
            weight = chord_weight(t, start, end, end - start)
            for midi, amp in notes:
                value += weight * amp * piano_tone(max(0.0, t - start), hz(midi), 0.55)
        for start, midi, amp in melody:
            local = t - start
            if local >= 0:
                value += amp * piano_tone(local, hz(midi), 0.35)
        samples.append(value)
    return samples


def render_strings(chords, melody, length=3.2):
    samples = []
    for i in range(int(RATE * length)):
        t = i / RATE
        value = 0.0
        for start, end, notes in chords:
            weight = chord_weight(t, start, end, end - start)
            for midi, amp in notes:
                local = max(0.0, t - start)
                value += weight * amp * string_tone(local, hz(midi), 4.8)
        for start, midi, amp in melody:
            local = t - start
            if local >= 0:
                value += amp * air_tone(local, hz(midi), 0.24)
        samples.append(value)
    return samples


def render_air(chords, melody, length=3.2):
    samples = []
    for i in range(int(RATE * length)):
        t = i / RATE
        value = 0.0
        for start, end, notes in chords:
            weight = chord_weight(t, start, end, end - start)
            for midi, amp in notes:
                local = max(0.0, t - start)
                value += weight * amp * air_tone(local, hz(midi), 0.42)
        for start, midi, amp in melody:
            local = t - start
            if local >= 0:
                value += amp * air_tone(local, hz(midi), 0.50)
        samples.append(value)
    return samples


def write_wav(path, samples, stereo_spread):
    peak = max(max(abs(value) for value in samples), 1e-9)
    gain = 0.62 / peak
    with wave.open(path, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        frames = bytearray()
        for i, value in enumerate(samples):
            stereo_lfo = math.sin(2.0 * math.pi * 0.18 * i / RATE)
            left = value * gain * (1.0 - stereo_spread * (0.5 + 0.5 * stereo_lfo))
            right = value * gain * (1.0 + stereo_spread * (0.5 + 0.5 * stereo_lfo))
            frames += int(max(-1.0, min(1.0, left)) * 32767).to_bytes(2, "little", signed=True)
            frames += int(max(-1.0, min(1.0, right)) * 32767).to_bytes(2, "little", signed=True)
        output.writeframes(frames)


COMMON_LENGTH = 3.2

VARIANTS = {
    "01_felt_harmony": {
        "engine": render_felt,
        "chords": [(0.00, 1.12, [(60, 0.16), (64, 0.12), (67, 0.10)]), (0.82, 2.20, [(57, 0.14), (60, 0.11), (64, 0.09)]), (1.86, 3.00, [(53, 0.12), (57, 0.09), (60, 0.08)])],
        "melody": [(0.22, 72, 0.08), (0.70, 76, 0.06), (1.38, 74, 0.055), (2.24, 79, 0.045)],
        "spread": 0.08,
    },
    "02_silk_strings": {
        "engine": render_strings,
        "chords": [(0.00, 1.28, [(62, 0.14), (65, 0.10), (69, 0.08)]), (0.96, 2.32, [(58, 0.12), (62, 0.09), (65, 0.08)]), (2.00, 3.04, [(60, 0.11), (64, 0.08), (67, 0.06)])],
        "melody": [(0.34, 74, 0.06), (0.92, 77, 0.05), (1.64, 76, 0.045), (2.42, 81, 0.035)],
        "spread": 0.18,
    },
    "03_air_synth": {
        "engine": render_air,
        "chords": [(0.00, 1.20, [(57, 0.10), (61, 0.075), (64, 0.055)]), (0.88, 2.30, [(53, 0.09), (57, 0.07), (60, 0.05)]), (2.02, 3.08, [(60, 0.085), (64, 0.06), (67, 0.045)])],
        "melody": [(0.18, 69, 0.055), (0.64, 73, 0.045), (1.28, 76, 0.038), (2.16, 73, 0.032)],
        "spread": 0.28,
    },
    "04_soft_chimes": {
        "engine": render_air,
        "chords": [(0.00, 1.18, [(63, 0.11), (67, 0.08), (70, 0.06)]), (0.84, 2.18, [(58, 0.10), (63, 0.075), (67, 0.05)]), (1.88, 3.04, [(63, 0.095), (67, 0.065), (70, 0.045)])],
        "melody": [(0.29, 75, 0.045), (0.86, 79, 0.038), (1.55, 77, 0.032), (2.36, 82, 0.028)],
        "spread": 0.22,
    },
}


os.makedirs(OUT, exist_ok=True)
for name, config in VARIANTS.items():
    samples = config["engine"](config["chords"], config["melody"], COMMON_LENGTH)
    write_wav(os.path.join(OUT, f"info_music_{name}.wav"), samples, config["spread"])
