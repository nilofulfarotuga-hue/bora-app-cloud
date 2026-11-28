"""Resumo das 21:00 para o Danilo, só pelo porteiro (texto + voz). Lê o dia de redes_*.

O comando do porteiro vem de COMUNIDADE_PORTEIRO_CMD (ex.: "python3 /opt/data/voz/porteiro_cli.py
danilo --origem comunidade-24h"); o texto vai como último argumento. Sem a variável não envia nada
e só regista (assim nunca se fala ao Danilo por fora do porteiro).
"""
import os
import shlex
import subprocess
from collections import Counter
from datetime import date, datetime, time, timezone

from comum import e2e, registo, sb_get

NOMES = {"youtube": "YouTube", "facebook": "Facebook", "instagram": "Instagram", "tiktok": "TikTok"}


def main():
    hoje = date.today()
    inicio = datetime.combine(hoje, time(0), timezone.utc).isoformat()
    st, inter = sb_get("redes_interacoes", f"select=conta,rede,tipo,estado,canal&quando=gte.{inicio}")
    st2, met = sb_get("redes_metricas", f"select=conta,rede,id_video,numeros&dia=eq.{hoje.isoformat()}&id_video=eq.")
    if st != 200 or st2 != 200:
        e2e("resumo-21h", "erro", f"leitura falhou HTTP {st}/{st2}")
        return
    respondidas = Counter(i["rede"] for i in inter if i["tipo"] == "resposta" and i["estado"] in ("publicado", "lido-de-volta"))
    chumbadas = sum(1 for i in inter if i["tipo"] == "resposta" and i["estado"] == "chumbado")
    ignoradas = sum(1 for i in inter if i["tipo"] == "comentario" and i["estado"] == "ignorado")
    lote = sum(1 for i in inter if i["canal"] == "pc-lote" and i["estado"] == "pc-lote")
    partes = []
    total = sum(respondidas.values())
    if total:
        partes.append("Hoje respondi a " + str(total) + " comentários: " +
                      ", ".join(f"{n} no {NOMES.get(r, r)}" for r, n in respondidas.items()) + ".")
    else:
        partes.append("Hoje não houve comentários novos para responder.")
    if ignoradas:
        partes.append(f"Ignorei {ignoradas} insultos ou spam.")
    if chumbadas:
        partes.append(f"O Juiz travou {chumbadas} respostas, que ficaram por publicar.")
    seg = [(m["conta"], NOMES.get(m["rede"], m["rede"]), m["numeros"].get("seguidores")) for m in met
           if m["numeros"].get("seguidores") is not None]
    if seg:
        partes.append("Seguidores hoje: " + "; ".join(f"{c} no {r}, {n}" for c, r, n in seg) + ".")
    gasto = [m["numeros"].get("gasto_eur") for m in met if m["rede"] == "meta-ads"]
    if gasto:
        partes.append("O anúncio gastou " + f"{gasto[0]:.2f}".replace(".", ",") + " euros ontem.")
    if lote:
        partes.append(f"Ficaram {lote} tarefas para o lote do computador (fixar e corações).")
    texto = " ".join(partes)
    cmd = os.environ.get("COMUNIDADE_PORTEIRO_CMD")
    if not cmd:
        e2e("resumo-21h", "sem-porteiro", "resumo feito mas não enviado (falta COMUNIDADE_PORTEIRO_CMD): " + texto)
        print(texto)
        return
    try:
        r = subprocess.run(shlex.split(cmd) + [texto], capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as e:
        e2e("resumo-21h", "erro", f"porteiro não correu ({e}): {texto}")
        return
    registo("resumo", rc=r.returncode, saida=r.stdout[-300:], erro=r.stderr[-300:])
    e2e("resumo-21h", "feito" if r.returncode == 0 else "erro",
        f"porteiro rc={r.returncode} (conferir porteiro.log.jsonl e voz.log.jsonl): {texto}")
    print(texto)


if __name__ == "__main__":
    main()
