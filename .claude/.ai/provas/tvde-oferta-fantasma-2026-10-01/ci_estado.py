# -*- coding: utf-8 -*-
"""Estado do CI no GitHub sem o `gh`: usa o token que o Git Credential
Manager ja guardou (nunca o imprime). Uso: py ci_estado.py [run_id]"""
import json
import subprocess
import sys
import urllib.request

REPO = 'nilofulfarotuga-hue/bora-app-cloud'
out = subprocess.run(['git', 'credential', 'fill'],
                     input='protocol=https\nhost=github.com\n\n',
                     capture_output=True, text=True).stdout
tok = dict(l.split('=', 1) for l in out.splitlines() if '=' in l)['password']


def get(caminho):
    req = urllib.request.Request(
        'https://api.github.com/repos/%s/%s' % (REPO, caminho),
        headers={'Authorization': 'Bearer ' + tok,
                 'Accept': 'application/vnd.github+json'})
    return json.load(urllib.request.urlopen(req, timeout=30))


if len(sys.argv) > 1:
    for j in get('actions/runs/%s/jobs' % sys.argv[1])['jobs']:
        print(j['name'], '|', j['status'], '|', j['conclusion'],
              '|', j['started_at'], '->', j['completed_at'])
        for s in j['steps']:
            if s['conclusion'] not in ('success', 'skipped', None):
                print('   passo', s['name'], s['conclusion'])
else:
    for r in get('actions/runs?per_page=6')['workflow_runs']:
        print(r['id'], '|', r['name'], '|', r['head_sha'][:8], '|',
              r['status'], '|', r['conclusion'], '|', r['created_at'],
              '| #%s' % r['run_number'])
