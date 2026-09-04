import math
import os
import wave


RATE = 44100
LENGTH = 2.05
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_guitar_candidate")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def string_envelope(local, duration):
    if local < 0.0 or local > duration:
        return 0.0
    attack = 0.006
    if local < attack:
        return smoothstep(local / attack)
    # A plucked string decays quickly at the edge and leaves a softer body tone.
    return math.exp(-local / 0.52) * (0.88 + 0.12 * math.exp(-local / 1.3))


def guitar_string(local, frequency):
    phase = 2.0 * math.pi * frequency * local
    # Harmonics are deliberately restrained to keep the attack wooden, not metallic.
    value = (
        0.82 * math.sin(phase)
        + 0.27 * math.sin(phase * 2.0)
        + 0.11 * math.sin(phase * 3.0)
        + 0.045 * math.sin(phase * 4.0)
    )
    body = 0.05 * math.sin(2.0 * math.pi * 118.0 * local) * math.exp(-local / 0.42)
    return value + body


def add_string(samples, start, midi, amplitude, duration, pan):
    first = int(start * RATE)
    last = min(len(samples), int((start + duration) * RATE))
    frequency = hz(midi)
    for index in range(first, last):
        local = index / RATE - start
        value = amplitude * string_envelope(local, duration) * guitar_string(local, frequency)
        old_left, old_right = samples[index]
        samples[index] = (
            old_left + value * (1.0 - pan * 0.28),
            old_right + value * (1.0 + pan * 0.28),
        )


def strum(samples, start, strings, direction, amplitude):
    ordered = strings if direction == "low_to_high" else list(reversed(strings))
    for index, (midi, duration, pan) in enumerate(ordered):
        # The small gaps are the sweep across the strings, not a fixed rhythmic beat.
        add_string(samples, start + index * 0.019, midi, amplitude, duration, pan)


samples = [(0.0, 0.0) for _ in range(int(RATE * LENGTH))]

# Dmaj7(add9): one low-to-high sweep gives the cue a clear instrument identity.
strum(
    samples,
    0.045,
    [
        (50, 1.45, -0.75),
        (57, 1.28, -0.45),
        (61, 1.14, -0.18),
        (66, 1.04, 0.20),
        (73, 0.92, 0.62),
    ],
    "low_to_high",
    0.15,
)

# A shorter upper-string answer falls back toward the tonic instead of rising like an alarm.
strum(
    samples,
    0.78,
    [
        (66, 0.86, -0.30),
        (69, 0.78, 0.00),
        (73, 0.70, 0.34),
    ],
    "high_to_low",
    0.105,
)

# Very quiet body resonance keeps the ending musical without becoming a sustained pad.
for delay, gain in ((0.11, 0.075), (0.21, 0.032)):
    for index, (left, right) in enumerate(tuple(samples)):
        target = index + int(delay * RATE)
        if target >= len(samples):
            break
        old_left, old_right = samples[target]
        samples[target] = (old_left + left * gain, old_right + right * gain)

peak = max(max(abs(left), abs(right)) for left, right in samples)
gain = 0.62 / max(peak, 1e-9)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_guitar_sweep.wav")
with wave.open(path, "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(RATE)
    frames = bytearray()
    for left, right in samples:
        frames += int(max(-1.0, min(1.0, left * gain)) * 32767).to_bytes(2, "little", signed=True)
        frames += int(max(-1.0, min(1.0, right * gain)) * 32767).to_bytes(2, "little", signed=True)
    output.writeframes(frames)
print(path)
