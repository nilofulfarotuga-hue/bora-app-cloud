"""Espera pelos workflows do commit e imprime o estado final de cada um."""
import json
import subprocess
import sys
import time
import urllib.request

SHA = sys.argv[1]
ALVO = sys.argv[2:]  # nomes (substring) a esperar; vazio = todos
REPO = 'nilofulfarotuga-hue/bora-app-cloud'


def token():
    p = subprocess.run(['git', 'credential', 'fill'],
                       input='protocol=https\nhost=github.com\n\n',
                       capture_output=True, text=True,
                       cwd=r'C:\BoraLocal\projetosflutter\bora_app')
    return next((l.split('=', 1)[1] for l in p.stdout.splitlines()
                 if l.startswith('password=')), '')


def runs(tok):
    req = urllib.request.Request(
        f'https://api.github.com/repos/{REPO}/actions/runs?per_page=10&head_sha={SHA}',
        headers={'Authorization': 'Bearer ' + tok,
                 'Accept': 'application/vnd.github+json'})
    return json.load(urllib.request.urlopen(req, timeout=30))['workflow_runs']


tok = token()
fim = time.time() + 55 * 60
while time.time() < fim:
    try:
        rs = runs(tok)
    except Exception as e:  # rede a falhar não mata a espera
        print('erro transitório:', e, flush=True)
        time.sleep(60)
        continue
    alvo = [r for r in rs if not ALVO or any(a in r['name'] for a in ALVO)]
    if alvo and all(r['status'] == 'completed' for r in alvo):
        break
    time.sleep(45)

for r in rs:
    print(r['id'], r['name'], '|', r['status'], r['conclusion'], flush=True)
