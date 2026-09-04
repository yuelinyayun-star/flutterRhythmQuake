import math
import os
import wave


RATE = 44100
LENGTH = 1.75
OUT = os.path.join(os.path.dirname(__file__), "..", "tmp", "info_sound_slide_candidate")


def hz(midi):
    return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def slide_envelope(local, duration):
    if local < 0.0 or local > duration:
        return 0.0
    attack = 0.014
    if local < attack:
        return smoothstep(local / attack)
    return math.exp(-local / 0.46) * smoothstep((duration - local) / 0.24)


def add_slide(samples, start, from_midi, to_midi, duration, amplitude, pan):
    first = int(start * RATE)
    last = min(len(samples), int((start + duration) * RATE))
    start_hz = hz(from_midi)
    end_hz = hz(to_midi)
    phase = 0.0
    previous_frequency = start_hz
    for index in range(first, last):
        local = index / RATE - start
        progress = smoothstep(local / duration)
        frequency = start_hz + (end_hz - start_hz) * progress
        phase += 2.0 * math.pi * (previous_frequency + frequency) * 0.5 / RATE
        previous_frequency = frequency
        vibrato = 1.0 + 0.0025 * math.sin(2.0 * math.pi * 5.2 * local)
        body = math.sin(phase * vibrato)
        body += 0.16 * math.sin(phase * 2.0)
        body += 0.045 * math.sin(phase * 3.0)
        # A short bright edge makes the slide readable as a cue, not as a pad.
        edge = 0.035 * math.sin(phase * 5.0) * math.exp(-local / 0.075)
        value = amplitude * slide_envelope(local, duration) * (body + edge)
        old_left, old_right = samples[index]
        samples[index] = (
            old_left + value * (1.0 - pan * 0.18),
            old_right + value * (1.0 + pan * 0.18),
        )


samples = [(0.0, 0.0) for _ in range(int(RATE * LENGTH))]

# Two melodic gestures only: the first opens gently, the second answers by
# sliding down. There are no repeated plucks and no sustained chord bed.
add_slide(samples, 0.045, 66, 73, 0.34, 0.24, -0.12)
add_slide(samples, 0.43, 73, 69, 0.28, 0.18, 0.08)
add_slide(samples, 0.76, 71, 76, 0.30, 0.19, 0.10)
add_slide(samples, 1.10, 76, 68, 0.38, 0.155, -0.08)

# A quiet, short tail preserves the cue's musical finish without adding a pad.
for delay, gain in ((0.10, 0.055), (0.19, 0.022)):
    for index, (left, right) in enumerate(tuple(samples)):
        target = index + int(delay * RATE)
        if target >= len(samples):
            break
        old_left, old_right = samples[target]
        samples[target] = (old_left + left * gain, old_right + right * gain)

peak = max(max(abs(left), abs(right)) for left, right in samples)
gain = 0.60 / max(peak, 1e-9)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "info_update_slide_melody.wav")
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
