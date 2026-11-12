"""Controller side only; the cloud Windows host does not need Python."""
import argparse, json, pathlib, urllib.request

p=argparse.ArgumentParser()
p.add_argument('--connection',type=pathlib.Path,required=True)
p.add_argument('--url',help='Override URL when using a local SSH forward')
p.add_argument('command',choices=['status','samples','diagnostics','health','scenario','inject','shutdown'])
p.add_argument('--label')
p.add_argument('--file',type=pathlib.Path)
p.add_argument('--format',default='whews')
p.add_argument('--output',type=pathlib.Path)
a=p.parse_args()
connection=json.loads(a.connection.read_text(encoding='utf-8-sig'))
routes={'status':'/status','samples':'/samples','diagnostics':'/app/diagnostics','health':'/app/health','scenario':'/scenario','shutdown':'/shutdown'}
body=None
if a.command=='scenario':
    if not a.label:p.error('--label is required')
    body=json.dumps({'label':a.label},ensure_ascii=False).encode('utf-8')
elif a.command=='inject':
    if not a.file:p.error('--file is required')
    if not a.format or any(not(c.isascii() and(c.isalnum() or c in '_-'))for c in a.format):p.error('Invalid format')
    # Read once and forward original bytes; never decode/rewrite observation data.
    body=a.file.read_bytes();routes['inject']='/app/inject?format='+a.format
elif a.command=='shutdown':body=b''
request=urllib.request.Request((a.url or connection['url']).rstrip('/')+routes[a.command],data=body,
    headers={'Authorization':'Bearer '+connection['token'],'Content-Type':'application/json; charset=utf-8'},
    method='POST' if body is not None else 'GET')
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open(request,timeout=20)as response:raw=response.read()
if a.output:a.output.write_bytes(raw)
else:print(json.dumps(json.loads(raw),ensure_ascii=False,indent=2))
