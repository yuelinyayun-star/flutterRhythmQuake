"""Preserve actual DNS, TCP and validated HTTPS results; no network changes."""
import concurrent.futures
import datetime as dt
import json
import os
from pathlib import Path
import socket
import time
import urllib.error
import urllib.parse
import urllib.request


def safe_proxy(value):
    try:
        u = urllib.parse.urlsplit(value if '://' in value else 'http://'+value)
        return {'host': u.hostname, 'port': u.port, 'scheme': u.scheme}
    except Exception:
        return {'configured': True}


def check(target):
    u = urllib.parse.urlsplit(target)
    host = u.hostname
    port = u.port or (443 if u.scheme == 'https' else 80)
    result = {'target': target, 'host': host, 'port': port}
    started = time.monotonic()
    try:
        result['addresses'] = sorted({a[4][0] for a in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)})
    except Exception as e:
        result['dnsError'] = str(e)
        return result
    result['dnsMillis'] = (time.monotonic()-started)*1000
    t = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=5):
            result['tcp'] = True
    except Exception as e:
        result['tcp'] = False
        result['tcpError'] = str(e)
    result['tcpMillis'] = (time.monotonic()-t)*1000
    if u.scheme in ['http', 'https']:
        result['http'] = {}
        for name, proxy in [('systemProxy', urllib.request.ProxyHandler()), ('direct', urllib.request.ProxyHandler({}))]:
            t = time.monotonic()
            try:
                req = urllib.request.Request(target, headers={'User-Agent':'RhythmQuake-Startup-Diagnostics/1.0'})
                with urllib.request.build_opener(proxy).open(req, timeout=6) as r:
                    result['http'][name] = {'status':r.status, 'url':r.url}
            except urllib.error.HTTPError as e:
                result['http'][name] = {'status':e.code, 'url':e.url}
            except Exception as e:
                result['http'][name] = {'error':str(e)}
            result['http'][name]['millis'] = (time.monotonic()-t)*1000
    return result


def run(root):
    settings = json.loads((root/'private/session.json').read_text(encoding='utf8'))
    targets = ['tcp://'+settings['host']+':22', 'https://agent.yuelinrhythm.top/']
    file = root/'network-targets.txt'
    if file.exists():
        targets.extend(s.strip() for s in file.read_text(encoding='utf-8-sig').splitlines() if s.strip() and not s.lstrip().startswith('#'))
    targets = list(dict.fromkeys(targets))
    for url in targets:
        u = urllib.parse.urlsplit(url)
        if u.scheme not in ['http','https','tcp'] or not u.hostname or u.username or u.password:
            raise ValueError('Invalid diagnostic URL: use http(s)://host/path or tcp://host:port without credentials')
    result = {'utc':dt.datetime.now(dt.timezone.utc).isoformat(),
        'proxies':{k:safe_proxy(v) for k,v in urllib.request.getproxies().items() if k.lower() != 'no'},
        'results':[]}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for row in pool.map(check, targets):
            result['results'].append(row)
            print('Network:', row['host'], row['port'], 'TCP='+str(row.get('tcp')), row.get('dnsError',''), flush=True)
    out = root/'logs/network.json'
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf8')
    return result


if __name__ == '__main__':
    import sys
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf8')
    run(Path(__file__).resolve().parent)
