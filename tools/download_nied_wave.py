import requests, re, os

USER = "Yun Lin"
PASS = "mmMCygyw1"
AUTH = "https://hinetwww11.bosai.go.jp/auth/"

session = requests.Session()
session.verify = False
requests.packages.urllib3.disable_warnings()

# Login
session.get(AUTH, timeout=15)
print(f"Cookies after GET: {dict(session.cookies)}")
r = session.post(AUTH, data={"auth_un": USER, "auth_pw": PASS}, timeout=15)
print(f"Cookies after POST: {dict(session.cookies)}")
print(f"auth_logout.png in response: {'auth_logout.png' in r.text}")
print(f"Redirect history: {[h.url for h in r.history]}")

# Try accessing cont_request.php - but NIED might use a different path
# Let's first check what the actual menu links are on the logged-in page
menu_pattern = re.findall(r'href="(\./|/auth/)([^"]+)"', r.text)
print(f"\nMenu links:")
for prefix, path in menu_pattern[:10]:
    print(f"  {prefix}{path}")

# Also check for any download form links
form_pattern = re.findall(r'<form[^>]*action="([^"]*)"', r.text)
print(f"\nForm actions: {form_pattern}")
