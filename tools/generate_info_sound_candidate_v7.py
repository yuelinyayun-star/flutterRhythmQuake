import math
import os
import wave


RATE = 44100
LENGTH = 1.82
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_candidate_v7")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def envelope(local, duration):
    if local < 0.0 or local > duration:
        return 0.0
    attack = 0.018
    release = 0.34
    if local < attack:
        return smoothstep(local / attack)
    return smoothstep((duration - local) / release) * math.exp(-local / 0.72)


def soft_mallet(local, frequency):
    phase = 2.0 * math.pi * frequency * local
    # A restrained second partial keeps the note clear without a piercing edge.
    return 0.82 * math.sin(phase) + 0.15 * math.sin(phase * 2.0) + 0.035 * math.sin(phase * 3.0)


def add_note(samples, start, midi, amplitude, duration, pan):
    frequency = hz(midi)
    first = int(start * RATE)
    last = min(len(samples), int((start + duration) * RATE))
    for index in range(first, last):
        local = index / RATE - start
        value = amplitude * envelope(local, duration) * soft_mallet(local, frequency)
        # Keep the stereo movement subtle; the sound should remain a single cue.
        left = value * (1.0 - pan * 0.35)
        right = value * (1.0 + pan * 0.35)
        old_left, old_right = samples[index]
        samples[index] = (old_left + left, old_right + right)


samples = [(0.0, 0.0) for _ in range(int(RATE * LENGTH))]

# One compact, non-repeating gesture: a soft consonant opening, a lift, then a
# descending answer that settles instead of ending on a high note.
add_note(samples, 0.00, 67, 0.25, 0.82, -0.08)
add_note(samples, 0.015, 76, 0.13, 0.68, 0.08)
add_note(samples, 0.34, 72, 0.18, 0.72, 0.03)
add_note(samples, 0.73, 69, 0.15, 0.70, -0.05)
add_note(samples, 1.08, 64, 0.105, 0.62, 0.02)

# A very quiet delayed resonance supplies the short tail found in a musical cue.
for delay, gain in ((0.095, 0.075), (0.18, 0.035)):
    for index, (left, right) in enumerate(tuple(samples)):
        target = index + int(delay * RATE)
        if target >= len(samples):
            break
        samples[target] = (
            samples[target][0] + left * gain,
            samples[target][1] + right * gain,
        )

peak = max(max(abs(left), abs(right)) for left, right in samples)
gain = 0.58 / max(peak, 1e-9)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_candidate.wav")
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
