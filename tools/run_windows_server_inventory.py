"""Execute a supplied read-only inventory script over encrypted NTLM WinRM."""
import argparse
import json
import os
from pathlib import Path
import sys
import winrm

parser = argparse.ArgumentParser()
parser.add_argument('script', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
session = winrm.Session(
    'http://' + os.environ['RQ_AUDIT_HOST'] + ':5985/wsman',
    auth=(os.environ['RQ_AUDIT_USER'], os.environ['RQ_AUDIT_PASSWORD']),
    transport='ntlm', message_encryption='always', proxy=None,
    read_timeout_sec=120, operation_timeout_sec=100,
)
response = session.run_ps(args.script.read_text(encoding='utf-8'))
if response.status_code:
    print(response.std_err.decode('utf-8', errors='replace'))
    sys.exit(response.status_code)
result = json.loads(response.std_out.decode('utf-8-sig'))
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
