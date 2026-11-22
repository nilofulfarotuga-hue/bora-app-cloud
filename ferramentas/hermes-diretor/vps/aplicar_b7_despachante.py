#!/usr/bin/env python3
"""Remendo do despachante do Hermes (missao hermes-diretor-2026-11-20, blocos B5 e B7). Corre NO HOST da VPS, como root.

O que muda em /opt/data/rotinas/despachante.py e emerson.py:
  1. Agente "desligado" deixa de falhar: o despachante acorda-o para a tarefa. So nao corre quem esta
     ARQUIVADO (faz o substituto) ou BLOQUEADO (so o Danilo liga). Enquanto as colunas novas
     (agentes_estado.arquivado/substituto) nao estiverem aplicadas, le-se a marca no campo `nota`.
  2. "Nenhum bot serve" deixa de fechar a tarefa com uma frase: faz o proprio diretor (perfil principal).
  3. O fiscal confere a prova, com contexto limpo, antes de a tarefa ficar "feita". Prova que nao bate
     volta ao mesmo agente (2 vezes); a 3.a vai ao emerson como evento urgente.
  4. "a-espera-do-danilo" so quando o AGENTE escreve "PRECISA DO AUTORIZO: ..." (dinheiro ou apagar).
     Acabou a lista de palavras (publicar, enviar, mandar...) que punha la tarefas que nao eram dele.
  5. O Danilo so recebe aviso de: pedido de autorizo, resultado do que ELE pediu, evento automatico,
     e falha do que ele ou a Claude.ai pediram. O resto fica no registo.

Uso:  python3 aplicar_b7_despachante.py --ensaio   (mostra o que mudaria; nao escreve)
      python3 aplicar_b7_despachante.py            (faz copia .bak-20261122, escreve e compila)
Idempotente: se ja estiver aplicado, nao faz nada."""
import io, os, py_compile, re, shutil, sys

PASTA = "/opt/data/rotinas"
ENSAIO = "--ensaio" in sys.argv
MARCA = "hermes-diretor-2026-11-20"


def trocar(texto, velho, novo, nome, n=1):
    c = texto.count(velho)
    if c != n:
        raise SystemExit("PARO: esperava %d ocorrencia(s) de [%s], encontrei %d" % (n, nome, c))
    return texto.replace(velho, novo)


# ───────────────────────────── despachante.py ─────────────────────────────
D_ESTA_LIGADO_VELHO = '''def esta_ligado(bot):
    """O interruptor do painel admin manda. Se nao der para ler, deixa passar (nao travar por duvida)."""
    r = _rest("agentes_estado?select=ligado&agente=eq." + bot)
    if not r:
        return True
    return bool(r[0].get("ligado", True))
'''
D_ESTA_LIGADO_NOVO = '''_COLUNAS_NOVAS = [True]   # agentes_estado.arquivado/substituto (hermes-diretor-2026-11-20); False se ainda nao existem


def estado_agente(bot):
    """Tres estados (hermes-diretor-2026-11-20): 'ativo' (relogio ou a pedido: pode ser acordado para uma
    tarefa mesmo com o interruptor desligado), 'arquivado' (faz o substituto) e 'bloqueado' (so o Danilo
    liga). Devolve (estado, substituto). Se nao der para ler, deixa passar (nao travar por duvida)."""
    import re as _re
    r = None
    if _COLUNAS_NOVAS[0]:
        r = _rest("agentes_estado?select=ligado,nota,arquivado,substituto&agente=eq." + bot)
        if r is None:
            _COLUNAS_NOVAS[0] = False
    if r is None:
        r = _rest("agentes_estado?select=ligado,nota&agente=eq." + bot)
    if not r:
        return "ativo", None
    linha = r[0]
    nota = (linha.get("nota") or "").strip()
    if nota.upper().startswith("BLOQUEADO"):
        return "bloqueado", None
    if linha.get("arquivado") or nota.upper().startswith("ARQUIVADO"):
        m = _re.search(r"substituto\\s*=\\s*([a-z0-9-]+)", nota, _re.I)
        return "arquivado", (linha.get("substituto") or (m.group(1) if m else None))
    return "ativo", None


def esta_ligado(bot):
    """Compatibilidade: so NAO se invoca quem esta arquivado ou bloqueado (desligado acorda-se)."""
    return estado_agente(bot)[0] == "ativo"
'''

D_GUIAO_VELHO = '''    guiao = 'cd /opt/data && exec hermes -p "$1" --provider custom -z "$2"'
'''
D_GUIAO_NOVO = '''    if bot == "emerson":
        # o diretor em pessoa (perfil principal): quando nenhum agente serve, faz ele, a serio
        guiao = 'cd /opt/data && exec hermes -z "$2"'
    else:
        guiao = 'cd /opt/data && exec hermes -p "$1" --provider custom -z "$2"'
'''

D_DESPACHAR_VELHO = '''    if not bot:
        return {"bot": None, "porque": porque,
                "resposta": "Nenhum bot serve para isto. Respondo eu, o Emerson."}
    if not esta_ligado(bot):
        return {"bot": bot, "porque": porque, "desligado": True,
                "resposta": "O %s esta DESLIGADO no painel admin. Nao o invoquei." % bot}
'''
D_DESPACHAR_NOVO = '''    if bot:
        est, subst = estado_agente(bot)
        if est == "bloqueado":
            return {"bot": bot, "porque": porque, "desligado": True,
                    "resposta": "O %s esta BLOQUEADO: so o Danilo o liga. Nao o invoquei." % bot}
        if est == "arquivado":
            registar(evento="arquivado", bot=bot, substituto=subst)
            tem_perfil = bool(subst) and os.path.isfile(os.path.join(PERFIS, subst, "SOUL.md"))
            bot = subst if (tem_perfil and subst != "emerson") else None
    if not bot:
        # ninguem serve (ou o substituto e o diretor): faz o proprio Hermes, a serio (hermes-diretor-2026-11-20)
        bot = "emerson"
        porque = ((porque or "") + " | sem agente: faz o diretor").strip(" |")
'''

# ───────────────────────────── emerson.py ─────────────────────────────
E_PORTAO_NOVO = '''# 22/11/2026 (missao hermes-diretor-2026-11-20, ordem do Danilo de 20/11): so DUAS coisas esperam por
# ele — DINHEIRO e APAGAR. Publicar, enviar, mandar, submeter e cancelar deixaram de esperar. E quem diz
# que precisa do autorizo e o AGENTE, na resposta (linha "PRECISA DO AUTORIZO: ..."), nao uma palavra solta
# no texto da tarefa: texto nao e comando (a 22/11 havia 24 tarefas "a espera do Danilo" e so 1 era dele).
PEDE_AUTORIZO = re.compile(r"^[^A-Za-z\\n]{0,6}PRECISA DO AUTORIZO\\b[:\\s-]*(.{0,300})", re.I | re.M)
SO_LEITURA = re.compile(r"\\bs[o\\u00f3]\\s+leitura\\b", re.I)


def precisa_do_danilo(resultado):
    """Devolve o pedido (texto) quando o agente parou a pedir o autorizo do Danilo; senao None."""
    m = PEDE_AUTORIZO.search(resultado or "")
    return (m.group(1).strip() or "sem descricao") if m else None


def precisa_de_fiscal(linha):
    """Tarefa que muda alguma coisa: tudo menos as rondas do relogio, o que se declara so de leitura e o
    trabalho do proprio fiscal."""
    if linha.get("origem") == "relogio" or linha.get("para") == "fiscal":
        return False
    if linha.get("precisa_auditoria") is True:
        return True
    return not SO_LEITURA.search(linha.get("tarefa") or "")


def fiscalizar(id_, titulo, tarefa, resultado, prova):
    """O fiscal REFAZ a prova com contexto limpo: so recebe a tarefa, o resultado e a prova.
    Devolve (True|False|None, nota). None = o fiscal nao deu veredicto (nao trava a casa)."""
    pedido = ("AUDITORIA da tarefa %d do despacho. Recebes SO a tarefa, o resultado e a prova; nao tens o "
              "raciocinio de quem fez.\\nREFAZ a prova tu proprio (le o ficheiro, corre o comando de leitura, "
              "abre o endereco) e so depois decide. Sem prova refeita por ti, e FALHOU.\\n"
              "Responde com a PRIMEIRA linha exatamente 'AUDITORIA: OK' ou 'AUDITORIA: FALHOU' e a seguir 1 a 3 "
              "linhas: o que conferiste, como, e o que falta.\\n\\nTITULO: %s\\n\\nTAREFA:\\n%s\\n\\n"
              "RESULTADO DE QUEM FEZ:\\n%s\\n\\nPROVA DE QUEM FEZ:\\n%s"
              % (id_, titulo, (tarefa or "")[:3000], (resultado or "")[:2500], (prova or "")[:800]))
    t1 = time.time()
    ok, saida, rc = D.invocar("fiscal", pedido, 240)
    D.guardar_corrida("fiscal", "emerson", pedido[:600], ok, int((time.time() - t1) * 1000),
                      saida if ok else "", None if ok else saida[:1000], despacho_id=id_)
    if not ok:
        return None, "o fiscal nao respondeu: %s" % (saida or "")[:200]
    m = re.search(r"AUDITORIA:\\s*(OK|FALHOU)", saida, re.I)
    if not m:
        return None, "o fiscal respondeu sem veredicto: %s" % saida[:200]
    return m.group(1).upper() == "OK", saida.strip()[:700]


_COLUNAS_AUDITORIA = [True]   # despacho.auditada/auditoria_nota/... ; False se ainda nao existem


def gravar_auditoria(id_, campos):
    """Grava nas colunas novas do despacho, se ja existirem. Nunca rebenta."""
    if not _COLUNAS_AUDITORIA[0]:
        return
    if rest("despacho?id=eq.%d" % id_, "PATCH", campos) is None:
        _COLUNAS_AUDITORIA[0] = False

'''

E_VIVOS_VELHO = '''    r = rest("agentes_estado?select=agente,ligado") or []
    ligados = {x["agente"] for x in r if x.get("ligado")}
    vivos = sorted(emdisco & ligados) if ligados else sorted(emdisco)
    return vivos or sorted(emdisco)
'''
E_VIVOS_NOVO = '''    # 22/11 (hermes-diretor): "desligado" ja nao tira ninguem da lista — o despachante acorda-o para a
    # tarefa. So ficam de fora os ARQUIVADOS (faz o substituto) e os BLOQUEADOS (so o Danilo liga).
    r = rest("agentes_estado?select=agente,nota,arquivado")
    if r is None:
        r = rest("agentes_estado?select=agente,nota") or []
    fora = {x["agente"] for x in r
            if x.get("arquivado") or (x.get("nota") or "").strip().upper().startswith(("ARQUIVADO", "BLOQUEADO"))}
    vivos = sorted(emdisco - fora)
    return vivos or sorted(emdisco)
'''

E_PARA_VELHO = '''        subs = [{"agente": linha.get("para") if linha.get("para") in vivos else None,
                 "tarefa": tarefa, "estado": "aberta", "prova": None}]
'''
E_PARA_NOVO = '''        para = linha.get("para")
        if para and para not in vivos:
            est_p, subst_p = D.estado_agente(para)
            para = subst_p if (est_p == "arquivado" and subst_p in vivos) else None
        subs = [{"agente": para, "tarefa": tarefa, "estado": "aberta", "prova": None}]
'''

E_LIGADO_VELHO = '''            if not D.esta_ligado(s["agente"]):
                s["estado"], s["prova"] = "saltada", "agente desligado no painel"
                continue
'''
E_LIGADO_NOVO = '''            est_a, subst_a = D.estado_agente(s["agente"])
            if est_a == "arquivado" and subst_a in vivos:
                s["agente"] = subst_a      # arquivado: faz o substituto
            elif est_a != "ativo":
                s["estado"], s["prova"] = "saltada", "agente %s: %s" % (s["agente"], est_a)
                continue
'''

E_ESTADO_VELHO = '''    if origem != "relogio" and precisa_do_danilo(tarefa):
        estado = "a-espera-do-danilo"
'''
E_ESTADO_NOVO = '''    pedido_autorizo = precisa_do_danilo(resultado) if origem != "relogio" else None
    if pedido_autorizo:
        estado = "a-espera-do-danilo"
'''

E_FECHO_VELHO = '''    else:
        estado = "feita"
    tocar(id_, {"estado": estado, "resultado": resultado,
'''
E_FECHO_NOVO = '''    else:
        estado = "feita"

    # O FISCAL (hermes-diretor-2026-11-20, B5): o que muda alguma coisa so fica "feita" depois de ele
    # refazer a prova. Nao bate -> volta ao MESMO agente com a nota (2 vezes); a 3.a vai ao emerson.
    if estado == "feita" and precisa_de_fiscal(linha) and (time.time() - t0) < 550:
        veredicto, nota_fiscal = fiscalizar(id_, titulo, tarefa, resultado, " | ".join(provas))
        vezes = len(re.findall(r"\\[FISCAL \\d/2\\]", tarefa or ""))
        registar(evento="fiscal", id=id_, veredicto=veredicto, vez=vezes + 1, nota=(nota_fiscal or "")[:200])
        if veredicto is True:
            provas.append("fiscal: OK")
            gravar_auditoria(id_, {"auditada": True, "auditada_em": "now()", "auditoria_nota": nota_fiscal[:1000]})
        elif veredicto is False and vezes < 2:
            tocar(id_, {"estado": "aberta", "iniciada_em": None, "resultado": resultado,
                        "tarefa": (tarefa or "") + "\\n[FISCAL %d/2] %s" % (vezes + 1, nota_fiscal[:500]),
                        "prova": (" | ".join(provas) + " | fiscal: FALHOU")[:2000]})
            gravar_auditoria(id_, {"auditada": False, "auditoria_nota": nota_fiscal[:1000],
                                   "auditoria_tentativas": vezes + 1})
            registar(evento="fiscal-devolveu", id=id_, vez=vezes + 1)
            return "aberta"
        elif veredicto is False:
            estado = "falhou"
            resultado = (resultado + "\\n[FISCAL] 3.a conferencia falhada: " + nota_fiscal)[:4000]
            provas.append("fiscal: FALHOU 3 vezes")
            rest("despacho", "POST", {"origem": "evento", "para": "emerson", "tipo": "tarefa", "prioridade": 90,
                                      "titulo": ("Fiscal: a tarefa %d falhou a conferencia 3 vezes" % id_)[:200],
                                      "tarefa": "A tarefa %d (%s) nao passou no fiscal 3 vezes. Ultima nota do fiscal: %s\\n"
                                                "Decide: fazes tu, passas a outro agente ou explicas ao Danilo o que falta."
                                                % (id_, titulo[:120], nota_fiscal[:600])})
            gravar_auditoria(id_, {"auditada": False, "auditoria_nota": nota_fiscal[:1000],
                                   "auditoria_tentativas": vezes + 1})
        else:
            provas.append(("fiscal: sem veredicto (%s)" % (nota_fiscal or ""))[:160])   # fiscal em baixo nao trava a casa
    tocar(id_, {"estado": estado, "resultado": resultado,
'''

E_AVISO_VELHO = '''    else:
        dep = prefixo_departamento([s.get("agente") for s in subs])
        cabeca = "[%s] Tarefa %d (%s), pedida por %s: %s." % (dep, id_, tipo, quem, titulo)
        corpo_aviso = "Estado: %s. %d passo(s)." % (estado, len(subs))
        avisar(cabeca + chr(10) + corpo_aviso + chr(10) + resultado[:600])
'''
E_AVISO_NOVO = '''    elif pedido_autorizo:
        # o unico "preciso de ti" que sobra: dinheiro ou apagar (hermes-diretor-2026-11-20)
        quem_agente = ", ".join(sorted({s.get("agente") or "emerson" for s in subs}))
        avisar("Precisas de ti: o %s pede o teu autorizo (tarefa %d). %s" % (quem_agente, id_, pedido_autorizo[:300]))
        registar(evento="avisou-autorizo", id=id_, pedido=pedido_autorizo[:200])
    elif origem in ("danilo-telegram", "evento") or (estado == "falhou" and origem == "claude-ai"):
        dep = prefixo_departamento([s.get("agente") for s in subs])
        cabeca = "[%s] Tarefa %d (%s), pedida por %s: %s." % (dep, id_, tipo, quem, titulo)
        corpo_aviso = "Estado: %s. %d passo(s)." % (estado, len(subs))
        avisar(cabeca + chr(10) + corpo_aviso + chr(10) + resultado[:600])
    else:
        # pedido por outro agente ou pela Claude.ai e correu bem: quem pediu le no despacho; o Danilo nao e incomodado
        registar(evento="aviso-calado", id=id_, porque="pedida por %s, estado %s" % (quem, estado))
'''


def remendar(nome, passos, extra=None):
    caminho = os.path.join(PASTA, nome)
    texto = io.open(caminho, encoding="utf-8").read()
    if MARCA in texto:
        print("%s: ja aplicado, nada a fazer" % nome)
        return
    for velho, novo, rotulo in passos:
        texto = trocar(texto, velho, novo, rotulo)
    if extra:
        texto = extra(texto)
    tmp = caminho + ".novo-b7"
    io.open(tmp, "w", encoding="utf-8", newline="\n").write(texto)
    py_compile.compile(tmp, doraise=True)
    if ENSAIO:
        os.remove(tmp)
        print("%s: ensaio OK (%d passos encaixam e o resultado compila)" % (nome, len(passos) + (1 if extra else 0)))
        return
    shutil.copy2(caminho, caminho + ".bak-20261122")
    st = os.stat(caminho)
    os.chmod(tmp, st.st_mode)
    os.chown(tmp, st.st_uid, st.st_gid)
    os.replace(tmp, caminho)
    print("%s: aplicado (copia em %s.bak-20261122)" % (nome, nome))


def portao(texto):
    """Troca o portao antigo (lista de palavras) pelo novo, do comentario ate ao fim de precisa_do_danilo."""
    ini = texto.index("# O portao decide pela INTENCAO")
    fim_marca = "    return bool(ACCAO_PARA_FORA.search(tarefa)) and not NEGADA.search(tarefa)\n"
    fim = texto.index(fim_marca) + len(fim_marca)
    return texto[:ini] + E_PORTAO_NOVO + texto[fim:]


def main():
    remendar("despachante.py", [
        (D_ESTA_LIGADO_VELHO, D_ESTA_LIGADO_NOVO, "esta_ligado"),
        (D_GUIAO_VELHO, D_GUIAO_NOVO, "guiao do invocar"),
        (D_DESPACHAR_VELHO, D_DESPACHAR_NOVO, "despachar: desligado/nenhum bot"),
    ])
    remendar("emerson.py", [
        (E_VIVOS_VELHO, E_VIVOS_NOVO, "agentes_vivos"),
        (E_PARA_VELHO, E_PARA_NOVO, "para direto"),
        (E_LIGADO_VELHO, E_LIGADO_NOVO, "esta_ligado no passo"),
        (E_ESTADO_VELHO, E_ESTADO_NOVO, "estado a-espera-do-danilo"),
        (E_FECHO_VELHO, E_FECHO_NOVO, "fecho com fiscal"),
        (E_AVISO_VELHO, E_AVISO_NOVO, "aviso ao Danilo"),
    ], extra=portao)


if __name__ == "__main__":
    main()
