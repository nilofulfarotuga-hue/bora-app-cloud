#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Autorizacao do Gmail da Bora para o carteiro (missao caca-clientes-2026-10-03).

O unico clique do Danilo e o "Permitir" do Google. Este script:
  1. le o cliente OAuth (ficheiro client_secret*.json) sem o mostrar;
  2. abre a pagina de consentimento no Chrome do perfil Bora (Profile 1), a frente;
  3. espera o codigo num endereco local (127.0.0.1), troca-o pelo refresh token;
  4. confirma que a conta autorizada e boraappbora@gmail.com;
  5. grava GMAIL_BORA_CLIENT_ID / _CLIENT_SECRET / _REFRESH_TOKEN em /opt/data/.env da VPS, por ssh.
Nenhum segredo e impresso nem fica no repo. O estado vai para autorizar_gmail.log.
"""
import glob
import http.server
import io
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

BASE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(BASE, "autorizar_gmail.log")
SEGREDOS = r"C:\BoraLocal\_segredos\avenca"
DOWNLOADS = os.path.join(os.path.expanduser("~"), "Downloads")
CONTA = "boraappbora@gmail.com"
SCOPES = "https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.readonly"
PORTA = 8765
ESPERA_S = int(sys.argv[1]) if len(sys.argv) > 1 else 6 * 3600
VPS = "root@srv1786862.hstgr.cloud"
CHAVE_SSH = os.path.join(os.path.expanduser("~"), ".ssh", "id_ed25519_vps")
CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


def log(msg):
    linha = "[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    with io.open(LOG, "a", encoding="utf-8") as f:
        f.write(linha + chr(10))
    print(linha, flush=True)


def cliente():
    guardado = os.path.join(SEGREDOS, "gmail_bora_oauth_client.json")
    novos = sorted(glob.glob(os.path.join(DOWNLOADS, "client_secret*.json")), key=os.path.getmtime)
    if novos:
        shutil.move(novos[-1], guardado)
        for resto in novos[:-1]:
            os.remove(resto) if os.path.getsize(resto) < 4096 else None
    d = json.load(io.open(guardado, encoding="utf-8"))
    d = d.get("installed") or d.get("web")
    return d["client_id"], d["client_secret"]


class Apanha(http.server.BaseHTTPRequestHandler):
    codigo = None
    erro = None

    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if "code" in q:
            Apanha.codigo = q["code"][0]
            texto = "Feito. O carteiro da Bora ja pode enviar email. Podes fechar este separador."
        elif "error" in q:
            Apanha.erro = q["error"][0]
            texto = "Nao foi autorizado (%s)." % Apanha.erro
        else:
            texto = "..."
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(("<html><body style='font-family:sans-serif;font-size:22px;padding:40px'>%s</body></html>" % texto).encode("utf-8"))

    def log_message(self, *a):
        pass


def main():
    cid, segredo = cliente()
    redir = "http://127.0.0.1:%d/" % PORTA
    url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
        "client_id": cid, "redirect_uri": redir, "response_type": "code", "scope": SCOPES,
        "access_type": "offline", "prompt": "consent", "login_hint": CONTA})
    srv = http.server.HTTPServer(("127.0.0.1", PORTA), Apanha)
    srv.timeout = 5
    subprocess.Popen([CHROME, "--profile-directory=Profile 1", "--new-window", url])
    log("PAGINA ABERTA no Chrome (perfil Bora). A espera do Permitir ate %d min." % (ESPERA_S // 60))
    fim = time.time() + ESPERA_S
    while time.time() < fim and not Apanha.codigo and not Apanha.erro:
        srv.handle_request()
    srv.server_close()
    if Apanha.erro:
        log("FIM FALHOU: o Google devolveu %s" % Apanha.erro)
        return 1
    if not Apanha.codigo:
        log("FIM FALHOU: ninguem carregou em Permitir dentro do prazo")
        return 1
    dados = urllib.parse.urlencode({"code": Apanha.codigo, "client_id": cid, "client_secret": segredo,
                                    "redirect_uri": redir, "grant_type": "authorization_code"}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=dados), timeout=30) as r:
        t = json.loads(r.read().decode())
    if not t.get("refresh_token"):
        log("FIM FALHOU: o Google nao devolveu refresh token")
        return 1
    req = urllib.request.Request("https://gmail.googleapis.com/gmail/v1/users/me/profile", headers={"Authorization": "Bearer " + t["access_token"]})
    with urllib.request.urlopen(req, timeout=30) as r:
        conta = json.loads(r.read().decode()).get("emailAddress", "")
    if conta.lower() != CONTA:
        log("FIM FALHOU: a conta autorizada foi %s e nao a da Bora; nada foi gravado" % conta)
        return 1
    linhas = "GMAIL_BORA_CLIENT_ID=%s\nGMAIL_BORA_CLIENT_SECRET=%s\nGMAIL_BORA_REFRESH_TOKEN=%s\n" % (cid, segredo, t["refresh_token"])
    remoto = ("sed -i '/^GMAIL_BORA_/d' /opt/data/.env && cat >> /opt/data/.env && "
              "grep -c '^GMAIL_BORA_' /opt/data/.env")
    p = subprocess.run(["ssh", "-o", "BatchMode=yes", "-i", CHAVE_SSH, VPS, remoto], input=linhas.encode(), capture_output=True, timeout=60)
    n = p.stdout.decode().strip()
    if p.returncode != 0 or n != "3":
        log("FIM FALHOU: gravacao na VPS (rc=%s, linhas=%s)" % (p.returncode, n))
        return 1
    log("FIM OK: conta %s autorizada; 3 variaveis GMAIL_BORA_ gravadas em /opt/data/.env da VPS" % conta)
    return 0


if __name__ == "__main__":
    sys.exit(main())
