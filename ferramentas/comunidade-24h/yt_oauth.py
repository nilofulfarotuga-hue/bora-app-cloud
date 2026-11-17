"""Autorização OAuth do YouTube, um canal de marca de cada vez (VPS).

O fluxo de dispositivo (google.com/device) NÃO serve: o comments.insert exige o âmbito
youtube.force-ssl, que esse fluxo não aceita. Por isso: fluxo de aplicação de computador com
PKCE e retorno para http://127.0.0.1:8765 no PC do Danilo, onde o pc_apanha_codigo.ps1 escuta
e guarda o código num ficheiro. O código sozinho não vale nada (precisa do segredo do cliente e
do verificador PKCE, que só existem no cofre da VPS), por isso pode passar pelo PC.

  python3 yt_oauth.py iniciar <conta>    -> grava o pendente e mostra o endereço de autorização
  python3 yt_oauth.py apanhar            -> vai buscar os códigos ao PC (ssh bora-pc) e troca-os
  python3 yt_oauth.py trocar <conta> <código ou endereço de retorno completo>
  python3 yt_oauth.py ver                -> diz que canais têm token e se o token renova

Cofre: youtube-cliente.json {client_id, client_secret}; youtube/<conta>.json {refresh_token,
channel_id, channel_title}; youtube/pendente-<conta>.json {state, verifier}.
"""
import base64
import glob
import hashlib
import os
import secrets
import subprocess
import sys
import urllib.parse

from comum import COFRE, contas, e2e, gravar_cofre, http, ler_cofre, registo

REDIRECT = "http://127.0.0.1:8765/"
ESCOPO = "https://www.googleapis.com/auth/youtube.force-ssl"
PASTA_PC = r"C:\BoraLocal\comunidade-24h"


class Falha(Exception):
    pass


def _conta(nome):
    for c in contas():
        if c["conta"] == nome and c.get("youtube"):
            return c
    sys.exit(f"conta sem YouTube: {nome}")


def iniciar(nome):
    c = _conta(nome)
    cli = ler_cofre("youtube-cliente.json")
    verifier = secrets.token_urlsafe(64)
    desafio = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = nome + "." + secrets.token_urlsafe(12)
    gravar_cofre(f"youtube/pendente-{nome}.json", {"state": state, "verifier": verifier})
    url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
        "client_id": cli["client_id"], "redirect_uri": REDIRECT, "response_type": "code",
        "scope": ESCOPO, "access_type": "offline", "prompt": "consent select_account",
        "state": state, "code_challenge": desafio, "code_challenge_method": "S256"})
    e2e(f"B3-oauth-{nome}", "precisa-danilo",
        f"Autorizar o canal do YouTube {c['youtube']} ({c['nome']}): abrir no Chrome pessoal 5b260cdd, "
        f"escolher o canal {c['youtube']} na lista de contas e carregar em Permitir. O PC tem de ter o "
        f"pc_apanha_codigo.ps1 a correr. Endereço: {url}")
    print(url)


def trocar(nome, codigo_ou_url):
    codigo = codigo_ou_url
    if codigo_ou_url.startswith("http"):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(codigo_ou_url).query)
        if q.get("error"):
            raise Falha(f"o Google devolveu erro: {q['error'][0]}")
        codigo = q["code"][0]
        if q.get("state", [""])[0] != ler_cofre(f"youtube/pendente-{nome}.json")["state"]:
            raise Falha("state não bate: não troco o código")
    cli = ler_cofre("youtube-cliente.json")
    pend = ler_cofre(f"youtube/pendente-{nome}.json")
    st, r = http("POST", "https://oauth2.googleapis.com/token", {
        "code": codigo, "client_id": cli["client_id"], "client_secret": cli["client_secret"],
        "redirect_uri": REDIRECT, "grant_type": "authorization_code", "code_verifier": pend["verifier"]},
        forma="form")
    if st != 200 or "refresh_token" not in r:
        e2e(f"B3-oauth-{nome}", "erro", f"troca do código falhou HTTP {st}: {str(r)[:300]}")
        raise Falha(f"troca falhou HTTP {st}")
    st2, canal = http("GET", "https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true",
                      cabecalhos={"Authorization": "Bearer " + r["access_token"]})
    item = (canal.get("items") or [{}])[0] if isinstance(canal, dict) else {}
    titulo = item.get("snippet", {}).get("title", "?")
    handle = item.get("snippet", {}).get("customUrl", "?")
    certo = _conta(nome)["youtube"].lower().lstrip("@") == handle.lower().lstrip("@")
    if not certo:
        e2e(f"B3-oauth-{nome}", "erro", f"autorizado o canal ERRADO ({titulo} {handle}); token deitado fora")
        raise Falha(f"canal errado: {handle}")
    gravar_cofre(f"youtube/{nome}.json", {"refresh_token": r["refresh_token"], "channel_id": item["id"],
                                          "channel_title": titulo, "handle": handle})
    os.remove(os.path.join(COFRE, f"youtube/pendente-{nome}.json"))
    registo("yt-autorizado", conta=nome, canal=item["id"])
    e2e(f"B3-oauth-{nome}", "feito", f"canal {titulo} ({handle}, {item['id']}) autorizado; channels.list mine=true lido de volta")
    print(f"ok {nome} -> {titulo} {handle}")


def apanhar():
    """Lê os códigos que o PC guardou (pela ligação ssh bora-pc que o contentor já tem)."""
    for pend in glob.glob(os.path.join(COFRE, "youtube", "pendente-*.json")):
        nome = os.path.basename(pend)[len("pendente-"):-len(".json")]
        state = ler_cofre(f"youtube/pendente-{nome}.json")["state"]
        r = subprocess.run(["ssh", "-F", "/opt/data/.ssh/config", "bora-pc",
                            f'type "{PASTA_PC}\\codigo-{state}.txt"'],
                           capture_output=True, text=True, timeout=60)
        if r.returncode == 0 and "=" in r.stdout:
            try:
                trocar(nome, REDIRECT + "?" + r.stdout.strip().lstrip("?"))
            except Falha as e:
                # o código já foi gasto: apagar o pendente para não repetir o erro de 2 em 2 min
                p = os.path.join(COFRE, f"youtube/pendente-{nome}.json")
                if os.path.exists(p):
                    os.remove(p)
                print(f"{nome}: {e} (pendente apagado; voltar a correr iniciar {nome})")
            finally:
                subprocess.run(["ssh", "-F", "/opt/data/.ssh/config", "bora-pc",
                                f'del "{PASTA_PC}\\codigo-{state}.txt"'], timeout=60)
        else:
            print(f"{nome}: ainda sem código no PC")


def token(nome):
    """Access token novo para o canal (usado pela ronda)."""
    cli = ler_cofre("youtube-cliente.json")
    t = ler_cofre(f"youtube/{nome}.json")
    st, r = http("POST", "https://oauth2.googleapis.com/token", {
        "client_id": cli["client_id"], "client_secret": cli["client_secret"],
        "refresh_token": t["refresh_token"], "grant_type": "refresh_token"}, forma="form")
    if st != 200:
        raise RuntimeError(f"YouTube {nome}: token não renovou HTTP {st}: {str(r)[:200]}")
    return r["access_token"], t["channel_id"]


def ver():
    for c in contas():
        if not c.get("youtube"):
            continue
        try:
            _, canal = token(c["conta"])
            print(f"{c['conta']}: ok ({canal})")
        except FileNotFoundError:
            print(f"{c['conta']}: sem autorização")
        except RuntimeError as e:
            print(f"{c['conta']}: {e}")


if __name__ == "__main__":
    acao = sys.argv[1] if len(sys.argv) > 1 else "ver"
    try:
        {"iniciar": lambda: iniciar(sys.argv[2]), "trocar": lambda: trocar(sys.argv[2], sys.argv[3]),
         "apanhar": apanhar, "ver": ver}[acao]()
    except Falha as e:
        sys.exit(str(e))
