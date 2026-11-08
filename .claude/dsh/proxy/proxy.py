#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Proxy local do Dipsy com registo (missao m3-dipsy-acesso-total-2026-11-08). Codigo nosso, so biblioteca padrao + PyYAML.

- Ouve SO em 127.0.0.1:47900 (nunca na rede). O dsh e tudo o que ele lanca (shell, curl, git, python, web_fetch) recebem
  HTTPS_PROXY/HTTP_PROXY=http://127.0.0.1:47900 dos lancadores (ponte do Telegram, DIPSY, DIPSY-MISSAO).
- Cada dominio passa pela politica de ~/.dsh/rede-categorias.yml (modulo rede.py): permitido, barrado, ou "pergunta"
  (fora das categorias: devolve 403 e cria o pedido "Posso abrir X?" que a ponte manda ao Danilo pelo Telegram).
- HTTPS vai em tunel (CONNECT), sem abrir o conteudo (sem certificados falsos): regista dominio, porta, bytes, tempo.
- Categorias so_leitura: a ligacao que mande mais de 1 MB para fora e cortada (e assim que se faz um upload).
- Registo: ~/.dsh/proxy/registo.jsonl, uma linha por ligacao: quando, dominio, porta, metodo, categoria, decisao, motivo,
  enviados, recebidos, ms. Roda para registo-AAAAMMDD-HHMMSS.jsonl acima de 20 MB.

Uso: pythonw proxy.py            (corre; uma so instancia: se a porta estiver ocupada, sai)
     python proxy.py --estado    (diz se esta vivo e os ultimos pedidos)
"""
import asyncio
import json
import os
import socket
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rede  # noqa: E402

PORTA = 47900
ENDERECO = "127.0.0.1"
MAX_REGISTO = 20 * 1024 * 1024
LOG = os.path.join(rede.PASTA_PROXY, "proxy.log")


def log(msg):
    try:
        os.makedirs(rede.PASTA_PROXY, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"[{datetime.now().isoformat(timespec='seconds')}] {msg}\n")
    except Exception:
        pass


def registar(**campos):
    campos = {"quando": datetime.now(timezone.utc).isoformat(timespec="seconds"), **campos}
    try:
        os.makedirs(rede.PASTA_PROXY, exist_ok=True)
        try:
            if os.path.getsize(rede.REGISTO) > MAX_REGISTO:
                os.replace(rede.REGISTO, rede.REGISTO.replace(".jsonl", datetime.now().strftime("-%Y%m%d-%H%M%S.jsonl")))
        except OSError:
            pass
        with open(rede.REGISTO, "a", encoding="utf-8") as f:
            f.write(json.dumps(campos, ensure_ascii=False) + "\n")
    except Exception as e:
        log(f"nao consegui registar: {type(e).__name__}")


async def _ler_cabecalho(leitor):
    dados = await asyncio.wait_for(leitor.readuntil(b"\r\n\r\n"), timeout=30)
    if len(dados) > 65536:
        raise ValueError("cabecalho grande demais")
    return dados


def _responder_erro(escritor, codigo, texto):
    corpo = (texto + "\n").encode("utf-8")
    escritor.write(f"HTTP/1.1 {codigo} {'Forbidden' if codigo == 403 else 'Bad Gateway' if codigo == 502 else 'Bad Request'}\r\n"
                   f"Content-Type: text/plain; charset=utf-8\r\nContent-Length: {len(corpo)}\r\nConnection: close\r\n"
                   f"X-Dipsy-Proxy: barrado\r\n\r\n".encode("latin-1") + corpo)


def _decidir(host):
    decisao, categoria, motivo, so_leitura = rede.decidir(host)
    pedido = None
    if decisao == "pergunta":
        try:
            pedido = rede.criar_pedido_rede(host, origem="proxy")
        except Exception as e:
            log(f"pedido de rede falhou para {host}: {type(e).__name__}")
    return decisao, categoria, motivo, so_leitura, pedido


def _texto_barrado(host, decisao, motivo, pedido):
    if decisao == "pergunta":
        return (f"Bloqueado pelo proxy do Dipsy: {host} não está em nenhuma categoria. "
                f"Perguntei ao Danilo pelo Telegram se pode abrir{f' (pedido {pedido})' if pedido else ''}; "
                "sem o sim dele, fica barrado.")
    return f"Bloqueado pelo proxy do Dipsy: {host} ({motivo})."


_dns_cache = {}


def _resolver_doh(host):
    """Reserva quando o DNS do router falha (o da NOS diz que example.com nao existe): DNS seguro da Google, so registo A."""
    import urllib.request
    c = _dns_cache.get(host)
    if c and c[1] > time.time():
        return c[0]
    req = urllib.request.Request(f"https://dns.google/resolve?name={host}&type=A", headers={"accept": "application/dns-json"})
    direto = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # nunca por si proprio
    with direto.open(req, timeout=8) as r:
        j = json.loads(r.read().decode("utf-8"))
    ips = [a["data"] for a in j.get("Answer", []) if a.get("type") == 1]
    if ips:
        _dns_cache[host] = (ips[0], time.time() + 300)
        return ips[0]
    raise socket.gaierror(f"sem registo A para {host}")


async def _ligar(host, porta):
    """Liga ao destino; se o DNS do sistema falhar, tenta o DNS seguro (o TLS continua a usar o nome certo)."""
    try:
        return await asyncio.wait_for(asyncio.open_connection(host, porta), timeout=20), "dns-sistema"
    except socket.gaierror:
        ip = await asyncio.get_running_loop().run_in_executor(None, _resolver_doh, host)
        return await asyncio.wait_for(asyncio.open_connection(ip, porta), timeout=20), "dns-seguro"


async def _bombear(origem, destino, contador, chave, limite=None, ao_passar=None):
    try:
        while True:
            bloco = await origem.read(65536)
            if not bloco:
                break
            contador[chave] += len(bloco)
            if limite is not None and contador[chave] > limite:
                if ao_passar:
                    ao_passar()
                break
            destino.write(bloco)
            await destino.drain()
    except Exception:
        pass
    finally:
        try:
            destino.close()
        except Exception:
            pass


async def tratar(leitor, escritor):
    inicio = time.time()
    cont = {"enviados": 0, "recebidos": 0}
    info = {"metodo": "?", "dominio": "?", "porta": 0}
    try:
        cab = await _ler_cabecalho(leitor)
        linhas = cab.decode("latin-1").split("\r\n")
        metodo, alvo, versao = (linhas[0].split(" ") + ["", "", ""])[:3]
        info["metodo"] = metodo.upper()
        if info["metodo"] == "CONNECT":
            host, _, porta = alvo.rpartition(":")
            host = host.strip("[]")
            porta = int(porta or 443)
            caminho = None
            resto = b""
        else:
            from urllib.parse import urlsplit
            u = urlsplit(alvo)
            if u.scheme != "http" or not u.hostname:
                _responder_erro(escritor, 400, "O proxy do Dipsy só aceita CONNECT (https) ou http:// absoluto.")
                registar(metodo=info["metodo"], dominio=str(u.hostname), porta=0, categoria=None, decisao="erro",
                         motivo="pedido mal formado", enviados=0, recebidos=0, ms=0)
                return
            host, porta = u.hostname, (u.port or 80)
            caminho = (u.path or "/")
            pedido_origem = caminho + (("?" + u.query) if u.query else "")
            cabecalhos = [l for l in linhas[1:] if l and not l.lower().startswith(("proxy-connection:", "proxy-authorization:", "connection:", "keep-alive:"))]
            resto = (f"{metodo} {pedido_origem} {versao}\r\n" + "\r\n".join(cabecalhos) + "\r\nConnection: close\r\n\r\n").encode("latin-1")
        info["dominio"], info["porta"] = host.lower(), porta
        decisao, categoria, motivo, so_leitura, pedido = await asyncio.get_running_loop().run_in_executor(None, _decidir, host)
        if decisao != "permitido":
            _responder_erro(escritor, 403, _texto_barrado(host, decisao, motivo, pedido))
            await escritor.drain()
            registar(metodo=info["metodo"], dominio=host.lower(), porta=porta, categoria=categoria, decisao=decisao,
                     motivo=motivo, pedido=pedido, enviados=0, recebidos=0, ms=int((time.time() - inicio) * 1000))
            return
        try:
            (up_leitor, up_escritor), via_dns = await _ligar(host, porta)
        except Exception as e:
            _responder_erro(escritor, 502, f"O proxy do Dipsy não conseguiu ligar a {host}:{porta} ({type(e).__name__}).")
            registar(metodo=info["metodo"], dominio=host.lower(), porta=porta, categoria=categoria, decisao="falhou",
                     motivo=type(e).__name__, enviados=0, recebidos=0, ms=int((time.time() - inicio) * 1000))
            return
        if info["metodo"] == "CONNECT":
            escritor.write(b"HTTP/1.1 200 Connection Established\r\nX-Dipsy-Proxy: registado\r\n\r\n")
            await escritor.drain()
        else:
            up_escritor.write(resto)
            await up_escritor.drain()
            cont["enviados"] += len(resto)
        cortado = {"sim": False}

        def cortar():
            cortado["sim"] = True
        limite = rede.LIMITE_SO_LEITURA if so_leitura else None
        await asyncio.gather(
            _bombear(leitor, up_escritor, cont, "enviados", limite, cortar),
            _bombear(up_leitor, escritor, cont, "recebidos"),
        )
        registar(metodo=info["metodo"], dominio=host.lower(), porta=porta, categoria=categoria,
                 decisao="cortado-upload" if cortado["sim"] else "permitido",
                 motivo="mais de 1 MB para fora numa categoria só de leitura" if cortado["sim"] else "",
                 caminho=caminho, dns=via_dns, enviados=cont["enviados"], recebidos=cont["recebidos"],
                 ms=int((time.time() - inicio) * 1000))
    except (asyncio.IncompleteReadError, asyncio.TimeoutError, ConnectionError):
        pass
    except Exception as e:
        log(f"erro a tratar {info}: {type(e).__name__}: {str(e)[:120]}")
    finally:
        try:
            escritor.close()
        except Exception:
            pass


def estado():
    vivo = False
    try:
        with socket.create_connection((ENDERECO, PORTA), timeout=2):
            vivo = True
    except OSError:
        pass
    print(f"proxy {'VIVO' if vivo else 'PARADO'} em {ENDERECO}:{PORTA}")
    try:
        with open(rede.REGISTO, encoding="utf-8") as f:
            ultimas = f.readlines()[-5:]
        for l in ultimas:
            print(l.rstrip())
    except FileNotFoundError:
        print("(registo vazio)")


async def principal():
    rede.compilar(rede.carregar())
    try:
        servidor = await asyncio.start_server(tratar, ENDERECO, PORTA, reuse_address=False)
    except OSError:
        print("O proxy do Dipsy já está a correr.")
        return
    log(f"proxy a ouvir em {ENDERECO}:{PORTA} (pid {os.getpid()})")
    with open(os.path.join(rede.PASTA_PROXY, "proxy.pid"), "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
    async with servidor:
        while True:
            await asyncio.sleep(30)
            try:
                rede.carregar()          # recompila politica.json se a lista mudou
            except Exception:
                pass


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--estado":
        estado()
    else:
        try:
            asyncio.run(principal())
        except KeyboardInterrupt:
            pass
