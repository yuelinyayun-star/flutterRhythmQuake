import json
import math
import os
import re
import wave

import mido
import numpy as np
from scipy.signal import stft


ROOT = os.path.join(os.path.dirname(__file__), "..")
SOURCE = r"C:\Users\Rhythm\AppData\Local\Programs\WQuake\web\audio\VXSE52.ogg"
MIDI = r"D:\Users\Rhythm\Downloads\basic_pitch_transcription (2).mid"
LIBRARY = os.path.join(ROOT, "tmp", "sound_libraries", "tonejs_instruments", "common")
OUT_DIR = os.path.join(ROOT, "tmp", "vxse52_instrument_comparison")
INSTRUMENTS = [
    "guitar-acoustic",
    "guitar-nylon",
    "harp",
    "piano",
    "xylophone",
    "cello",
    "violin",
    "flute",
]
NOTE_NAMES = {"C": 0, "Cs": 1, "D": 2, "Ds": 3, "E": 4, "F": 5, "Fs": 6, "G": 7, "Gs": 8, "A": 9, "As": 10, "B": 11}


def read_wav(path):
    with wave.open(path, "rb") as source:
        rate = source.getframerate()
        channels = source.getnchannels()
        if source.getsampwidth() != 2:
            raise ValueError(f"expected 16-bit PCM: {path}")
        values = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2").astype(np.float64)
    values = values.reshape(-1, channels) / 32768.0
    return rate, values.mean(axis=1)


def resample(values, ratio):
    output_length = max(1, round(len(values) / ratio))
    positions = np.arange(output_length, dtype=np.float64) * ratio
    return np.interp(positions, np.arange(len(values), dtype=np.float64), values)


def resample_rate(values, source_rate, target_rate):
    return resample(values, source_rate / target_rate)


def parse_sample_midi(filename):
    match = re.fullmatch(r"([A-G](?:s)?)(-?\d+)\.wav", filename)
    if not match:
        raise ValueError(filename)
    return (int(match.group(2)) + 1) * 12 + NOTE_NAMES[match.group(1)]


def parse_midi_notes():
    midi = mido.MidiFile(MIDI)
    tempo = 500000
    time_s = 0.0
    active = {}
    notes = []
    for message in mido.merge_tracks(midi.tracks):
        time_s += mido.tick2second(message.time, midi.ticks_per_beat, tempo)
        if message.type == "set_tempo":
            tempo = message.tempo
        elif message.type == "note_on" and message.velocity > 0:
            active.setdefault((message.channel, message.note), []).append((time_s, message.velocity))
        elif message.type in ("note_off", "note_on"):
            key = (message.channel, message.note)
            if active.get(key):
                start, velocity = active[key].pop(0)
                notes.append({"midi": message.note, "start": start, "end": time_s, "velocity": velocity})

    merged = []
    for midi_note in sorted({note["midi"] for note in notes}):
        current = None
        for note in sorted((note for note in notes if note["midi"] == midi_note), key=lambda item: item["start"]):
            if current is not None and note["start"] - current["end"] <= 0.015:
                current["end"] = max(current["end"], note["end"])
                current["velocity"] = max(current["velocity"], note["velocity"])
            else:
                current = dict(note)
                merged.append(current)
    return sorted(merged, key=lambda item: (item["start"], item["midi"]))


def trim_leading_silence(values):
    peak = max(float(np.max(np.abs(values))), 1e-12)
    indices = np.flatnonzero(np.abs(values) >= peak * 0.01)
    return values[indices[0] :] if len(indices) else values


def render_instrument(instrument, notes, rate, length):
    folder = os.path.join(LIBRARY, instrument)
    sample_files = [name for name in os.listdir(folder) if name.lower().endswith(".wav")]
    samples = [(name, parse_sample_midi(name)) for name in sample_files]
    cache = {}
    mix = np.zeros(round(length * rate), dtype=np.float64)
    for note in notes:
        filename, source_midi = min(samples, key=lambda item: abs(item[1] - note["midi"]))
        key = (filename, note["midi"])
        if key not in cache:
            source_rate, values = read_wav(os.path.join(folder, filename))
            values = resample_rate(trim_leading_silence(values), source_rate, rate)
            cache[key] = resample(values, 2.0 ** ((note["midi"] - source_midi) / 12.0))
        voice = cache[key]
        start = round(note["start"] * rate)
        duration = max(1, round((note["end"] - note["start"]) * rate))
        release = min(round(0.18 * rate), duration)
        voice = voice[:duration].copy()
        if len(voice) < duration:
            voice = np.pad(voice, (0, duration - len(voice)))
        if release > 0:
            voice[-release:] *= np.linspace(1.0, 0.0, release) ** 2
        gain = (note["velocity"] / 127.0) ** 1.35
        available = min(len(voice), len(mix) - start)
        if available > 0:
            mix[start : start + available] += voice[:available] * gain
    return mix


def frame_features(values, rate):
    frequencies, _, spectrum = stft(values, fs=rate, window="hann", nperseg=2048, noverlap=1536, nfft=4096)
    magnitude = np.abs(spectrum)
    selected = (frequencies >= 70.0) & (frequencies <= 6000.0)
    magnitude = magnitude[selected]
    log_magnitude = np.log1p(magnitude * 120.0)
    shape = log_magnitude / (np.linalg.norm(log_magnitude, axis=0, keepdims=True) + 1e-12)
    energy = np.sqrt(np.mean(np.abs(spectrum) ** 2, axis=0))
    energy = energy / max(float(np.max(energy)), 1e-12)
    return shape, energy


def compare(source, candidate, rate):
    source_shape, source_energy = frame_features(source, rate)
    candidate_shape, candidate_energy = frame_features(candidate, rate)
    frames = min(source_shape.shape[1], candidate_shape.shape[1])
    spectral_cosine = np.mean(np.sum(source_shape[:, :frames] * candidate_shape[:, :frames], axis=0))
    envelope_rmse = float(np.sqrt(np.mean((source_energy[:frames] - candidate_energy[:frames]) ** 2)))
    score = float(spectral_cosine - 0.45 * envelope_rmse)
    return {
        "score": score,
        "spectral_cosine": float(spectral_cosine),
        "envelope_rmse": envelope_rmse,
    }


def write_wav(path, rate, values):
    peak = max(float(np.max(np.abs(values))), 1e-12)
    values = np.clip(values * (0.76 / peak), -1.0, 1.0)
    with wave.open(path, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes((values * 32767.0).astype("<i2").tobytes())


def note_name(midi_note):
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return f"{names[midi_note % 12]}{midi_note // 12 - 1}"


if __name__ == "__main__":
    rate, source = read_wav(SOURCE)
    length = len(source) / rate
    notes = parse_midi_notes()
    os.makedirs(OUT_DIR, exist_ok=True)
    results = []
    for instrument in INSTRUMENTS:
        candidate = render_instrument(instrument, notes, rate, length)
        metrics = compare(source, candidate, rate)
        path = os.path.join(OUT_DIR, f"{instrument}.wav")
        write_wav(path, rate, candidate)
        results.append({"instrument": instrument, "path": path, **metrics})
    results.sort(key=lambda item: item["score"], reverse=True)
    report = {
        "source": SOURCE,
        "midi": MIDI,
        "notes_after_adjacent_merge": [
            {
                "note": note_name(note["midi"]),
                "start_s": round(note["start"], 4),
                "end_s": round(note["end"], 4),
                "velocity": note["velocity"],
            }
            for note in notes
        ],
        "ranking": results,
    }
    report_path = os.path.join(OUT_DIR, "comparison.json")
    with open(report_path, "w", encoding="utf-8") as output:
        json.dump(report, output, ensure_ascii=False, indent=2)
    print(json.dumps(report, ensure_ascii=False, indent=2))
