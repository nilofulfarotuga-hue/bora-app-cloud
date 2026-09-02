# -*- coding: utf-8 -*-
"""manual.py — o manual do vault, lido POR SECCAO. E a fonte de factos: o modelo nao inventa.

O cerebro antigo colava os primeiros 2.200 caracteres do manual no prompt e mais nada -- 16% de
13.000. Agora o modelo ve o INDICE inteiro e pede a seccao que precisa com `ler_manual(tema)`.
As seccoes "Correcoes do Danilo", "Licoes" e "Perguntas novas" crescem sozinhas e entram sempre.
"""
import datetime
import os
import re
import threading
import unicodedata

CANDIDATOS = [
    r"C:\BoraLocal\Bora\MANUAL-ATENDIMENTO-BORA.md",
    "/opt/whatsapp-bora/MANUAL-ATENDIMENTO-BORA.md",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "MANUAL-ATENDIMENTO-BORA.md"),
]
MANUAL = next((p for p in CANDIDATOS if os.path.exists(p)), CANDIDATOS[0])
SEC_CORRECOES = "## CORREÇÕES DO DANILO (cresce sozinho)"
SEC_LICOES = "## LIÇÕES (auto-revisão diária)"
SEC_PERGUNTAS = "## PERGUNTAS NOVAS (sem resposta no manual)"
SEC_DANILO = "## SOBRE O DANILO"
_lock = threading.Lock()


def _sem_acentos(s):
    return "".join(c for c in unicodedata.normalize("NFD", s or "") if unicodedata.category(c) != "Mn").lower()


def texto():
    try:
        return open(MANUAL, encoding="utf-8").read()
    except OSError:
        return ""


def seccoes():
    """[(titulo, corpo)] pelas linhas '## '. O que vem antes do primeiro '## ' fica em 'INTRO'."""
    t = texto()
    partes = re.split(r"(?m)^(## .+)$", t)
    out = []
    if partes and partes[0].strip():
        out.append(("INTRO", partes[0].strip()))
    for i in range(1, len(partes) - 1, 2):
        out.append((partes[i].lstrip("# ").strip(), partes[i + 1].strip()))
    return out


def indice():
    return "\n".join("- " + t for t, _ in seccoes() if t not in ("INTRO",))


def sempre():
    """O que entra em TODAS as respostas: correcoes do Danilo, licoes, e quem e o Danilo."""
    partes = []
    for t, c in seccoes():
        tt = _sem_acentos(t)
        if "correcoes do danilo" in tt or "licoes" in tt or "sobre o danilo" in tt:
            c = c.strip()
            if c and not c.startswith("- _("):
                partes.append("### " + t + "\n" + c[:2500])
    return "\n\n".join(partes)


def ler(tema, max_chars=3800, registar=True):
    """Devolve as seccoes que mais falam do tema (titulo pesa 3x). Nunca inventa: se nao ha nada,
    diz isso mesmo e regista a pergunta nova (registar=False quando o tema e a mensagem inteira da
    pessoa, no caminho rapido -- senao cada 'obrigado' virava pergunta nova no manual)."""
    palavras = [w for w in re.findall(r"[a-z0-9]{3,}", _sem_acentos(tema)) if w not in ("que", "como", "para", "com", "uma", "the")]
    pontuadas = []
    for t, c in seccoes():
        if t == "INTRO":
            continue
        tt, cc = _sem_acentos(t), _sem_acentos(c)
        score = sum(3 for w in palavras if w in tt) + sum(min(cc.count(w), 5) for w in palavras)
        if score:
            pontuadas.append((score, t, c))
    pontuadas.sort(key=lambda x: -x[0])
    if not pontuadas:
        if registar:
            registar_pergunta_nova(tema)
        return ("NADA NO MANUAL sobre: %r. Nao inventes. Diz que vais confirmar com o Danilo e usa "
                "agendar_seguimento + avisar_danilo. Indice do manual:\n%s" % (tema, indice()))
    out, usado = [], 0
    for _s, t, c in pontuadas[:4]:
        bloco = "### %s\n%s" % (t, c)
        if usado + len(bloco) > max_chars:
            bloco = bloco[: max(0, max_chars - usado)]
        out.append(bloco)
        usado += len(bloco)
        if usado >= max_chars:
            break
    return "\n\n".join(out)


def _garantir_seccao(titulo):
    t = texto()
    if titulo not in t:
        with open(MANUAL, "a", encoding="utf-8") as f:
            f.write("\n\n" + titulo + "\n")


def _acrescentar(titulo, linha):
    with _lock:
        _garantir_seccao(titulo)
        t = texto()
        i = t.index(titulo) + len(titulo)
        j = t.find("\n## ", i)
        j = len(t) if j < 0 else j
        bloco = t[i:j].rstrip() + "\n" + linha + "\n"
        t = t[:i] + bloco + ("\n" + t[j:].lstrip("\n") if j < len(t) else "")
        open(MANUAL, "w", encoding="utf-8").write(t)


def registar_correcao(o_que, origem="danilo"):
    hoje = datetime.date.today().isoformat()
    _acrescentar(SEC_CORRECOES, "- %s (%s): %s" % (hoje, origem, (o_que or "").strip()))
    return True


def registar_licao(o_que):
    hoje = datetime.date.today().isoformat()
    _acrescentar(SEC_LICOES, "- %s: %s" % (hoje, (o_que or "").strip()))
    return True


def registar_pergunta_nova(pergunta):
    """Conta repeticoes: as que chegam a 2x sobem ao Danilo no digest."""
    p = (pergunta or "").strip()[:160]
    if not p:
        return
    with _lock:
        _garantir_seccao(SEC_PERGUNTAS)
        t = texto()
        chave = _sem_acentos(p)
        linhas = t.split("\n")
        for k, ln in enumerate(linhas):
            m = re.match(r"^- \((\d+)×\) (.*)$", ln)
            if m and _sem_acentos(m.group(2)) == chave:
                linhas[k] = "- (%d×) %s" % (int(m.group(1)) + 1, m.group(2))
                open(MANUAL, "w", encoding="utf-8").write("\n".join(linhas))
                return
    _acrescentar(SEC_PERGUNTAS, "- (1×) %s" % p)


def perguntas_repetidas(minimo=2):
    out = []
    for ln in texto().split("\n"):
        m = re.match(r"^- \((\d+)×\) (.*)$", ln)
        if m and int(m.group(1)) >= minimo:
            out.append((int(m.group(1)), m.group(2)))
    return out


if __name__ == "__main__":
    print(MANUAL, "|", len(texto()), "chars |", len(seccoes()), "seccoes")
    print(indice())
    print("---- ler('horario') ----")
    print(ler("horario")[:600])
