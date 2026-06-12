"""
Pure Python WIN32 .cnt parser - extracts PGA from Hi-net waveform data
Format: K-WIN32 (giKwin32=1) — 16-byte block header + data
"""
import struct, glob, os, math

BASE = r"D:\Users\Rhythm\Desktop\iyonada_waveform"

# Step 1: Read channel table to get station list + conversion factors
ch_file = glob.glob(BASE + "/*.sjis.ch")[0]
channels = {}
with open(ch_file, 'r', encoding='shift_jis') as f:
    for line in f:
        if line.startswith('#'): continue
        parts = line.split()
        if len(parts) < 15: continue
        try:
            chid = int(parts[0], 16)
            code = parts[3].replace('N.', '')
            comp = parts[4]
            conv = float(parts[12])  # m/s per count
            lat = float(parts[13])
            lng = float(parts[14])
            dist = math.sqrt((lat - 33.531)**2 + (lng - 132.332)**2)
            if dist < 0.3 and comp == 'U':
                channels[chid] = (code, conv, lat, lng, dist*111)
        except (ValueError, IndexError):
            continue

print(f"Target channels near Iyo-nada epicenter: {len(channels)}")
for chid, (code, conv, lat, lng, dist) in sorted(channels.items(), key=lambda x: x[1][4]):
    print(f"  CH{chid:05x} {code} dist={dist:.1f}km conv={conv:.2e}")

# Step 2: Parse .cnt files
cnt_files = sorted(glob.glob(BASE + "/*.cnt"))
target_ids = set(channels.keys())

pga_data = {}  # chid -> list of (timestamp_second, pga_gal)

for cnt_path in cnt_files:
    fname = os.path.basename(cnt_path)
    with open(cnt_path, 'rb') as f:
        data = f.read()
    
    pos = 0
    blocks = 0
    while pos + 16 < len(data):
        # K-WIN32 block format (giKwin32=1):
        # 16-byte prefix: [4][4][4][4=blocksize]
        # Block data: [4=total_size][16=prefix_copy][channel_data]
        
        prefix = data[pos:pos+16]
        block_size_raw = struct.unpack_from('<I', prefix, 12)[0]
        block_size = ((block_size_raw & 0xFF000000) >> 24) | \
                     ((block_size_raw & 0x00FF0000) >> 8) | \
                     ((block_size_raw & 0x0000FF00) << 8) | \
                     ((block_size_raw & 0x000000FF) << 24)  # swap endian
        
        if block_size <= 0 or block_size > 1000000:
            # Wrong format or too large - try scanning
            pos += 1
            continue
        
        block_end = pos + 16 + block_size
        if block_end > len(data):
            pos += 1
            continue
        
        block_data = data[pos+16:block_end]
        if len(block_data) < 20:
            pos += 1
            continue
        
        # Read total_size from block data
        total_size = struct.unpack_from('<I', block_data, 0)[0]
        # The 16-byte prefix copy is at offset 4
        prefix_copy = block_data[4:20]
        
        # Channel data starts at offset 20
        ch_data = block_data[20:]
        
        # Channel data contains per-second channel blocks
        # Each second: [40-byte header][samples*2 bytes]
        ch_pos = 0
        while ch_pos + 44 <= len(ch_data):
            chid = struct.unpack_from('<I', ch_data, ch_pos)[0]
            # Timestamp in BCD format at offset 4-8
            ts_bytes = ch_data[ch_pos+4:ch_pos+8]
            
            # nsize at offset 12
            nsize = struct.unpack_from('<I', ch_data, ch_pos + 12)[0]
            if nsize == 0 or nsize > 100000:
                ch_pos += 1
                continue
            
            if chid in target_ids:
                code, conv, lat, lng, dist_km = channels[chid]
                sample_start = ch_pos + 40
                sample_end = sample_start + nsize * 2
                
                if sample_end <= len(ch_data) and nsize > 0:
                    # Find max absolute value
                    max_val = 0
                    for i in range(nsize):
                        val = struct.unpack_from('<h', ch_data, sample_start + i * 2)[0]
                        if abs(val) > abs(max_val):
                            max_val = val
                    
                    pga = abs(max_val) * conv * 100  # m/s → gal
                    
                    if chid not in pga_data:
                        pga_data[chid] = []
                    pga_data[chid].append(pga)
                    blocks += 1
            
            ch_pos += 40 + nsize * 2
        
        pos = block_end
    
    print(f"  {fname}: {blocks} blocks matched")

# Step 3: Calculate shindo and level
print("\n=== 伊予灘 M2.7 真实 NIED 数据 PGA 结果 ===")
scratchValues = [-3.0,-2.5,-2.0,-1.5,-1.17,-0.84,-0.5,-0.17,0.16,0.5,0.83,1.16,1.5,1.83,2.16,2.5,2.83,3.16,3.5,3.83,4.16,4.5,4.75,5.0,5.25,5.5,5.75,6.0,6.25,6.5]

for chid, (code, conv, lat, lng, dist_km) in sorted(channels.items(), key=lambda x: x[1][4]):
    if chid not in pga_data:
        print(f"  {code} dist={dist_km:.1f}km: NO DATA")
        continue
    v = pga_data[chid]
    max_pga = max(v)
    avg_pga = sum(v) / len(v)
    
    # JMA instrumental shindo
    if max_pga > 0.001:
        shindo = 2.68 + 1.72 * math.log10(max_pga)
    else:
        shindo = -3
    
    # levelFromShindo
    level = -1
    if shindo >= scratchValues[0]:
        for i in range(len(scratchValues)-1, -1, -1):
            if shindo >= scratchValues[i]:
                level = i
                break
    
    print(f"  {code} dist={dist_km:.1f}km maxPGA={max_pga:.2f}gal avgPGA={avg_pga:.2f}gal shindo={shindo:.1f} level={level} (n={len(v)}s)")
