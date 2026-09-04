import math
import os
import struct
import wave

import numpy as np
from scipy.signal import butter, sosfilt


ROOT = os.path.join(os.path.dirname(__file__), "..")
LIBRARY = os.path.join(ROOT, "tmp", "sound_libraries", "tonejs_instruments", "common")
OUT_DIR = os.path.join(ROOT, "tmp", "reference_sound_instrument_rebuilds")


def read_wav(path):
    with wave.open(path, "rb") as source:
        rate = source.getframerate()
        channels = source.getnchannels()
        width = source.getsampwidth()
        if width != 2:
            raise ValueError(f"expected 16-bit PCM: {path}")
        values = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64)
    values = values.reshape(-1, channels) / 32768.0
    return rate, values


def resample_rate(values, source_rate, target_rate):
    if source_rate == target_rate:
        return values
    output_length = round(len(values) * target_rate / source_rate)
    positions = np.arange(output_length, dtype=np.float64) * source_rate / target_rate
    source_positions = np.arange(len(values), dtype=np.float64)
    channels = [np.interp(positions, source_positions, values[:, channel]) for channel in range(values.shape[1])]
    return np.stack(channels, axis=1)


def pitch_shift(values, semitones):
    ratio = 2.0 ** (semitones / 12.0)
    output_length = max(1, int(len(values) / ratio))
    positions = np.arange(output_length, dtype=np.float64) * ratio
    source_positions = np.arange(len(values), dtype=np.float64)
    channels = [np.interp(positions, source_positions, values[:, channel]) for channel in range(values.shape[1])]
    return np.stack(channels, axis=1)


def mono(values):
    return values.mean(axis=1, keepdims=True)


def add_voice(mix, voice, start_s, gain, rate, max_duration=None, attack_s=0.0, release_s=0.15):
    start = round(start_s * rate)
    if max_duration is not None:
        voice = voice[: round(max_duration * rate)]
    available = min(len(voice), len(mix) - start)
    if available <= 0:
        return
    voice = voice[:available].copy()
    envelope = np.ones(available, dtype=np.float64)
    attack = min(round(attack_s * rate), available)
    if attack > 0:
        x = np.linspace(0.0, 1.0, attack, endpoint=False)
        envelope[:attack] *= x * x * (3.0 - 2.0 * x)
    release = min(round(release_s * rate), available)
    if release > 0:
        x = np.linspace(1.0, 0.0, release)
        envelope[-release:] *= x * x * (3.0 - 2.0 * x)
    mix[start : start + available] += voice * envelope[:, None] * gain


def add_reflections(values, rate, reflections):
    result = values.copy()
    for delay_s, gain in reflections:
        delay = round(delay_s * rate)
        if delay < len(values):
            result[delay:] += values[:-delay] * gain
    return result


def normalize(values, peak=0.78):
    current = float(np.max(np.abs(values)))
    return values * (peak / max(current, 1e-9))


def write_wav(path, rate, values):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    values = np.clip(values, -1.0, 1.0)
    with wave.open(path, "wb") as output:
        output.setnchannels(values.shape[1])
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes((values * 32767.0).astype("<i2").tobytes())


def render_srev_update():
    rate = 44100
    length = 1.2
    source_rate, source = read_wav(os.path.join(LIBRARY, "xylophone", "G4.wav"))
    source = resample_rate(source, source_rate, rate)
    if source.shape[1] == 1:
        source = np.repeat(source, 2, axis=1)
    mix = np.zeros((round(rate * length), 2), dtype=np.float64)

    # The reference is one short two-note gesture: E4 and B4 are nearly
    # simultaneous, with a soft 40 ms rise and a compact mallet tail.
    e4 = pitch_shift(source, -3.0)
    b4 = pitch_shift(source, 4.0)
    add_voice(mix, e4, 0.056, 0.72, rate, max_duration=0.38, attack_s=0.038, release_s=0.15)
    add_voice(mix, b4, 0.066, 0.62, rate, max_duration=0.40, attack_s=0.030, release_s=0.17)
    mix = add_reflections(mix, rate, [(0.052, 0.11), (0.094, 0.06)])
    mix = normalize(mix, 0.72)
    path = os.path.join(OUT_DIR, "srev_update_instrument_rebuild.wav")
    write_wav(path, rate, mix)
    return path


def load_string(folder, filename, source_midi, target_midi, rate, source_lowpass_hz=None):
    source_rate, values = read_wav(os.path.join(LIBRARY, folder, filename))
    if source_lowpass_hz is not None:
        filter_sos = butter(4, source_lowpass_hz, btype="lowpass", fs=source_rate, output="sos")
        values = np.stack(
            [sosfilt(filter_sos, values[:, channel]) for channel in range(values.shape[1])],
            axis=1,
        )
    values = mono(resample_rate(values, source_rate, rate))
    return pitch_shift(values, target_midi - source_midi)


def render_vxse52():
    rate = 48000
    length = 2.0422083333333334
    mix = np.zeros((round(rate * length), 1), dtype=np.float64)

    # A downward strum runs from the bass strings to the treble strings. Each
    # string overlaps the following one; the final E string keeps the long tail.
    strings = [
        ("guitar-acoustic", "D3.wav", 50, 50, 0.045, 0.34, 0.82, 230.0),  # D3
        ("guitar-nylon", "G3.wav", 55, 57, 0.155, 0.31, 0.92, None), # A3
        ("guitar-nylon", "E4.wav", 64, 62, 0.285, 0.29, 1.04, None), # D4
        ("guitar-nylon", "Fs4.wav", 66, 66, 0.420, 0.27, 1.12, None), # F#4
        ("guitar-nylon", "A4.wav", 69, 69, 0.575, 0.25, 1.22, None), # A4
        # D5.wav in this library is centered around D#5, not D5. B4.wav
        # gives a verified B4 source that can be moved to the final E5.
        ("guitar-nylon", "B4.wav", 71, 76, 0.760, 0.38, 1.28, 520.0), # E5
    ]
    for folder, filename, source_midi, target_midi, start, gain, duration, source_lowpass_hz in strings:
        voice = load_string(folder, filename, source_midi, target_midi, rate, source_lowpass_hz)
        add_voice(mix, voice, start, gain, rate, max_duration=duration, attack_s=0.006, release_s=0.30)

    # The reference loses high-frequency pick noise quickly but lets the tonal
    # body ring. A gentle low-pass and short room reflections reproduce that
    # behavior without turning the sound into a pad.
    low_pass = butter(2, 5200.0, btype="lowpass", fs=rate, output="sos")
    mix[:, 0] = sosfilt(low_pass, mix[:, 0])
    mix = add_reflections(mix, rate, [(0.058, 0.10), (0.116, 0.065), (0.184, 0.035)])
    mix = normalize(mix, 0.78)
    path = os.path.join(OUT_DIR, "vxse52_string_strum_rebuild.wav")
    write_wav(path, rate, mix)
    return path


if __name__ == "__main__":
    print(render_srev_update())
    print(render_vxse52())
