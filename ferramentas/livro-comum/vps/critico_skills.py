#!/usr/bin/env python3
"""O critico revê as skills criadas pelo Hermes antes de entrarem na pasta comum (missão livro-comum-2026-10-23).
Saída: /tmp/critico_skills.json  {pasta: {veredito, motivo, segredo}}"""
import io, json, re, subprocess

C = 'hermes-agent-fvnc-hermes-agent-1'
CAND = ['creative/multi-asset-web-project', 'devops/remote-command-execution', 'email/email-management-himalaya',
        'hermes-agent/buzz-platform-operation', 'hermes-agent/desbloqueio-zona-vermelha',
        'hermes-agent/future-project-registration', 'hermes-agent/hermes-auto-configuracao',
        'hermes-agent/hermes-operacao-confiavel', 'hermes-agent/socio-ai-onboarding', 'remote-delegation-gate',
        'research/web-content-extraction', 'software-development/competitive-feature-audit']
SEG = re.compile(r'(sk_live_|sk_test_|sb_secret_|eyJhbGciOi|ghp_[A-Za-z0-9]{20}|AIza[0-9A-Za-z_-]{30}|PRIVATE KEY|tskey-)')
REGRAS = ('Regras do Bora que a skill NÃO pode contrariar: dinheiro (preços, Stripe, tokens, carteira) só com "autorizo" do '
          'Danilo; nunca UPDATE direto em orders/drivers/wallets; "feito" só com prova; reportar falhas, nunca as esconder; '
          'nunca segredos em ficheiros; mensagens para fora só com confirmação.')
out = {}
for c in CAND:
    t = io.open('/opt/data/skills/%s/SKILL.md' % c, encoding='utf-8', errors='replace').read()
    seg = bool(SEG.search(t))
    pedido = ('És o critico do Bora. Revê esta skill criada pelo Hermes antes de entrar na pasta comum de skills de todos os '
              'agentes. %s\nResponde EXACTAMENTE numa linha a começar por "APROVADA:" ou "REPROVADA:" seguida do motivo em '
              'menos de 25 palavras (útil para o negócio do Danilo? contradiz alguma regra? inventa coisas?).\n\n=== %s ===\n%s'
              % (REGRAS, c, t[:9000]))
    guiao = 'cd /opt/data && exec hermes -p critico --provider custom -z "$1"'
    try:
        r = subprocess.run(['docker', 'exec', '-u', 'hermes', '-e', 'HOME=/opt/data', C, 'sh', '-lc', guiao, '_', pedido],
                           capture_output=True, text=True, timeout=300)
        s = (r.stdout or r.stderr or '').strip()
    except subprocess.TimeoutExpired:
        s = 'SEM RESPOSTA: o critico passou dos 300 s'
    m = re.search(r'(APROVADA|REPROVADA)\s*:?(.*)', s)
    out[c] = {'veredito': m.group(1) if m else 'SEM-VEREDITO', 'motivo': (m.group(2).strip() if m else s[-200:])[:300],
              'segredo': seg}
    print(c, out[c]['veredito'], '|', out[c]['motivo'][:120], '| segredo' if seg else '', flush=True)
json.dump(out, open('/tmp/critico_skills.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
