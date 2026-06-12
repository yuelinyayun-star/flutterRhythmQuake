import urllib.request, json, gzip
from datetime import datetime, timezone, timedelta

# Test current time (now) - should have data
now = datetime.now(timezone(timedelta(hours=9)))
t = now.strftime('%Y%m%d%H%M00')
url = f'https://weather-kyoshin.east.edge.storage-yahoo.jp/RealTimeData/{t[:8]}/{t}.json'

print(f'Testing current JST: {t}')
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Accept-Encoding': 'identity'})
resp = urllib.request.urlopen(req, timeout=10)
d = json.loads(gzip.decompress(resp.read()))
rtd = d['realTimeData']
intensity = rtd.get('intensity', [])
print(f'  intensity array length: {len(intensity)}')
print(f'  hypoInfo: {d.get("hypoInfo") is not None}')
print(f'  estShindo: {d.get("estShindo") is not None}')
if isinstance(intensity, list) and len(intensity) > 0:
    print(f'  first 5: {intensity[:5]}')
    # Count non-zero
    non_zero = sum(1 for x in intensity if isinstance(x, (int, float)) and x > 0)
    print(f'  non-zero entries: {non_zero}')

# Also test 1 hour ago
t2 = (now - timedelta(hours=1)).strftime('%Y%m%d%H%M00')
url2 = f'https://weather-kyoshin.east.edge.storage-yahoo.jp/RealTimeData/{t2[:8]}/{t2}.json'
print(f'\nTesting 1h ago: {t2}')
req2 = urllib.request.Request(url2, headers={'User-Agent': 'Mozilla/5.0', 'Accept-Encoding': 'identity'})
try:
    resp2 = urllib.request.urlopen(req2, timeout=10)
    d2 = json.loads(gzip.decompress(resp2.read()))
    i2 = d2['realTimeData'].get('intensity', [])
    print(f'  intensity length: {len(i2)}')
    non_zero = sum(1 for x in i2 if isinstance(x, (int, float)) and x > 0)
    print(f'  non-zero: {non_zero}')
except Exception as e:
    print(f'  ERROR: {e}')
