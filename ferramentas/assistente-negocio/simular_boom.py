"""Conversas simuladas do robo da Boom! Burger (final-app-2026-10-29, bloco 2), pela MESMA funcao que a porta usa
(assistente.atender). Diferenca para a vida real: as mensagens de SAIDA ficam 'simulado' (a porta nunca as envia
para o telemovel do Danilo). Tudo o resto e producao: modelo, ferramentas, precos, morada (Google), create_order, order_origem.

O "cliente" responde sozinho a perguntas previsiveis (opcoes? mais alguma coisa? morada? confirma?) para a conversa
andar ate ao fim; o texto de cada passo fica no relatorio JSON.

Uso (na VPS, em /opt/assistente-negocio):   python3 simular_boom.py B2-entrega-dinheiro [B1-ir-buscar ...]
                                            python3 simular_boom.py --limpar     (cancela carrinhos simulados abertos)
"""
import json
import os
import re
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from servidor import carregar_env  # noqa: E402

carregar_env(os.environ.get("ASSISTENTE_ENV", os.path.join(AQUI, ".env")))
import assistente as A  # noqa: E402
import db  # noqa: E402

SESSAO = "vps-baileys:" + os.environ.get("BORA_WHATSAPP_NUMERO", "")  # número da Bora fora do código (repo público)
DANILO = None  # o numero de teste vem da allowlist do tenant (base), nunca do repo

# (abertura, morada para quando perguntarem, resposta a "quer trocar algo?", extra opcional depois do 1.o resumo)
CENARIOS = {
    "B0-abre-em-breve": {"abertura": "Boa tarde, queria fazer uma encomenda para hoje.", "max": 1},
    "B1-ir-buscar": {"abertura": "Boa tarde! Queria um Boom! Clássico e uma Coca-Cola. Venho buscar à loja.", "morada": None},
    "B2-entrega-dinheiro": {"abertura": "Boa tarde, queria um Boom! Clássico e uma Coca-Cola para entregar.",
                            "morada": "Praça Luís de Camões 1, Guarda"},
    "B3-entrega-acima-30-mbway": {
        "abertura": "Boa noite! Queria 2 Boom! Clássico e 2 Coca-Cola, para entregar. Posso pagar por MB Way?",
        "morada": "Avenida Monsenhor Mendes do Carmo, Guarda", "depois_de_mbway": "Então pode ser em dinheiro, está bem."},
    "B4-acima-do-maximo": {"abertura": "Queria 3 Boom! Kamikaze para entregar.", "morada": "Praça Luís de Camões 1, Guarda", "max": 5,
                           "parar_se": r"m[aá]ximo|40"},
    "B5-audio-menu": {"abertura": "AUDIO:Boa tarde, que hambúrgueres é que vocês têm?", "max": 1},
    "B6-longe": {"abertura": "Queria um Boom! Clássico para entregar.", "morada": "Rua Principal 10, Vilar Formoso", "max": 5,
                 "parar_se": r"zona|longe"},
}

RESPOSTAS = [  # (regex sobre a ultima resposta do robo, chave) por ordem de prioridade
    (r"confirma a encomenda|confirma\?", "sim"),
    (r"buscar ou|entregar\?|vem buscar", "modo"),
    (r"morada|onde (devo|quer)|para onde", "morada"),
    (r"é esta\?|é essa\?|esta morada|certo\?|correta", "sim_morada"),
    (r"trocar|alguma (altera|coisa)|op[cç][oõ]es|mais alguma|quer algo mais|acompanh", "nao"),
    (r"nome", "nome"),
]


def audio_cliente(frase):
    from simular import audio_cliente as f
    return f(frase)


def limpar_memoria(t, numero):
    A.contacto(t, numero)
    A.gravar_contacto(t, numero, {"historico": [], "a_espera_de": None, "silenciado_ate": None, "pessoal": False})
    db.atualizar("assistant_tasks", f"tenant_id=eq.{t['id']}&numero=eq.{numero}&tipo=eq.pedido&estado=eq.aberta&simulado=eq.true&payload->>fase=eq.carrinho",
                 {"estado": "cancelada", "resposta": "limpeza antes de simulacao"})


def correr(nome):
    global DANILO
    c = CENARIOS[nome]
    t = db.ler("assistant_tenants", "slug=eq.boom-burger")[0]
    DANILO = os.environ.get("BOOM_NUMERO_TESTE") or t["allowlist"][0]
    limpar_memoria(t, DANILO)
    passos, turnos, id_pedido = [], 0, None
    inicio = A.agora()
    texto = c["abertura"]
    mbway_dito = False
    while turnos < c.get("max", 9):
        turnos += 1
        antes = db.ler("assistant_messages", "order=id.desc&limit=1", "id")
        id0 = antes[0]["id"] if antes else 0
        ev = {"sessao": SESSAO, "numero": DANILO, "texto": texto, "msg_id": f"simboom_{nome}_{time.time()}"}
        if texto.startswith("AUDIO:"):
            texto = texto[6:]
            ev.update({"texto": "", "tipo": "audio", "mime": "audio/ogg; codecs=opus", "audio_b64": audio_cliente(texto)})
        t0 = time.time()
        r = A.atender(ev, simular=True)
        saidas = db.ler("assistant_messages", f"id=gt.{id0}&direcao=eq.saida&order=id.asc", "texto,motivo,entrega_estado,media_path")
        resposta = "\n".join(s["texto"] for s in saidas)
        passos.append({"cliente": texto, "audio": bool(ev.get("audio_b64")), "ouvido": r.get("ouvido"), "acao": r.get("acao"),
                       "ferramentas": r.get("ferramentas"), "modelos": r.get("modelos"), "erro_motor": r.get("erro_motor"),
                       "segundos": round(time.time() - t0, 1),
                       "robo": [{"texto": s["texto"], "motivo": s["motivo"], "estado": s["entrega_estado"], "voz": bool(s.get("media_path"))} for s in saidas]})
        print(f"[{nome}] #{turnos} cliente> {texto}\n   acao={r.get('acao')} ferr={r.get('ferramentas')} mod={r.get('modelos')} {round(time.time() - t0, 1)}s")
        for s in saidas:
            print(f"   robo< ({s['motivo']}, {s['entrega_estado']}{', voz' if s.get('media_path') else ''}) {s['texto']}")
        ped = db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&numero=eq.{DANILO}&tipo=eq.pedido&order=created_at.desc&limit=1",
                     "payload,codigo,created_at")
        if ped and (ped[0].get("payload") or {}).get("order_id") and A.hora_local(ped[0]["created_at"]) >= inicio:
            id_pedido = ped[0]["payload"]["order_id"]
            break
        if c.get("parar_se") and re.search(c["parar_se"], resposta, re.I):
            break
        low = resposta.lower()
        if "mb way" in (c["abertura"].lower()) and not mbway_dito and re.search(r"s[oó] (em )?dinheiro|dinheiro", low) and c.get("depois_de_mbway"):
            mbway_dito, texto = True, c["depois_de_mbway"]
            time.sleep(3)
            continue
        chave = next((k for rx, k in RESPOSTAS if re.search(rx, low)), None)
        if chave == "sim":
            texto = "Sim, confirmo."
        elif chave == "modo":
            texto = "Venho buscar." if not c.get("morada") else "É para entregar."
        elif chave == "morada":
            texto = c.get("morada") or "Venho buscar à loja."
        elif chave == "sim_morada":
            texto = "Sim, é essa."
        elif chave == "nao":
            texto = "Não, assim está bem."
        elif chave == "nome":
            texto = "O meu nome é Danilo."
        else:
            texto = "Pode ser."
        time.sleep(3)
    return {"cenario": nome, "order_id": id_pedido, "passos": passos}


def limpar():
    t = db.ler("assistant_tenants", "slug=eq.boom-burger")[0]
    n = db.atualizar("assistant_tasks", f"tenant_id=eq.{t['id']}&tipo=eq.pedido&estado=eq.aberta&simulado=eq.true&payload->>fase=eq.carrinho",
                     {"estado": "cancelada", "resposta": "limpeza"})
    print("carrinhos simulados cancelados:", len(n))


if __name__ == "__main__":
    if sys.argv[1:] == ["--limpar"]:
        limpar()
        sys.exit(0)
    rel = {"quando": A.iso(A.agora()), "cenarios": []}
    for nome in sys.argv[1:] or list(CENARIOS):
        rel["cenarios"].append(correr(nome))
    f = os.path.join(AQUI, f"simulacao-boom-{A.agora().strftime('%Y%m%d-%H%M')}.json")
    json.dump(rel, open(f, "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    print("RELATORIO", f)
    for c in rel["cenarios"]:
        print("PEDIDO", c["cenario"], c["order_id"])
