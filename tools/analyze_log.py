import json, glob, os

# Find latest log
files = glob.glob(os.path.expanduser('~/Desktop/nied_replay_*.json'))
latest = max(files, key=os.path.getmtime)
print(f'File: {os.path.basename(latest)} ({os.path.getsize(latest)}b)')

d = json.load(open(latest, 'r', encoding='utf-8'))
print(f'Session: {d.get("session_start","?")} -> {d.get("written_at","?")[:19]}')
print(f'Frames: {d["frame_count"]}, Det: {d["detection_count"]}, Epi: {d["epicenter_count"]}')
print()

for f in d['frames']:
    t = f['type']
    if t == 'detection':
        print(f'DETECT: stage={f["stage"]} W={f["weak"]} D={f["detected"]} S={f["strong"]} maxShindo={f["max_shindo"]}')
        for s in f.get('stations', [])[:8]:
            print(f'  {s["code"]} {s["pref"]} L={s["level"]} shindo={s["shindo"]} state={s["state"]} reason={s["reason"]}')
    elif t == 'epicenter':
        print(f'EPICENTER: lat={f["lat"]} lng={f["lng"]} conf={f["confidence"]} active={f["active_count"]}')
