#!/usr/bin/env python3
"""Host: processa /opt/data/livro-fila/*.json (pedidos do comando aprender do Hermes) e chama
public.livro_aprender com a service key. Escreve <id>.resposta para o Hermes ler.
Corrido pela unidade systemd livro-fila.service (disparada por livro-fila.path).
Missão livro-comum-2026-10-23.

22/11/2026 (missão hermes-diretor-2026-11-20, B6.5): quando quem aprende é o Hermes, a correção fica
também em public.licoes_robos (robo 'hermes'); se for a 2.ª vez da mesma lição, a regra passa para a
secção 12 da alma (/opt/data/SOUL-base.md), com cópia antes e sem nunca passar os 10 000 bytes."""
import glob, io, json, os, re, shutil, subprocess, time, unicodedata, urllib.parse, urllib.request, urllib.error

FILA = '/opt/data/livro-fila'
FEITOS = os.path.join(FILA, 'feitos')
ENVF = '/opt/whatsapp-bora/.env'
ALMA = '/opt/data/SOUL-base.md'
ARQUIVO = '/opt/data/arquivo'
TETO_ALMA = 10000
UID = 10000


def env():
    e = {}
    for ln in io.open(ENVF, encoding='utf-8', errors='replace'):
        ln = ln.strip()
        if ln and not ln.startswith('#') and '=' in ln:
            k, v = ln.split('=', 1)
            e[k.strip()] = v.strip().strip('"').strip("'")
    return e


def rest(e, caminho, metodo='GET', corpo=None):
    k = e['SUPABASE_SERVICE_ROLE_KEY']
    req = urllib.request.Request(e['SUPABASE_URL'].rstrip('/') + '/rest/v1/' + caminho,
                                 data=json.dumps(corpo).encode() if corpo is not None else None, method=metodo,
                                 headers={'apikey': k, 'Authorization': 'Bearer ' + k, 'Content-Type': 'application/json',
                                          'Prefer': 'return=representation'})
    with urllib.request.urlopen(req, timeout=30) as r:
        txt = r.read().decode() or '[]'
        return json.loads(txt)


def rpc(e, corpo):
    try:
        return 'GRAVADO no livro (erros-aprendidos): ' + rest(e, 'rpc/livro_aprender', 'POST', corpo)
    except urllib.error.HTTPError as ex:
        try:
            msg = json.load(ex).get('message', '')
        except Exception:
            msg = str(ex)
        return 'RECUSADO: ' + msg


def palavras(t):
    t = unicodedata.normalize('NFKD', t or '').encode('ascii', 'ignore').decode().lower()
    return {w for w in re.findall(r'[a-z0-9]+', t) if len(w) > 3}


def mesma_licao(a, b):
    """A mesma lição dita por outras palavras: metade ou mais das palavras em comum."""
    pa, pb = palavras(a), palavras(b)
    return bool(pa and pb) and len(pa & pb) / float(len(pa | pb)) >= 0.5


def licao_do_hermes(e, errei, regra):
    """Soma a lição do Hermes em licoes_robos. Devolve quantas vezes já vai."""
    linhas = rest(e, 'licoes_robos?robo=eq.hermes&arquivada_em=is.null&select=id,regra,vezes')
    for l in linhas:
        if mesma_licao(l.get('regra'), regra):
            vezes = int(l.get('vezes') or 1) + 1
            rest(e, 'licoes_robos?id=eq.%s' % l['id'], 'PATCH', {'vezes': vezes, 'ativa': True, 'editada_em': 'now()'})
            return vezes
    rest(e, 'licoes_robos', 'POST', {'robo': 'hermes', 'errou': errei[:600], 'regra': regra[:600],
                                     'origem': 'correcao-do-danilo', 'vezes': 1, 'ativa': True})
    return 1


def regra_para_a_alma(regra):
    """2.ª vez da mesma lição: entra na secção 12 da alma, com cópia antes. Nunca passa o teto."""
    texto = io.open(ALMA, encoding='utf-8').read()
    linha = '- ' + re.sub(r'\s+', ' ', regra).strip()[:300]
    if linha in texto:
        return 'ja estava na alma'
    novo = texto.replace('(vazio)\n', linha + '\n', 1) if '(vazio)\n' in texto else texto.rstrip('\n') + '\n' + linha + '\n'
    if len(novo.encode('utf-8')) > TETO_ALMA:
        return 'NAO entrou na alma: passava os %d bytes (rever a seccao 12)' % TETO_ALMA
    os.makedirs(ARQUIVO, exist_ok=True)
    shutil.copy2(ALMA, os.path.join(ARQUIVO, 'SOUL-base-%s.md' % time.strftime('%Y%m%dT%H%M%S')))
    tmp = ALMA + '.tmp'
    io.open(tmp, 'w', encoding='utf-8', newline='\n').write(novo)
    os.chown(tmp, UID, UID)
    os.chmod(tmp, 0o644)
    os.replace(tmp, ALMA)
    subprocess.run(['/usr/bin/python3', '/opt/data/bin/livro_ao_acordar.py'], capture_output=True, timeout=120)
    return 'regra passou para a alma (seccao 12)'


def main():
    os.makedirs(FEITOS, exist_ok=True)
    e = None
    for p in sorted(glob.glob(os.path.join(FILA, '*.json'))):
        e = e or env()
        try:
            d = json.load(io.open(p, encoding='utf-8'))
            quem, errei, regra = d.get('quem', 'hermes'), d.get('errei', ''), d.get('regra', '')
            txt = rpc(e, {'p_quem': quem, 'p_errei': errei, 'p_regra': regra})
            if txt.startswith('GRAVADO') and quem == 'hermes':
                try:
                    vezes = licao_do_hermes(e, errei, regra)
                    txt += ' | licao do hermes: %d.a vez' % vezes
                    if vezes == 2:
                        txt += ' | ' + regra_para_a_alma(regra)
                except Exception as ex:  # a lição no livro já ficou; isto não a pode estragar
                    txt += ' | (licoes_robos falhou: %s)' % str(ex)[:120]
        except Exception as ex:
            txt = 'ERRO no host: %s' % ex
        r = p[:-5] + '.resposta'
        io.open(r, 'w', encoding='utf-8').write(txt + '\n')
        os.chown(r, UID, UID)
        os.replace(p, os.path.join(FEITOS, os.path.basename(p)))
        print(os.path.basename(p), '->', txt[:160])


if __name__ == '__main__':
    main()
