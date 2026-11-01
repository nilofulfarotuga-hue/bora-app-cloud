#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""grupos_plano.py -- o plano do dia para os grupos de Facebook.

Escrito 2026-09-06, ordem "melhorias a maquina dos grupos". Substitui o bloco de
Python que vivia dentro do social-grupos-plano.sh.

NAO PUBLICA NADA. Corre num contentor sem navegador; o que faz e' escolher, e
deixar o plano pronto para uma sessao com o Facebook do Danilo aberto.

O QUE MUDOU EM RELACAO A VERSAO ANTERIOR
  - 4 a 6 grupos por dia em vez de 2 a 3 (com trava de seguranca, ver abaixo);
  - cada grupo e' CLIENTE ou NEGOCIO e recebe a peca da sua familia; nunca se
    mistura;
  - o par (foto, texto) nunca se repete no mesmo grupo enquanto houver pares por
    usar, e fica registado quem saiu onde;
  - so entram grupos cujo assunto e' a Guarda (area_ok);
  - cada publicacao leva a sua marcacao de origem, qr-grupo-<slug>, para se
    poder medir depois qual o grupo que trouxe gente;
  - as horas vem espalhadas entre as 11h e as 21h, com pelo menos 20 minutos
    entre publicacoes e hora de arranque sorteada.

A TRAVA DE SEGURANCA
  Se o Facebook der um aviso, uma restricao ou apagar uma publicacao, quem estiver
  a publicar cria o ficheiro grupos/PARAGEM-AAAA-MM-DD com o motivo dentro.
  - PARAGEM de hoje  -> o plano de hoje nao sai, e diz-se porque.
  - PARAGEM de ontem -> hoje anda a metade do ritmo (3 grupos).

CONSTANCIA
  Publica-se todos os dias. Quando nao ha grupo elegivel, o plano sai na mesma a
  dizer QUAL e a razao -- nunca fica em silencio.

USO
  grupos_plano.py [--data AAAA-MM-DD] [--saida ficheiro.txt] [--seco]
"""
import argparse
import json
import os
import random
import sys
from datetime import date, datetime, timedelta

RAIZ = "/opt/data/social"
PASTA = os.path.join(RAIZ, "grupos")
ESTADO = os.path.join(RAIZ, "grupos-estado.json")
BIBLIOTECA = os.path.join(PASTA, "biblioteca.json")
REGISTO = os.path.join(PASTA, "registo.json")

PRIMEIRA_HORA = 11          # nunca antes das 11:00
ULTIMA_HORA = 21            # nunca depois das 21:00
MIN_INTERVALO = 20          # minimo entre publicacoes; nao ha maximo
LINK_BASE = "https://boraguarda.com/baixar?de=%s"


def carregar(caminho, por_defeito):
    if not os.path.exists(caminho):
        return por_defeito
    with open(caminho, encoding="utf-8") as f:
        return json.load(f)


def dias_desde(iso, hoje):
    if not iso:
        return 9999
    try:
        return (hoje - date.fromisoformat(iso)).days
    except ValueError:
        return 9999


def paragem(dia):
    caminho = os.path.join(PASTA, "PARAGEM-%s" % dia.isoformat())
    if os.path.exists(caminho):
        motivo = open(caminho, encoding="utf-8").read().strip()
        return motivo or "sem motivo escrito"
    return None


def escolher_par(familia, usados, rnd):
    """Escolhe (foto, texto) da familia, evitando pares ja usados NESTE grupo.

    `usados` e' o conjunto de "categoria|foto|texto" que ja sairam neste grupo.
    Quando ja saiu tudo, volta ao par mais antigo -- mas isso so acontece depois
    de 9 publicacoes no mesmo grupo, ou seja passadas nove semanas.
    """
    todos = []
    for categoria, dados in sorted(familia.items()):
        for foto in dados["fotos"]:
            for texto in dados["textos"]:
                todos.append((categoria, foto, texto))
    # Regra das lojas permitidas (2026-10-27): texto que fala de uma loja
    # fechada/excluida (ou base sem resposta) nao entra no plano.
    import lojas_permitidas as lp
    todos = [t for t in todos
             if lp.verificar_texto("%s %s" % (t[2].get("titulo", ""), t[2].get("corpo", "")))[0] == lp.OK]
    # B8 (2026-11-01, stories-em-breve): a FOTO tambem passa pela regra -- foto
    # de loja em breve/inativa/excluida (logo de parceiro colado incluido) nao
    # entra. E a categoria "barbearia" so entra se houver pelo menos uma
    # barbearia permitida (hoje estao todas em breve: anunciar "barbearias na
    # app" seria anunciar lojas em breve). Base sem resposta: barbearia fora.
    def _foto_ok(foto):
        dono = lp.dono_da_foto(foto)
        return dono in (None, "generica") or lp.verificar(dono)[0] == lp.OK
    try:
        ha_barbearia = any(v["permitida"] and v.get("categoria") == "barbershop"
                           for v in lp.lojas_vivas().values())
    except lp.SemResposta:
        ha_barbearia = False
    todos = [t for t in todos
             if _foto_ok(t[1]) and (t[0] != "barbearia" or ha_barbearia)]
    if not todos:
        raise SystemExit("ERRO: nenhuma peca passou na regra das lojas permitidas")
    livres = [t for t in todos
              if "%s|%s|%s" % (t[0], t[1], t[2]["id"]) not in usados]
    pool = livres or todos
    return rnd.choice(pool), bool(livres)


def horas_do_dia(n, rnd):
    """n horas sorteadas entre as 11h e as 21h, nunca a menos de 20 minutos.

    Regra do Danilo (06/09, a segunda versao, que e a que manda): 4 a 6
    publicacoes por dia, espalhadas entre as 11h e as 21h, com PELO MENOS 20
    minutos entre elas e hora de arranque sorteada. Nao ha maximo de espacamento.

    Como se faz: sorteiam-se n horas na janela, ordenam-se, e depois AFASTAM-SE
    as que ficaram coladas -- primeiro empurrando para a frente, e se a ultima
    passar das 21h, puxando tudo para tras. Com 6 publicacoes o minimo ocupa 100
    dos 600 minutos da janela, por isso ha sempre espaco.
    """
    if n <= 0:
        return []
    janela = (ULTIMA_HORA - PRIMEIRA_HORA) * 60
    if MIN_INTERVALO * (n - 1) > janela:
        raise SystemExit("ERRO: %d publicacoes a %d minutos nao cabem entre as %dh "
                         "e as %dh" % (n, MIN_INTERVALO, PRIMEIRA_HORA, ULTIMA_HORA))

    t = sorted(rnd.randint(0, janela) for _ in range(n))
    for i in range(1, n):                      # afasta para a frente
        if t[i] - t[i - 1] < MIN_INTERVALO:
            t[i] = t[i - 1] + MIN_INTERVALO
    if t[-1] > janela:                         # transbordou: puxa tudo para tras
        atraso = t[-1] - janela
        t = [x - atraso for x in t]
        for i in range(n - 2, -1, -1):
            if t[i + 1] - t[i] < MIN_INTERVALO:
                t[i] = t[i + 1] - MIN_INTERVALO
        if t[0] < 0:                           # nao devia acontecer; se acontecer, encosta
            t = [i * MIN_INTERVALO for i in range(n)]

    base = PRIMEIRA_HORA * 60
    return ["%02d:%02d" % ((base + x) // 60, (base + x) % 60) for x in t]


def ritmo_pela_fila(n_fila, min_dias):
    """Quantas publicacoes por dia, em funcao do tamanho da fila de grupos.

    Ordem do Danilo (2026-09-06): para publicar mais por dia aumenta-se o NUMERO
    DE GRUPOS, nao a frequencia por grupo. Deu duas ancoras -- 14 grupos = 4 a 6
    por dia, 30 grupos = 8 a 10 -- e a recta que passa nas duas e
    min = 0.25n + 0.5, max = 0.25n + 2.5.

    O ritmo pedido e esse, e e esse que se usa. Quem garante a seguranca nao e
    este numero: e o filtro de elegibilidade, que so deixa entrar um grupo que
    nao publica ha `min_dias`. Por isso pedir 6 quando so ha 2 elegiveis nao
    quebra regra nenhuma -- saem 2.

    O que ESTE calculo tambem devolve e o ritmo SUSTENTAVEL a longo prazo,
    n / min_dias, porque e a conta que o Danilo tem de ver: com 30 grupos e uma
    publicacao por grupo por semana, o regime da 4 por dia, nao 8 a 10. Para 8 a
    10 em regime seriam precisos 56 a 70 grupos. Isto diz-se, nao se esconde.
    """
    pedido_min = max(1, int(round(0.25 * n_fila + 0.5)))
    pedido_max = max(pedido_min, int(round(0.25 * n_fila + 2.5)))
    sustentavel = n_fila / float(min_dias) if min_dias else 0.0
    return pedido_min, pedido_max, sustentavel


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=None)
    ap.add_argument("--saida", default=None)
    ap.add_argument("--seco", action="store_true",
                    help="nao grava o registo, so mostra o plano")
    a = ap.parse_args()

    hoje = date.fromisoformat(a.data) if a.data else date.today()
    rnd = random.Random("bora-grupos-" + hoje.isoformat())

    estado = carregar(ESTADO, {})
    biblioteca = carregar(BIBLIOTECA, {})
    registo = carregar(REGISTO, {"publicacoes": [], "_comentario":
                                 "Cada linha e uma publicacao planeada ou feita. "
                                 "estado: planeado|feito|falhou."})
    if not estado or not biblioteca:
        raise SystemExit("ERRO: falta grupos-estado.json ou grupos/biblioteca.json")

    tectos = estado.get("tectos", {})
    min_dias = tectos.get("max_publicacoes_por_grupo_por_dias", 7)

    linhas = ["Plano de grupos do Facebook — %s" % hoje.isoformat(), ""]

    trava_hoje = paragem(hoje)
    if trava_hoje:
        linhas.append("PARADO HOJE. O Facebook deu sinal e a maquina esta travada.")
        linhas.append("Motivo escrito: %s" % trava_hoje)
        linhas.append("Nao se publica nada hoje. Amanha volta a metade do ritmo.")
        saida = "\n".join(linhas) + "\n"
        print(saida)
        if a.saida:
            open(a.saida, "w", encoding="utf-8").write(saida)
        return 0

    trava_ontem = paragem(hoje - timedelta(days=1))
    if trava_ontem:
        linhas.append("RITMO A METADE hoje (maximo %d grupos): ontem houve travagem."
                      % tectos.get("ritmo_reduzido_max_grupos", 3))
        linhas.append("Motivo de ontem: %s" % trava_ontem)
        linhas.append("")

    # --------------------------------------------------------------- elegiveis
    recusados = []
    elegiveis = []
    for g in estado.get("grupos", []):
        if g.get("proibido"):
            recusados.append((g.get("nome"), "vetado pelas regras do grupo"))
            continue
        if not g.get("joined"):
            recusados.append((g.get("nome"), "ainda nao aceitaram a entrada"))
            continue
        if not g.get("allows_posting"):
            recusados.append((g.get("nome"), "nao deixa publicar (ou por confirmar)"))
            continue
        if not g.get("area_ok", True):
            recusados.append((g.get("nome"), g.get("area_motivo", "fora da area")))
            continue
        d = dias_desde(g.get("last_published"), hoje)
        if d < min_dias:
            recusados.append((g.get("nome"), "publicou ha %d dias (a regra e 7)" % d))
            continue
        elegiveis.append(g)

    # o ritmo sai do tamanho da FILA, nao de um numero fixo
    n_fila = sum(1 for g in estado.get("grupos", [])
                 if g.get("joined") and g.get("allows_posting")
                 and not g.get("proibido") and g.get("area_ok", True))
    min_grupos, max_grupos, sustentavel = ritmo_pela_fila(n_fila, min_dias)
    if trava_ontem:
        max_grupos = min(max_grupos, tectos.get("ritmo_reduzido_max_grupos", 3))
        min_grupos = min(min_grupos, max_grupos)
    linhas.append("FILA: %d grupos na maquina | elegiveis hoje: %d | ritmo pedido: "
                  "%d a %d" % (n_fila, len(elegiveis), min_grupos, max_grupos))
    linhas.append("Ritmo sustentavel com uma publicacao por grupo a cada %d dias: "
                  "%.1f por dia. Para %d por dia em regime seriam precisos %d grupos."
                  % (min_dias, sustentavel, max_grupos, max_grupos * min_dias))
    linhas.append("")

    elegiveis.sort(key=lambda g: (-dias_desde(g.get("last_published"), hoje),
                                  -(g.get("membros") or 0)))
    escolhidos = elegiveis[:max_grupos]

    # Os dois publicos andam juntos: se houver grupo de negocio elegivel e nenhum
    # tiver entrado, entra um a trocar pelo ultimo da lista. A angariacao de
    # parceiros nao pode ficar semanas atras da captacao de clientes so porque os
    # grupos de compra e venda sao mais e maiores.
    if escolhidos and not any(g.get("publico") == "negocio" for g in escolhidos):
        for g in elegiveis:
            if g.get("publico") == "negocio":
                escolhidos[-1] = g
                break

    if not escolhidos:
        linhas.append("Nao ha nenhum grupo elegivel hoje. As razoes, grupo a grupo:")
        for nome, motivo in recusados:
            linhas.append("  - %s: %s" % (nome, motivo))
        linhas.append("")
        linhas.append("Isto quebra a regra de publicar todos os dias, e a razao esta "
                      "acima. O caminho e entrar em mais grupos da Guarda "
                      "(ate %d pedidos por dia)." % tectos.get("max_entradas_por_dia", 8))
        saida = "\n".join(linhas) + "\n"
        print(saida)
        if a.saida:
            open(a.saida, "w", encoding="utf-8").write(saida)
        return 0

    if len(escolhidos) < min_grupos:
        linhas.append("Aviso: so ha %d grupos elegiveis, e o alvo do dia sao %d."
                      % (len(escolhidos), min_grupos))
        linhas.append("Falta entrar em mais grupos da Guarda. Razoes dos que ficaram de fora:")
        for nome, motivo in recusados[:8]:
            linhas.append("  - %s: %s" % (nome, motivo))
        linhas.append("")

    # --------------------------------------------------------------- os pares
    horas = horas_do_dia(len(escolhidos), rnd)
    ja = {}
    for p in registo.get("publicacoes", []):
        ja.setdefault(p["grupo"], set()).add(
            "%s|%s|%s" % (p.get("categoria"), p.get("foto"), p.get("texto")))

    categorias_hoje = set()
    novas = []
    linhas.append("%d publicacoes hoje, espalhadas pelo dia:" % len(escolhidos))
    linhas.append("")
    for i, g in enumerate(escolhidos):
        publico = g.get("publico", "cliente")
        familia = biblioteca.get(publico, {})
        if not familia:
            linhas.append("%d. %s — SEM PECAS para o publico %s" % (i + 1, g["nome"], publico))
            continue

        # tenta nao repetir categoria no mesmo dia
        par, era_novo = escolher_par(familia, ja.get(g["id"], set()), rnd)
        for _ in range(6):
            if par[0] not in categorias_hoje:
                break
            par, era_novo = escolher_par(familia, ja.get(g["id"], set()), rnd)
        categorias_hoje.add(par[0])
        categoria, foto, texto = par

        origem = g.get("origem", "qr-grupo-" + g["id"])
        corpo = texto["corpo"].replace("{LINK}", LINK_BASE % origem)

        linhas.append("%d. %s  (%s membros)  —  publico: %s"
                      % (i + 1, g["nome"], g.get("membros", "?"), publico.upper()))
        linhas.append("   hora sugerida: %s" % horas[i])
        linhas.append("   link do grupo: %s" % g["link"])
        linhas.append("   foto: %s" % foto)
        linhas.append("   texto %s (%s)%s:"
                      % (texto["id"], categoria, "" if era_novo else " [repetido — ja saiu tudo neste grupo]"))
        for l in corpo.splitlines():
            linhas.append("   > " + l)
        linhas.append("")

        novas.append({
            "data": hoje.isoformat(), "hora": horas[i], "grupo": g["id"],
            "grupo_nome": g["nome"], "publico": publico, "categoria": categoria,
            "foto": foto, "texto": texto["id"], "origem": origem,
            "estado": "planeado", "url": None,
        })

    linhas.append("Regras a cumprir a mao:")
    linhas.append("  - pelo menos 20 minutos entre publicacoes; se atrasares uma, "
                  "afasta a seguinte, nunca a encostes;")
    linhas.append("  - uma publicacao por grupo por semana;")
    linhas.append("  - peca de cliente nunca vai a grupo de negocio, nem ao contrario;")
    linhas.append("  - se o Facebook avisar, restringir ou apagar: PARA o dia, escreve "
                  "o motivo em grupos/PARAGEM-%s e avisa aqui." % hoje.isoformat())
    linhas.append("  - depois de publicar: grupos_registar.py --grupo <id> --url <url>")

    saida = "\n".join(linhas) + "\n"
    print(saida)
    if a.saida:
        open(a.saida, "w", encoding="utf-8").write(saida)

    if not a.seco:
        registo.setdefault("publicacoes", [])
        registo["publicacoes"] = [p for p in registo["publicacoes"]
                                  if not (p["data"] == hoje.isoformat()
                                          and p["estado"] == "planeado")]
        registo["publicacoes"].extend(novas)
        os.makedirs(PASTA, exist_ok=True)
        with open(REGISTO, "w", encoding="utf-8") as f:
            json.dump(registo, f, ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
