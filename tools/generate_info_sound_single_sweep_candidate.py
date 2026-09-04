import math
import os
import wave


RATE = 44100
LENGTH = 1.72
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_single_sweep_candidate")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def sweep_envelope(local, duration):
    if local < 0.0 or local > duration:
        return 0.0
    attack = 0.004
    release = 0.46
    if local < attack:
        return smoothstep(local / attack)
    return math.exp(-local / 0.58) * smoothstep((duration - local) / release)


def tuned_string(local, frequency, resonance):
    phase = 2.0 * math.pi * frequency * local
    # A compact, tuned spectrum: the sweep is one gesture, while the pitches
    # remain distinct enough to create the airy musical color.
    value = 0.86 * math.sin(phase)
    value += 0.20 * math.sin(phase * 2.0)
    value += 0.065 * math.sin(phase * 3.0)
    value += resonance * 0.028 * math.sin(phase * 4.0)
    return value


def add_swept_string(samples, start, midi, amplitude, duration, pan, resonance):
    first = int(start * RATE)
    last = min(len(samples), int((start + duration) * RATE))
    frequency = hz(midi)
    for index in range(first, last):
        local = index / RATE - start
        value = amplitude * sweep_envelope(local, duration) * tuned_string(local, frequency, resonance)
        old_left, old_right = samples[index]
        samples[index] = (
            old_left + value * (1.0 - pan * 0.12),
            old_right + value * (1.0 + pan * 0.12),
        )


samples = [(0.0, 0.0) for _ in range(int(RATE * LENGTH))]

# One single low-to-high sweep. The 4 ms spacing makes the strings read as one
# brush across the chord, not as a sequence of separate notes.
strings = [
    (50, 0.000, 0.12, -0.62),
    (57, 0.004, 0.15, -0.42),
    (62, 0.008, 0.16, -0.20),
    (66, 0.012, 0.15, 0.08),
    (69, 0.016, 0.13, 0.34),
    (74, 0.020, 0.10, 0.60),
]
for midi, offset, amplitude, pan in strings:
    add_swept_string(samples, 0.055 + offset, midi, amplitude, 1.38, pan, 1.0)

# Airy resonance only: no second melody, no second attack.
for midi, amplitude in ((69, 0.030), (74, 0.024), (78, 0.014)):
    add_swept_string(samples, 0.070, midi, amplitude, 1.18, 0.0, 1.8)

# Short room-like reflections keep the ending clear and light.
for delay, gain in ((0.085, 0.045), (0.17, 0.018)):
    original = tuple(samples)
    for index, (left, right) in enumerate(original):
        target = index + int(delay * RATE)
        if target >= len(samples):
            break
        old_left, old_right = samples[target]
        samples[target] = (old_left + left * gain, old_right + right * gain)

peak = max(max(abs(left), abs(right)) for left, right in samples)
gain = 0.60 / max(peak, 1e-9)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_single_sweep.wav")
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
