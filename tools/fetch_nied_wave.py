import os

import requests


def require_env(name):
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


USER = require_env("NIED_USERNAME")
PASS = require_env("NIED_PASSWORD")
session = requests.Session()

base = "https://hinetwww11.bosai.go.jp/auth"
session.get(f"{base}/?LANG=en", timeout=15).raise_for_status()
login_response = session.post(
    f"{base}/?LANG=en",
    data={"auth_un": USER, "auth_pw": PASS},
    timeout=15,
)
login_response.raise_for_status()

# NIED might use a different subdomain or path after login
# Common NIED download systems:
urls = [
    # Main menu after login
    "https://hinetwww11.bosai.go.jp/auth/menu/?LANG=en",
    "https://hinetwww11.bosai.go.jp/auth/top/?LANG=en",
    "https://hinetwww11.bosai.go.jp/auth/continuous/?LANG=en",
    "https://hinetwww11.bosai.go.jp/auth/event/?LANG=en",
    # Download CGI
    "https://hinetwww11.bosai.go.jp/auth/cgi/download.cgi",
    "https://hinetwww11.bosai.go.jp/auth/cgi/event.cgi",
    # Different numbering
    "https://hinetwww11.bosai.go.jp/auth/0/?LANG=en",
    "https://hinetwww11.bosai.go.jp/auth/1/?LANG=en",
    "https://hinetwww11.bosai.go.jp/auth/index2.php?LANG=en",
]
for url in urls:
    try:
        r = session.get(url, timeout=10, allow_redirects=False)
        print(f"{r.status_code} {url} ({len(r.text)}b)")
    except Exception as e:
        print(f"ERR {url}: {e}")
