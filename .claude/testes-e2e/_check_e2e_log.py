import json, re
from pathlib import Path
BASE = Path(__file__).resolve().parent
REPO = BASE.parent.parent
env = {}
for f in [BASE/'.env', REPO/'backend'/'.env']:
    if f.exists():
        for line in f.read_text(encoding='utf-8', errors='replace').splitlines():
            m = re.match(r"^\s*([A-Z0-9_]+)\s*=\s*[\"']?([^\"'#]+)", line)
            if m:
                env.setdefault(m.group(1), m.group(2).strip())
url = env.get('SUPABASE_URL') or env.get('SUPABASE_PROJECT_URL')
key = (env.get('SUPABASE_SERVICE_ROLE_KEY') or env.get('SERVICE_ROLE_KEY') or env.get('SUPABASE_KEY') or env.get('SUPABASE_ANON_KEY'))
print('URL found:', bool(url), 'KEY found:', bool(key))
import urllib.request
req = urllib.request.Request(
    f"{url}/rest/v1/e2e_log?select=created_at,fluxo,passo,estado,device&order=created_at.desc&limit=8",
    headers={'apikey': key, 'Authorization': f'Bearer {key}'})
with urllib.request.urlopen(req, timeout=8) as r:
    rows = json.loads(r.read().decode())
for row in rows:
    print(row.get('created_at'), row.get('fluxo'), row.get('passo'), row.get('estado'), row.get('device'))
