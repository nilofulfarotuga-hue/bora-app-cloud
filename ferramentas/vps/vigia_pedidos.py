#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
vigia_pedidos.py — Hermes vigia o delivery e avisa o Danilo no Telegram (adendo 1 E, 29/10/2026).

So LE (REST com a chave de servidor; nenhum UPDATE). Corre de 10 em 10 min por /etc/cron.d/bora-vigia-pedidos.
Avisa SO quando o estado muda (ficheiro de estado), e avisa tambem quando volta ao normal.

O que vigia:
  1. site publico https://app.boraguarda.com responde 200;
  2. a API (rest/v1) responde 200;
  3. pedidos PRESOS: criado/na loja/a chamar estafeta ha mais de 25 min (sem is_test_order);
  4. zero pedidos numa hora de pico (12-14, 19-22 Lisboa) quando nos ultimos 7 dias essa hora
     teve em media >= 1 pedido (com o volume de hoje, so avisa se for mesmo anormal).

Uso: python3 vigia_pedidos.py            (ciclo normal; avisa no Telegram se mudou)
     python3 vigia_pedidos.py --seco     (ciclo em seco: imprime, nao grava estado nem avisa)

Segredos: nunca aqui. Le-se do ficheiro .env de cada servico pelo caminho abaixo (sao CAMINHOS,
nao chaves).
"""
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.request
import zoneinfo

CAMINHO_FICHEIRO_ENV_HERMES = "/docker/hermes-agent-fvnc/data/.env"
CAMINHO_FICHEIRO_ENV_ASSISTENTE = "/opt/assistente-negocio/.env"
ESTADO = "/opt/data/rotinas/vigia_pedidos.estado.json"
LOG = "/var/log/vigia-pedidos.log"
GRITAR = "/opt/data/scripts/gritar.sh"
LISBOA = zoneinfo.ZoneInfo("Europe/Lisbon")
PICO = [(12, 14), (19, 22)]
SECO = "--seco" in sys.argv


def ler_variavel_do_env(caminho_ficheiro, nome_variavel):
    try:
        with open(caminho_ficheiro, encoding="utf-8") as f:
            for linha in f:
                if linha.startswith(nome_variavel + "="):
                    return linha.split("=", 1)[1].strip().strip('"').strip("'")
    except OSError:
        pass
    return ""


def log(msg):
    linha = f"[{dt.datetime.now(dt.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}] {msg}"
    if SECO:
        print(linha)
        return
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(linha + "\n")


def http_get(url, headers=None, timeout=15):
    # Sem User-Agent de navegador o Cloudflare do site responde 403 ao Python (visto 29/10 na VPS).
    h = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) BoraVigia/1.0"}
    h.update(headers or {})
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception as e:  # noqa: BLE001
        return 0, str(e).encode()


def main():
    url = ler_variavel_do_env(CAMINHO_FICHEIRO_ENV_HERMES, "SUPABASE_URL") or ler_variavel_do_env(
        CAMINHO_FICHEIRO_ENV_ASSISTENTE, "SUPABASE_URL")
    chave_servidor = ler_variavel_do_env(CAMINHO_FICHEIRO_ENV_ASSISTENTE, "SUPABASE_SERVICE_ROLE_KEY")
    if not url or not chave_servidor:
        log("sem SUPABASE_URL ou chave de servidor no .env — saio")
        return 0
    h = {"apikey": chave_servidor, "Authorization": f"Bearer {chave_servidor}"}
    agora = dt.datetime.now(dt.timezone.utc)
    problemas = []

    st, _ = http_get("https://app.boraguarda.com/", timeout=20)
    if st != 200:
        problemas.append(f"site app.boraguarda.com responde {st or 'nada'}")

    st, corpo = http_get(f"{url}/rest/v1/orders?select=id&limit=1", h)
    if st != 200:
        problemas.append(f"API da base responde {st or 'nada'}")
    else:
        limite = (agora - dt.timedelta(minutes=25)).isoformat()
        st2, corpo2 = http_get(
            f"{url}/rest/v1/orders?select=id,status,created_at,vendor_name"
            f"&status=in.(created,preparing,callingDriver)&is_test_order=eq.false&created_at=lt.{limite}"
            "&order=created_at.asc&limit=10", h)
        if st2 == 200:
            presos = json.loads(corpo2 or b"[]")
            for p in presos:
                minutos = int((agora - dt.datetime.fromisoformat(p["created_at"].replace("Z", "+00:00"))).total_seconds() // 60)
                problemas.append(f"pedido {p['id'][:8]} ({p.get('vendor_name') or 'loja'}) preso em '{p['status']}' ha {minutos} min")

        local = agora.astimezone(LISBOA)
        hora = local.hour
        if any(a <= hora < b for a, b in PICO):
            desde7 = (agora - dt.timedelta(days=7)).isoformat()
            st3, corpo3 = http_get(
                f"{url}/rest/v1/orders?select=created_at&is_test_order=eq.false&created_at=gte.{desde7}&limit=2000", h)
            if st3 == 200:
                ts = [dt.datetime.fromisoformat(x["created_at"].replace("Z", "+00:00")).astimezone(LISBOA)
                      for x in json.loads(corpo3 or b"[]")]
                mesma_hora_7d = sum(1 for t in ts if t.hour == hora and t.date() != local.date())
                inicio_hora = local.replace(minute=0, second=0, microsecond=0)
                hoje_esta_hora = sum(1 for t in ts if t >= inicio_hora)
                if mesma_hora_7d / 7.0 >= 1.0 and hoje_esta_hora == 0 and local.minute >= 50:
                    problemas.append(f"0 pedidos entre as {hora}h e as {hora + 1}h (media dos ultimos 7 dias: {mesma_hora_7d / 7.0:.1f})")

    estado_antigo = {}
    try:
        with open(ESTADO, encoding="utf-8") as f:
            estado_antigo = json.load(f)
    except (OSError, ValueError):
        pass
    chave_estado = "|".join(sorted(problemas))
    mudou = chave_estado != estado_antigo.get("chave", "")
    log(f"problemas={len(problemas)} mudou={mudou} :: {chave_estado[:300]}")
    if SECO:
        print(f"[seco] texto que iria para o Telegram: "
              + ("Vigia do Bora: " + "; ".join(problemas[:5]) + "." if problemas else "Vigia do Bora: voltou tudo ao normal."))
        return 0
    if mudou:
        if problemas:
            texto = "Vigia do Bora: " + "; ".join(problemas[:5]) + "."
        else:
            texto = "Vigia do Bora: voltou tudo ao normal."
        if os.path.exists(GRITAR):
            try:
                subprocess.run(["bash", GRITAR, texto], check=False, timeout=40)
                log("telegram enviado")
            except Exception as e:  # noqa: BLE001
                log(f"telegram falhou: {e}")
        with open(ESTADO, "w", encoding="utf-8") as f:
            json.dump({"chave": chave_estado, "quando": agora.isoformat()}, f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
