import math
import os
import wave


RATE = 44100
LENGTH = 1.2
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_synthetic")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def body_envelope(t):
    if t < 0.0 or t > 0.48:
        return 0.0
    attack = 0.07
    if t < attack:
        return smoothstep(t / attack)
    return math.exp(-(t - attack) / 0.20) * smoothstep((0.48 - t) / 0.18)


def air_envelope(t):
    if t < 0.0 or t > 0.25:
        return 0.0
    attack = 0.025
    if t < attack:
        return smoothstep(t / attack)
    return math.exp(-(t - attack) / 0.075) * smoothstep((0.25 - t) / 0.08)


def render():
    samples = []
    phase_e = 0.0
    phase_b = 0.0
    for index in range(int(RATE * LENGTH)):
        t = index / RATE - 0.056
        body = body_envelope(t)
        air = air_envelope(t)
        if t < 0.0:
            samples.append((0.0, 0.0))
            continue

        # The two measured main notes are one coherent interval, not a melody.
        fm = 0.9 * math.sin(2.0 * math.pi * 5.2 * t) * math.exp(-t / 0.16)
        phase_e += 2.0 * math.pi * hz(64) * (1.0 + 0.0012 * fm) / RATE
        phase_b += 2.0 * math.pi * hz(71) * (1.0 + 0.0012 * fm) / RATE
        e = math.sin(phase_e) + 0.12 * math.sin(phase_e * 2.0)
        b = math.sin(phase_b) + 0.10 * math.sin(phase_b * 2.0)

        # Short upper partials reproduce the reference's clear, airy onset.
        upper = (
            0.18 * math.sin(2.0 * math.pi * hz(69) * t)
            + 0.15 * math.sin(2.0 * math.pi * hz(76) * t)
            + 0.10 * math.sin(2.0 * math.pi * hz(80) * t)
            + 0.045 * math.sin(2.0 * math.pi * hz(87) * t)
        )
        value = 0.32 * body * (e + b) + air * upper
        width = 0.025 * math.sin(2.0 * math.pi * 0.7 * t)
        samples.append((value * (1.0 - width), value * (1.0 + width)))
    peak = max(max(abs(left), abs(right)) for left, right in samples)
    gain = 0.62 / max(peak, 1e-9)
    return [(left * gain, right * gain) for left, right in samples]


os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_airy_e4_b4_synth.wav")
with wave.open(path, "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(RATE)
    frames = bytearray()
    for left, right in render():
        frames += int(max(-1.0, min(1.0, left)) * 32767).to_bytes(2, "little", signed=True)
        frames += int(max(-1.0, min(1.0, right)) * 32767).to_bytes(2, "little", signed=True)
    output.writeframes(frames)
print(path)
