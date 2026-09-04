import math
import os
import wave


RATE = 44100
LENGTH = 3.6
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_variants_v6")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def clamp(value):
    return max(-1.0, min(1.0, value))


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def span_envelope(t, start, end, attack=0.28, release=0.55):
    if t < start or t > end:
        return 0.0
    fade_in = smoothstep((t - start) / attack) if attack else 1.0
    fade_out = smoothstep((end - t) / release) if release else 1.0
    return fade_in * fade_out


def note_envelope(local, attack, decay, release, sustain, duration):
    if local < 0.0 or local > duration:
        return 0.0
    if local < attack:
        return smoothstep(local / attack)
    if local < attack + decay:
        progress = (local - attack) / decay
        return 1.0 - (1.0 - sustain) * smoothstep(progress)
    return sustain * smoothstep((duration - local) / release)


def warm_string(local, frequency, detune=0.0):
    phase = 2.0 * math.pi * frequency * local
    drift = 0.003 * math.sin(2.0 * math.pi * 0.23 * local)
    return (
        0.72 * math.sin(phase * (1.0 + drift + detune))
        + 0.18 * math.sin(phase * 2.0)
        + 0.07 * math.sin(phase * 3.0)
    )


def felt_piano(local, frequency):
    phase = 2.0 * math.pi * frequency * local
    body = math.sin(phase) + 0.16 * math.sin(phase * 2.0)
    soft_edge = 0.035 * math.sin(phase * 4.0)
    return (body + soft_edge) * math.exp(-local / 1.05)


def glass_note(local, frequency):
    phase = 2.0 * math.pi * frequency * local
    shimmer = 0.18 * math.sin(phase * 2.01) + 0.06 * math.sin(phase * 3.97)
    return (0.76 * math.sin(phase) + shimmer) * math.exp(-local / 1.55)


def render(chords, notes, voice, width=0.0):
    samples = []
    for index in range(int(RATE * LENGTH)):
        t = index / RATE
        value = 0.0
        for start, end, chord_notes in chords:
            envelope = span_envelope(t, start, end)
            for midi, amplitude in chord_notes:
                local = max(0.0, t - start)
                value += envelope * amplitude * voice(local, hz(midi))
        for start, midi, amplitude, duration in notes:
            local = t - start
            envelope = note_envelope(local, 0.13, 0.10, 0.34, 0.30, duration)
            if envelope:
                value += amplitude * envelope * voice(local, hz(midi))
        samples.append(value)

    peak = max(max(abs(sample) for sample in samples), 1e-9)
    gain = 0.54 / peak
    frames = bytearray()
    for index, sample in enumerate(samples):
        motion = math.sin(2.0 * math.pi * 0.11 * index / RATE)
        left = sample * gain * (1.0 - width * (0.5 + 0.5 * motion))
        right = sample * gain * (1.0 + width * (0.5 + 0.5 * motion))
        frames += int(clamp(left) * 32767).to_bytes(2, "little", signed=True)
        frames += int(clamp(right) * 32767).to_bytes(2, "little", signed=True)
    return frames


VARIANTS = {
    "01_falling_piano_phrase": {
        "voice": felt_piano,
        "chords": [
            (0.00, 1.55, [(69, 0.10), (73, 0.075), (76, 0.065), (80, 0.035)]),
            (1.05, 2.72, [(67, 0.085), (71, 0.065), (74, 0.055), (78, 0.030)]),
            (2.32, 3.52, [(64, 0.075), (69, 0.060), (73, 0.050), (76, 0.028)]),
        ],
        "notes": [
            (0.18, 80, 0.055, 1.15),
            (0.67, 76, 0.045, 1.18),
            (1.47, 74, 0.042, 1.02),
            (2.28, 71, 0.035, 1.05),
            (2.86, 69, 0.026, 0.68),
        ],
        "width": 0.06,
    },
    "02_suspended_strings": {
        "voice": warm_string,
        "chords": [
            (0.00, 1.48, [(62, 0.085), (69, 0.075), (76, 0.045), (81, 0.025)]),
            (0.92, 2.52, [(60, 0.080), (67, 0.068), (74, 0.048), (79, 0.026)]),
            (2.00, 3.52, [(59, 0.072), (64, 0.060), (71, 0.047), (76, 0.026)]),
        ],
        "notes": [
            (0.36, 74, 0.030, 1.40),
            (1.14, 72, 0.026, 1.34),
            (2.17, 69, 0.024, 1.15),
        ],
        "width": 0.16,
    },
    "03_chime_answer": {
        "voice": glass_note,
        "chords": [
            (0.00, 1.32, [(65, 0.060), (69, 0.050), (72, 0.042), (77, 0.022)]),
            (1.18, 2.48, [(64, 0.055), (67, 0.045), (71, 0.038), (76, 0.020)]),
            (2.22, 3.48, [(60, 0.050), (65, 0.042), (69, 0.034), (74, 0.018)]),
        ],
        "notes": [
            (0.20, 77, 0.040, 1.10),
            (0.88, 72, 0.032, 1.18),
            (1.55, 74, 0.030, 1.10),
            (2.42, 69, 0.026, 0.90),
            (2.95, 65, 0.020, 0.64),
        ],
        "width": 0.22,
    },
}


os.makedirs(OUT, exist_ok=True)
for name, config in VARIANTS.items():
    path = os.path.join(OUT, f"info_music_{name}.wav")
    with wave.open(path, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(render(config["chords"], config["notes"], config["voice"], config["width"]))
    print(path)
