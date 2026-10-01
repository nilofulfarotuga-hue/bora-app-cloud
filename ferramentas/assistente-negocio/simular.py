"""Conversas simuladas pela MESMA funcao que a porta usa (assistente.atender), sem WhatsApp.

simulado=True so muda uma coisa: as mensagens de saida ficam com entrega_estado='simulado' e a porta
nunca as envia. Tudo o resto — encaminhamento, classificacao, motores, ferramentas, base de dados,
marcacoes reais em appointments (is_test=true) — e o caminho de producao.

Uso (na VPS):  python3 simular.py [cenario ...]   -> escreve simulacao-<data>.json
"""
import datetime as dt
import json
import os
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
from servidor import carregar_env  # noqa: E402

carregar_env(os.environ.get("ASSISTENTE_ENV", os.path.join(AQUI, ".env")))
import assistente as A  # noqa: E402
import db  # noqa: E402

DANILO, ERNANDO, ESTRANHO = "351931992662", "351937472634", "351912345678"
SESSAO = "vps-baileys:351937501673"
amanha = A.agora().date() + dt.timedelta(days=1)
dom = A.agora().date() + dt.timedelta(days=(6 - A.agora().weekday()) % 7 or 7)
D_AMANHA = A.DIAS[amanha.weekday()]

CENARIOS = {
    "01-preco": [(DANILO, "Boa noite, quanto custa um corte?")],
    "02-horario": [(DANILO, "A que horas abrem ao sábado?")],
    "03-morada": [(DANILO, "Onde é que ficam?")],
    "04-fim-da-tarde": [(DANILO, "tem horário amanhã ao fim da tarde para corte e barba?")],
    "05-marcacao": [(DANILO, f"Queria marcar um corte para {D_AMANHA} às 10h. Chamo-me Danilo."), (DANILO, "Sim, pode marcar"),
                    (DANILO, "Obrigado!")],
    "06-hora-ocupada": [(ERNANDO, f"Olá, sou o Ernando. Dava para um corte {D_AMANHA} às 10h?"), (ERNANDO, "Pode ser a mais próxima depois, marque essa")],
    "07-domingo": [(DANILO, "E no domingo, posso ir cortar o cabelo?")],
    "08-desmarcar": [(DANILO, "Afinal não vou conseguir ir, quero desmarcar a minha marcação"), (DANILO, "sim, desmarque")],
    "09-remarcar": [(ERNANDO, f"Consegue passar a minha marcação de {D_AMANHA} para as 16h?"), (ERNANDO, "sim")],
    "10-crianca": [(DANILO, "Fazem cortes a crianças? O meu filho tem 6 anos")],
    "11-degrade": [(DANILO, "Quanto fica um degradê?")],
    "12-freestyle": [(DANILO, "Fazem freestyle? Queria um desenho de lado")],
    "13-pergunta-ao-dono": [(ERNANDO, "Aceitam pagamento por MB Way?"), ("DONO", None), (DANILO, "Posso pagar com MB Way?")],
    "14-pessoal": [(DANILO, "Mano logo vens jantar cá a casa? A mãe fez bacalhau")],
    "15-grupo": [(DANILO, "Quanto é a barba?", {"grupo": True, "msg_id": "false_1203630@g.us_X"})],
    "16-fora-da-allowlist": [(ESTRANHO, "Quanto custa um corte?")],
    "17-dono-escreveu": [(DANILO, "Olá, têm vaga hoje?"), ("DONO_ESCREVEU", DANILO), (DANILO, "Então até já!")],
    "18-blocklist": [("BLOQUEAR", ERNANDO), (ERNANDO, "Quanto custa a barba?"), ("DESBLOQUEAR", ERNANDO)],
}


def limpar_memoria(numero):
    t, _ = A.tenant_para(SESSAO, numero)
    if t:
        A.contacto(t, numero)
        A.gravar_contacto(t, numero, {"historico": [], "a_espera_de": None, "silenciado_ate": None, "pessoal": False})


def correr(nome, passos):
    out = []
    t = db.ler("assistant_tenants", "slug=eq.mister-navalha")[0]
    for n in {p[0] for p in passos if p[0] in (DANILO, ERNANDO)}:
        limpar_memoria(n)
    inicio = A.iso(A.agora())
    for p in passos:
        numero, texto = p[0], p[1]
        extra = p[2] if len(p) > 2 else {}
        if numero == "DONO_ESCREVEU":  # o mesmo que a porta faz quando ve uma mensagem escrita a mao
            r = A.dono_falou(SESSAO, texto)
            out.append({"de": "PORTA", "acao": "dono-falou", "resultado": r})
            print(f"[{nome}] porta: o dono escreveu a mao na conversa {texto} -> {r}")
            continue
        if numero in ("BLOQUEAR", "DESBLOQUEAR"):
            bl = [x for x in (t.get("blocklist") or []) if x != texto] + ([texto] if numero == "BLOQUEAR" else [])
            db.atualizar("assistant_tenants", f"id=eq.{t['id']}", {"blocklist": bl})
            t["blocklist"] = bl
            out.append({"de": "ADMIN", "acao": numero.lower(), "blocklist": bl})
            print(f"[{nome}] admin: {numero.lower()} {texto} -> blocklist={bl}")
            continue
        if numero == "DONO":  # o dono responde com o codigo da pergunta aberta
            # so a pergunta criada NESTE cenario (a 1.a volta respondeu a uma pergunta de outro cenario)
            k = db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&tipo=eq.pergunta_dono&estado=eq.aberta&simulado=eq.true"
                                          f"&created_at=gte.{db.q(inicio)}&order=created_at.desc&limit=1")
            if not k:
                out.append({"de": "DONO", "erro": "nenhuma pergunta aberta"})
                continue
            numero, texto = A.so_digitos(t["dono_destino"]), f"{k[0]['codigo']} Sim, aceitamos MB Way e dinheiro. Cartão ainda não."
        antes = db.ler("assistant_messages", "order=id.desc&limit=1", "id")
        id0 = antes[0]["id"] if antes else 0
        ev = {"sessao": SESSAO, "numero": numero, "texto": texto, "msg_id": f"sim_{nome}_{time.time()}"}
        ev.update(extra)
        t0 = time.time()
        r = A.atender(ev, simular=True)
        saidas = db.ler("assistant_messages", f"id=gt.{id0}&direcao=eq.saida&order=id.asc", "numero,texto,motivo,entrega_estado")
        out.append({"de": numero, "texto": texto, "acao": r.get("acao"), "tratado": r.get("tratado"),
                    "ferramentas": r.get("ferramentas"), "modelos": r.get("modelos"), "erro_motor": r.get("erro_motor"),
                    "segundos": round(time.time() - t0, 1), "saidas": saidas})
        print(f"[{nome}] {numero} > {texto}\n   acao={r.get('acao')} ferr={r.get('ferramentas')} mod={r.get('modelos')} {round(time.time() - t0, 1)}s")
        for s in saidas:
            print(f"   < ({s['numero']}, {s['motivo']}, {s['entrega_estado']}) {s['texto']}")
        time.sleep(4)
    return out


def limpar():
    """Fim dos testes: cancela as marcacoes de teste (nunca apaga), esquece as respostas do dono que vieram
    de simulacao (eram do script, nao do Ernando) e limpa a memoria dos numeros de teste."""
    t = db.ler("assistant_tenants", "slug=eq.mister-navalha")[0]
    r = db.rpc("admin_assistente_limpar_testes", {"p_tenant": t["id"]})
    sim = {k["pergunta"] for k in db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&tipo=eq.pergunta_dono&simulado=eq.true", "pergunta")}
    k = t.get("knowledge") or {}
    antes = len(k.get("perguntas_aprendidas") or [])
    k["perguntas_aprendidas"] = [p for p in (k.get("perguntas_aprendidas") or []) if p.get("pergunta") not in sim]
    db.atualizar("assistant_tenants", f"id=eq.{t['id']}", {"knowledge": k})
    for n in (DANILO, ERNANDO):
        limpar_memoria(n)
        A.gravar_contacto(t, n, {"nome": None, "ultimo_servico": None})
    print("LIMPEZA", r, f"aprendidas {antes} -> {len(k['perguntas_aprendidas'])}")


if __name__ == "__main__":
    if sys.argv[1:] == ["--limpar"]:
        limpar()
        sys.exit(0)
    escolha = sys.argv[1:] or list(CENARIOS)
    rel = {"quando": A.iso(A.agora()), "cenarios": {}}
    for c in escolha:
        rel["cenarios"][c] = correr(c, CENARIOS[c])
    f = os.path.join(AQUI, f"simulacao-{A.agora().strftime('%Y%m%d-%H%M')}.json")
    json.dump(rel, open(f, "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    print("RELATORIO", f)
