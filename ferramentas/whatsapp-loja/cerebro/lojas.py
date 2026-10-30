# -*- coding: utf-8 -*-
"""Horários reais das lojas, do Supabase — 04/09/2026.

Ordem do Danilo: a pergunta do horário não se responde só com "cada loja tem o seu". Responde-se
com o facto, e logo a seguir o passo: "diga-me qual a loja e digo-lhe já a que horas abre" — e
depois vai-se mesmo buscar o horário dessa loja.

`restaurants.business_hours` é um JSON por dia: {"mon": {"open": "09:00", "close": "21:00",
"closed": false}, ...}. Lê-se de 10 em 10 minutos e fica em memória (são 19 lojas).
"""
import datetime
import re
import time
import unicodedata

from . import supa

DIAS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
DIA_PT = {"mon": "segunda", "tue": "terça", "wed": "quarta", "thu": "quinta",
          "fri": "sexta", "sat": "sábado", "sun": "domingo"}
# palavras que aparecem em nomes de lojas mas não servem para identificar nenhuma
VAZIAS = {"loja", "lojas", "casa", "brasil", "bora", "the", "com", "dos", "das", "de", "do", "da",
          "e", "supermercado", "mercado", "restaurante", "cafe", "café", "sabores"}
_cache = {"quando": 0.0, "lojas": []}
CACHE_S = 600


def _sem_acentos(s):
    return "".join(c for c in unicodedata.normalize("NFD", (s or "").lower()) if unicodedata.category(c) != "Mn")


def todas(forcar=False):
    """As lojas com nome e horário. Nunca rebenta: sem rede, devolve o que tiver em cache."""
    if not forcar and time.time() - _cache["quando"] < CACHE_S and _cache["lojas"]:
        return _cache["lojas"]
    try:
        r = supa.select("restaurants", select="id,name,category,business_hours,is_online,coming_soon,address",
                        limit="300")
        _cache["lojas"] = [x for x in r if x.get("name")]
        _cache["quando"] = time.time()
    except Exception:  # noqa: BLE001
        pass
    return _cache["lojas"]


def _fichas_de_nome(nome):
    """Pedaços do nome que servem para procurar (>= 4 letras, fora as palavras vazias)."""
    pedacos = [p for p in re.split(r"[^\wçãáàâéêíóôõúü]+", _sem_acentos(nome)) if p]
    return [p for p in pedacos if len(p) >= 4 and p not in VAZIAS]


def procurar(texto):
    """A loja que a pessoa nomeou, ou None. Ganha o nome mais comprido que aparece na mensagem —
    'pingo doce' ganha a 'doce'."""
    if not texto or len(texto) < 3:
        return None
    alvo = _sem_acentos(texto)
    melhor, melhor_peso = None, 0
    for loja in todas():
        nome = _sem_acentos(loja.get("name") or "")
        if len(nome) >= 4 and nome in alvo:
            peso = len(nome) + 10                      # nome inteiro: ganha sempre a um pedaço
        else:
            achados = [p for p in _fichas_de_nome(loja.get("name") or "") if re.search(r"\b" + re.escape(p), alvo)]
            peso = max([len(p) for p in achados] or [0])
        if peso > melhor_peso:
            melhor, melhor_peso = loja, peso
    return melhor


def _dia_de_hoje():
    return DIAS[datetime.datetime.now().weekday()]


def horario_texto(loja, quando=None):
    """Uma frase curta com o horário REAL de hoje, e o passo seguinte."""
    if not loja:
        return None
    nome = loja.get("name") or "a loja"
    h = loja.get("business_hours") or {}
    dia = quando or _dia_de_hoje()
    d = h.get(dia) if isinstance(h, dict) else None
    if loja.get("coming_soon"):
        return "%s ainda não está a receber pedidos — está para abrir na app. Quer que avise quando abrir?" % nome
    if not isinstance(d, dict):
        return ("Não tenho o horário do %s à mão aqui. Na app, na página da loja, aparece sempre o horário "
                "certo e se está aberta agora. Quer que veja outra loja?" % nome)
    if d.get("closed"):
        aberto = [DIA_PT[k] for k in DIAS if isinstance(h.get(k), dict) and not h[k].get("closed")]
        extra = (" Abre %s." % ", ".join(aberto)) if aberto else ""
        return "Hoje (%s) o %s está fechado.%s Quer ver outra loja?" % (DIA_PT[dia], nome, extra)
    ab, fe = d.get("open") or "?", d.get("close") or "?"
    igual = all(isinstance(h.get(k), dict) and not h[k].get("closed")
                and h[k].get("open") == ab and h[k].get("close") == fe for k in DIAS)
    if igual:
        return "O %s abre às %s e fecha às %s, todos os dias. Quer que o ajude a fazer o pedido?" % (nome, ab, fe)
    return ("Hoje (%s) o %s abre às %s e fecha às %s. Quer que o ajude a fazer o pedido?"
            % (DIA_PT[dia], nome, ab, fe))


def sugestoes(n=5):
    """Nomes de lojas para dar exemplo quando a pessoa não diz qual."""
    nomes = [x.get("name") for x in todas() if x.get("name") and not x.get("coming_soon")]
    return nomes[:n]
