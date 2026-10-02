"""Assistente de Negocio no WhatsApp ("funcionario digital") — o cerebro.

UMA funcao de entrada: `atender(evento)`. E a mesma que a porta `vps-baileys` chama (via servidor.py,
POST /evento) e a mesma que as simulacoes chamam (simular.py, com simular=True). Nenhum atalho.

Regras de ouro (missao 2026-10-01):
  - so atende numeros do cliente certo (modo teste: so a allowlist); o resto volta para a porta;
  - grupos: nunca; blocklist: nunca; mensagem pessoal: silencio; dono escreveu na conversa: 12 h calado;
  - preco, horario e vagas so vem das ferramentas (base de dados); nunca inventa;
  - "vou verificar" sem tarefa criada e proibido: se a resposta promete voltar, cria-se a pergunta ao dono.
"""
import datetime as dt
import json
import os
import re
import secrets
import time
import unicodedata

import db
import motores
import voz

try:
    from zoneinfo import ZoneInfo
    LX = ZoneInfo("Europe/Lisbon")
except Exception:  # Windows sem tzdata: outubro = WEST (UTC+1); so para correr no PC
    LX = dt.timezone(dt.timedelta(hours=1))

DIAS = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]
DIAS_BH = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
HIST_MAX = 10
MAX_VOLTAS = 6


# ----------------------------------------------------------------------------- utilitarios
def agora():
    return dt.datetime.now(LX)


def sem_acentos(s):
    s = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", s.lower()).strip()


def so_digitos(n):
    d = re.sub(r"\D", "", str(n or ""))
    return "351" + d if len(d) == 9 and d[0] in "923" else d  # 912345678 == 351912345678


def euros(cents):
    v = (cents or 0) / 100
    return (f"{v:.0f} €" if v == int(v) else f"{v:.2f} €".replace(".", ","))


def hora_local(iso):
    return dt.datetime.fromisoformat(str(iso).replace("Z", "+00:00")).astimezone(LX)


def iso(d):
    return d.isoformat()


# ----------------------------------------------------------------------------- tenant e contacto
def tenants_da_sessao(sessao):
    return db.ler("assistant_tenants", f"sessao=eq.{db.q(sessao)}&mode=neq.desligado")


def tenant_para(sessao, numero):
    """Devolve (tenant, motivo). tenant=None => a mensagem NAO e deste assistente (segue a porta normal)."""
    numero = so_digitos(numero)
    for t in tenants_da_sessao(sessao):
        if numero in {so_digitos(x) for x in (t.get("blocklist") or [])}:
            return t, "blocklist"
        if t["mode"] == "teste":
            if numero in {so_digitos(x) for x in (t.get("allowlist") or [])}:
                return t, "allowlist"
        elif t["mode"] == "ligado":
            return t, "ligado"
    return None, "fora"


def tenant_por_id(tid):
    r = db.ler("assistant_tenants", f"id=eq.{tid}")
    return r[0] if r else None


def pode_escrever_a(t, numero):
    """Rede de seguranca de SAIDA: em teste so a allowlist e o dono; desligado: ninguem."""
    numero = so_digitos(numero)
    if t["mode"] == "desligado" or numero in {so_digitos(x) for x in (t.get("blocklist") or [])}:
        return False
    if t["mode"] == "teste":
        return numero in {so_digitos(x) for x in (t.get("allowlist") or [])} or numero == so_digitos(t.get("dono_destino"))
    return True


def contacto(t, numero):
    r = db.ler("assistant_contacts", f"tenant_id=eq.{t['id']}&numero=eq.{db.q(numero)}")
    if r:
        return r[0]
    return db.upsert("assistant_contacts", {"tenant_id": t["id"], "numero": numero}, "tenant_id,numero")


def gravar_contacto(t, numero, campos):
    campos = dict(campos)
    campos["updated_at"] = iso(agora())
    db.atualizar("assistant_contacts", f"tenant_id=eq.{t['id']}&numero=eq.{db.q(numero)}", campos)


def servicos(t):
    return db.ler("provider_services", f"provider_id=eq.{db.q(t['provider_id'])}&is_active=eq.true&order=sort_order.asc,name.asc",
                  "id,name,price_cents,duration_minutes")


def negocio(t):
    r = db.ler("service_providers", f"id=eq.{db.q(t['provider_id'])}", "name,address,phone,business_hours")
    return r[0] if r else {}


ALIAS = {"degrade": "corte", "fade": "corte", "cabelo": "corte", "infantil": "corte infantil",
         "crianca": "corte infantil", "miudo": "corte infantil", "filho": "corte infantil",
         "sobrancelhas": "sobrancelha", "barba e corte": "corte + barba", "corte e barba": "corte + barba",
         "completo": "corte + barba + sobrancelha"}


def resolver_servico(t, nome):
    lista = servicos(t)
    alvo = sem_acentos(nome).replace(" e ", " + ").replace("&", "+")
    for k, v in ALIAS.items():
        if alvo == k or alvo == k + "s":
            alvo = v
    alvo = re.sub(r"\s*\+\s*", " + ", alvo)
    for s in lista:  # igual
        if sem_acentos(s["name"]).replace(" e ", " + ") == alvo or s["id"] == nome:
            return s, lista
    toks = set(re.findall(r"[a-z]+", alvo))
    melhor, pont = None, 0
    for s in lista:
        st = set(re.findall(r"[a-z]+", sem_acentos(s["name"])))
        p = len(toks & st) - 0.1 * len(st - toks)
        if p > pont:
            melhor, pont = s, p
    return melhor, lista


# ----------------------------------------------------------------------------- mensagens
def registar(t, numero, direcao, texto, **extra):
    linha = {"tenant_id": t["id"], "numero": numero, "direcao": direcao, "texto": texto}
    linha.update({k: v for k, v in extra.items() if v is not None})
    return db.inserir("assistant_messages", linha)


def enfileirar(t, numero, texto, motivo, simulado=False, media_path=None):
    """Poe uma mensagem na fila de saida. A porta vem buscar; aqui nunca se envia nada directamente.
    media_path = nota de voz (.ogg opus) que a porta envia como audio PTT."""
    if not pode_escrever_a(t, numero):
        registar(t, numero, "saida", texto, motivo=motivo, decisao="bloqueado-fora-da-allowlist",
                 entrega_estado="bloqueado", simulado=simulado, media_path=media_path)
        return None
    return registar(t, numero, "saida", texto, motivo=motivo, simulado=simulado, media_path=media_path,
                    entrega_estado="simulado" if simulado else "pendente")


# ----------------------------------------------------------------------------- ferramentas
FERRAMENTAS = [
    {"type": "function", "function": {"name": "ver_servicos", "description": "Lista os serviços ativos com preço e duração.",
                                      "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {"name": "ver_horario", "description": "Horário de funcionamento, morada, contactos e forma de pagamento.",
                                      "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "horarios_livres",
        "description": "Vagas reais na agenda para um serviço num dia (mesma lógica da app). Se o dia estiver fechado ou cheio, devolve as vagas mais próximas noutros dias.",
        "parameters": {"type": "object", "properties": {
            "dia": {"type": "string", "description": "Data AAAA-MM-DD"},
            "servico": {"type": "string", "description": "Nome do serviço (ex.: Corte, Barba, Corte + Barba)"},
            "depois_de": {"type": "string", "description": "Opcional, HH:MM — só vagas a partir desta hora"},
            "antes_de": {"type": "string", "description": "Opcional, HH:MM — só vagas que comecem antes desta hora"}},
            "required": ["dia", "servico"]}}},
    {"type": "function", "function": {
        "name": "marcar", "description": "Cria a marcação na agenda. Só depois de o cliente confirmar serviço, dia, hora e nome.",
        "parameters": {"type": "object", "properties": {
            "servico": {"type": "string"}, "dia": {"type": "string", "description": "AAAA-MM-DD"},
            "hora": {"type": "string", "description": "HH:MM"}, "nome": {"type": "string", "description": "Nome que o cliente deu"}},
            "required": ["servico", "dia", "hora", "nome"]}}},
    {"type": "function", "function": {"name": "minhas_marcacoes", "description": "Marcações futuras deste cliente (deste número).",
                                      "parameters": {"type": "object", "properties": {}}}},
    {"type": "function", "function": {
        "name": "desmarcar", "description": "Desmarca uma marcação deste cliente.",
        "parameters": {"type": "object", "properties": {"appointment_id": {"type": "string", "description": "Opcional se só houver uma"}}}}},
    {"type": "function", "function": {
        "name": "remarcar", "description": "Muda uma marcação deste cliente para outro dia/hora (tem de ser vaga real).",
        "parameters": {"type": "object", "properties": {
            "appointment_id": {"type": "string", "description": "Opcional se só houver uma"},
            "dia": {"type": "string", "description": "AAAA-MM-DD"}, "hora": {"type": "string", "description": "HH:MM"}},
            "required": ["dia", "hora"]}}},
    {"type": "function", "function": {
        "name": "lista_de_espera", "description": "Põe o cliente na lista de espera de um dia cheio; avisa-o se abrir vaga.",
        "parameters": {"type": "object", "properties": {"dia": {"type": "string"}, "servico": {"type": "string"}},
                       "required": ["dia", "servico"]}}},
    {"type": "function", "function": {
        "name": "perguntar_ao_dono", "description": "Quando não sabes a resposta (e não está na ficha nem nas perguntas aprendidas). Cria uma tarefa com prazo; a resposta do dono é entregue ao cliente.",
        "parameters": {"type": "object", "properties": {"pergunta": {"type": "string"}}, "required": ["pergunta"]}}},
    {"type": "function", "function": {
        "name": "passar_ao_dono", "description": "Assuntos que só o dono decide: freestyle/desenhos, madeixas, coloração, descontos, reclamações, dinheiro, pedidos fora da tabela.",
        "parameters": {"type": "object", "properties": {"motivo": {"type": "string"}}, "required": ["motivo"]}}},
    {"type": "function", "function": {
        "name": "guardar_nome", "description": "Guarda o nome SÓ quando a própria pessoa o disse.",
        "parameters": {"type": "object", "properties": {"nome": {"type": "string"}}, "required": ["nome"]}}},
    {"type": "function", "function": {
        "name": "guardar_fio", "description": "Guarda o que ficou pendente na conversa (ex.: 'escolher hora para Corte+Barba sexta'), para retomar na próxima mensagem. Vazio = nada pendente.",
        "parameters": {"type": "object", "properties": {"a_espera_de": {"type": "string"}}, "required": ["a_espera_de"]}}},
]


class Turno:
    """Estado de uma resposta: tenant, contacto, ferramentas usadas, custos."""

    def __init__(self, t, numero, ct, simular):
        self.t, self.numero, self.ct, self.simular = t, numero, ct, simular
        self.usadas, self.custo, self.tin, self.tout, self.modelos = [], 0.0, 0, 0, []
        self.tarefa_dono = False

    # --- ferramentas
    def ver_servicos(self):
        return {"servicos": [{"nome": s["name"], "preco": euros(s["price_cents"]), "duracao_min": s["duration_minutes"]}
                             for s in servicos(self.t)],
                "notas": (self.t.get("knowledge") or {}).get("ficha", {}).get("notas", [])}

    def ver_horario(self):
        n = negocio(self.t)
        bh = n.get("business_hours") or {}
        horas = {}
        for i, k in enumerate(DIAS_BH):
            d = bh.get(k) or {}
            horas[DIAS[i]] = "fechado" if d.get("closed") or not d else f"{d.get('open')}–{d.get('close')}"
        f = (self.t.get("knowledge") or {}).get("ficha", {})
        return {"horario": horas, "morada": f.get("morada") or n.get("address"), "telefone": f.get("telefone") or n.get("phone"),
                "instagram": f.get("instagram"), "pagamento": f.get("pagamento"), "site": f.get("site")}

    def _vagas(self, svc, dia, depois_de=None, antes_de=None):
        slots = db.rpc("assistente_vagas", {"p_tenant": self.t["id"], "p_servico_id": svc["id"], "p_dia": dia.isoformat()}) or []
        hs = sorted({hora_local(s["slot_start"]).strftime("%H:%M") for s in slots})
        if depois_de:
            hs = [h for h in hs if h >= depois_de]
        if antes_de:
            hs = [h for h in hs if h < antes_de]
        return hs

    def horarios_livres(self, dia, servico, depois_de=None, antes_de=None):
        svc, lista = resolver_servico(self.t, servico)
        if not svc:
            return {"erro": "servico_nao_existe", "servicos_disponiveis": [s["name"] for s in lista],
                    "instrucao": "Se o cliente pede algo fora desta lista, usa passar_ao_dono."}
        d = dt.date.fromisoformat(dia)
        hs = self._vagas(svc, d, depois_de, antes_de)
        res = {"servico": svc["name"], "preco": euros(svc["price_cents"]), "duracao_min": svc["duration_minutes"],
               "dia": d.isoformat(), "dia_semana": DIAS[d.weekday()]}
        if hs:
            res["vagas"] = hs[:14]
            return res
        bh = (negocio(self.t).get("business_hours") or {}).get(DIAS_BH[d.weekday()]) or {}
        res["vagas"] = []
        res["motivo"] = "fechado neste dia" if bh.get("closed") else "sem vagas neste dia/intervalo"
        prox = []
        for k in range(1, 8):
            d2 = d + dt.timedelta(days=k)
            h2 = self._vagas(svc, d2, depois_de, antes_de) or self._vagas(svc, d2)
            if h2:
                prox.append({"dia": d2.isoformat(), "dia_semana": DIAS[d2.weekday()], "vagas": h2[:6]})
            if len(prox) >= 2:
                break
        res["proximas"] = prox
        return res

    def _inicio(self, dia, hora):
        hh, mm = [int(x) for x in re.findall(r"\d+", hora)[:2]] + [0] * (2 - len(re.findall(r"\d+", hora)[:2]))
        return dt.datetime.combine(dt.date.fromisoformat(dia), dt.time(hh, mm), LX)

    def _mais_proximas(self, svc, dia, hora):
        d = dt.date.fromisoformat(dia)
        alvo = self._inicio(dia, hora)
        hs = self._vagas(svc, d)
        hs.sort(key=lambda h: abs((self._inicio(dia, h) - alvo).total_seconds()))
        return sorted(hs[:3])

    def marcar(self, servico, dia, hora, nome):
        svc, lista = resolver_servico(self.t, servico)
        if not svc:
            return {"ok": False, "erro": "servico_nao_existe", "servicos_disponiveis": [s["name"] for s in lista]}
        inicio = self._inicio(dia, hora)
        # idempotente: um "obrigado" nao pode voltar a marcar (e falhar contra a propria marcacao)
        for m in self.minhas_marcacoes()["marcacoes"]:
            if m["quando"] == inicio.strftime("%Y-%m-%d %H:%M") and m["servico"] == svc["name"]:
                return {"ok": True, "ja_estava_marcado": True, "servico": svc["name"], "dia": dia,
                        "dia_semana": DIAS[inicio.weekday()], "hora": inicio.strftime("%H:%M"),
                        "instrucao": "Já estava marcado — não digas que houve erro; só confirma se o cliente perguntar."}
        r = db.rpc("assistente_marcar_v2", {"p_notificar": not self.simular, "p_tenant": self.t["id"], "p_servico_id": svc["id"], "p_inicio": iso(inicio),
                                         "p_nome": nome, "p_telefone": "+" + self.numero, "p_teste": self.t["mode"] == "teste"})
        if not r.get("ok"):
            return {"ok": False, "erro": "hora_ocupada_ou_fora_do_horario", "pedido": f"{dia} {hora}",
                    "mais_proximas_no_mesmo_dia": self._mais_proximas(svc, dia, hora)}
        gravar_contacto(self.t, self.numero, {"nome": nome.strip()[:60], "ultimo_servico": svc["name"], "a_espera_de": None})
        db.atualizar("assistant_tasks", f"tenant_id=eq.{self.t['id']}&numero=eq.{self.numero}&tipo=eq.lista_espera&estado=eq.aberta",
                     {"estado": "cumprida", "cumprida_em": iso(agora()), "resposta": "marcou"})
        return {"ok": True, "servico": svc["name"], "dia": dia, "dia_semana": DIAS[inicio.weekday()], "hora": inicio.strftime("%H:%M"),
                "preco": euros(svc["price_cents"]), "pagamento": "na barbearia", "appointment_id": r["appointment_id"]}

    def minhas_marcacoes(self):
        r = db.rpc("assistente_minhas_marcacoes", {"p_tenant": self.t["id"], "p_telefone": self.numero}) or []
        return {"marcacoes": [{"appointment_id": a["appointment_id"], "servico": a["servico"],
                               "quando": hora_local(a["inicio"]).strftime("%Y-%m-%d %H:%M"),
                               "dia_semana": DIAS[hora_local(a["inicio"]).weekday()]} for a in r]}

    def _uma(self, appointment_id):
        if appointment_id:
            return appointment_id, None
        m = self.minhas_marcacoes()["marcacoes"]
        if len(m) == 1:
            return m[0]["appointment_id"], None
        return None, {"ok": False, "erro": "sem_marcacoes" if not m else "varias_marcacoes_qual", "marcacoes": m}

    def desmarcar(self, appointment_id=None):
        aid, err = self._uma(appointment_id)
        if err:
            return err
        r = db.rpc("assistente_desmarcar_v2", {"p_notificar": not self.simular, "p_tenant": self.t["id"], "p_appointment_id": aid, "p_telefone": self.numero})
        if r.get("ok"):
            self._oferecer_vaga(r)
            q = hora_local(r["inicio"])
            return {"ok": True, "servico": r["servico"], "era": q.strftime("%Y-%m-%d %H:%M"), "dia_semana": DIAS[q.weekday()]}
        return r

    def remarcar(self, dia, hora, appointment_id=None):
        aid, err = self._uma(appointment_id)
        if err:
            return err
        inicio = self._inicio(dia, hora)
        r = db.rpc("assistente_remarcar_v2", {"p_notificar": not self.simular, "p_tenant": self.t["id"], "p_appointment_id": aid, "p_telefone": self.numero,
                                           "p_novo_inicio": iso(inicio)})
        if r.get("ok"):
            self._oferecer_vaga({"service_id": r["service_id"], "inicio": r["de"], "servico": r["servico"]})
            return {"ok": True, "servico": r["servico"], "de": hora_local(r["de"]).strftime("%Y-%m-%d %H:%M"),
                    "para": inicio.strftime("%Y-%m-%d %H:%M"), "dia_semana": DIAS[inicio.weekday()]}
        if r.get("erro") == "vaga_indisponivel":
            svc = next((s for s in servicos(self.t) if s["name"] in json.dumps(self.minhas_marcacoes())), None)
            r["mais_proximas_no_mesmo_dia"] = self._mais_proximas(svc, dia, hora) if svc else []
        return r

    def _oferecer_vaga(self, r):
        """Alguem desmarcou: o primeiro da lista de espera desse dia recebe a vaga."""
        q = hora_local(r["inicio"])
        dia = q.date().isoformat()
        esp = db.ler("assistant_tasks", f"tenant_id=eq.{self.t['id']}&tipo=eq.lista_espera&estado=eq.aberta&order=created_at.asc")
        for k in esp:
            if (k.get("payload") or {}).get("dia") == dia and k.get("numero") != self.numero:
                txt = (f"Boa notícia: abriu uma vaga na {self.t['nome']} para {DIAS[q.weekday()]} às {q.strftime('%H:%M')}. "
                       f"Quer que a marque para si? Responda só \"sim\" e eu trato.")
                enfileirar(self.t, k["numero"], txt, "lista_espera", simulado=self.simular or k.get("simulado"))
                gravar_contacto(self.t, k["numero"], {"a_espera_de": {"o_que": f"oferecida vaga {dia} {q.strftime('%H:%M')} ({r.get('servico')}) — se disser sim, marcar"}})
                db.atualizar("assistant_tasks", f"id=eq.{k['id']}", {"estado": "cumprida", "cumprida_em": iso(agora()),
                                                                      "resposta": f"vaga oferecida {dia} {q.strftime('%H:%M')}"})
                break

    def lista_de_espera(self, dia, servico):
        svc, _ = resolver_servico(self.t, servico)
        db.inserir("assistant_tasks", {"tenant_id": self.t["id"], "numero": self.numero, "tipo": "lista_espera",
                                       "payload": {"dia": dia, "servico": svc["name"] if svc else servico},
                                       "prazo": iso(dt.datetime.combine(dt.date.fromisoformat(dia), dt.time(20), LX)),
                                       "simulado": self.simular}, devolver=False)
        return {"ok": True, "dia": dia}

    def perguntar_ao_dono(self, pergunta):
        self.tarefa_dono = True
        cod = "P" + str(secrets.randbelow(900) + 100)
        nome = self.ct.get("nome") or ("+" + self.numero)
        tk = db.inserir("assistant_tasks", {"tenant_id": self.t["id"], "numero": self.numero, "tipo": "pergunta_dono",
                                            "codigo": cod, "pergunta": pergunta,
                                            "prazo": iso(agora() + dt.timedelta(minutes=30)), "simulado": self.simular})
        txt = (f"❓ {self.t['nome']} — pergunta de um cliente ({cod})\n\n«{pergunta}»\n\nCliente: {nome}.\n"
               f"Responde a citar esta mensagem, ou escreve: {cod} e a resposta.")
        enfileirar(self.t, so_digitos(self.t["dono_destino"]), txt, f"pergunta_dono:{tk['id']}", self.simular)
        gravar_contacto(self.t, self.numero, {"a_espera_de": {"o_que": f"resposta do dono a: {pergunta}", "tarefa": tk["id"]}})
        return {"ok": True, "codigo": cod, "prazo_min": 30,
                "instrucao": "Diz ao cliente que confirmas com o Ernando e voltas a falar com ele assim que tiveres a resposta."}

    def passar_ao_dono(self, motivo):
        self.tarefa_dono = True
        nome = self.ct.get("nome") or ("+" + self.numero)
        db.inserir("assistant_tasks", {"tenant_id": self.t["id"], "numero": self.numero, "tipo": "passar_dono",
                                       "pergunta": motivo, "estado": "cumprida", "cumprida_em": iso(agora()),
                                       "simulado": self.simular}, devolver=False)
        txt = (f"📲 {self.t['nome']} — um cliente precisa de ti: {motivo}\nCliente: {nome} (+{self.numero}).\n"
               f"Fala tu diretamente com ele.")
        enfileirar(self.t, so_digitos(self.t["dono_destino"]), txt, "passar_dono", self.simular)
        return {"ok": True, "instrucao": "Diz ao cliente que isso é com o Ernando, que já lhe passaste o recado e ele fala consigo."}

    def guardar_nome(self, nome):
        gravar_contacto(self.t, self.numero, {"nome": nome.strip()[:60]})
        self.ct["nome"] = nome.strip()[:60]
        return {"ok": True}

    def guardar_fio(self, a_espera_de):
        gravar_contacto(self.t, self.numero, {"a_espera_de": {"o_que": a_espera_de} if a_espera_de.strip() else None})
        return {"ok": True}

    def executar(self, nome, args):
        f = getattr(self, nome, None)
        if nome.startswith("_") or not callable(f) or nome not in {x["function"]["name"] for x in FERRAMENTAS}:
            return {"erro": "ferramenta_desconhecida"}
        try:
            r = f(**args)
        except TypeError as e:
            r = {"erro": "argumentos_invalidos", "detalhe": str(e)[:120]}
        except db.ErroDB as e:
            r = {"erro": "base_de_dados", "detalhe": str(e)[:160]}
        except ValueError as e:
            r = {"erro": "valor_invalido", "detalhe": str(e)[:120]}
        self.usadas.append({"ferramenta": nome, "args": args, "resultado": r})
        return r


# ----------------------------------------------------------------------------- prompts
def prompt_sistema(t, ct):
    k = t.get("knowledge") or {}
    f = k.get("ficha", {})
    agora_ = agora()
    aprendidas = "\n".join(f"- P: {p.get('pergunta')} → R: {p.get('resposta')}" for p in (k.get("perguntas_aprendidas") or [])[-30:]) or "(nenhuma ainda)"
    fio = (ct.get("a_espera_de") or {}).get("o_que") if isinstance(ct.get("a_espera_de"), dict) else None
    semana = ", ".join(f"{DIAS[(agora_.date() + dt.timedelta(days=i)).weekday()]} {(agora_.date() + dt.timedelta(days=i)).isoformat()}" for i in range(8))
    tabela = "; ".join(f"{s['name']} {euros(s['price_cents'])} ({s['duration_minutes']} min)" for s in servicos(t))
    bh = negocio(t).get("business_hours") or {}
    horas = ", ".join(f"{DIAS[i]} " + ("fechado" if (bh.get(k) or {}).get("closed") or not bh.get(k) else f"{bh[k].get('open')}–{bh[k].get('close')}")
                      for i, k in enumerate(DIAS_BH))
    return f"""És a pessoa que atende o WhatsApp da {t['nome']} (Guarda, Portugal). Dono: {f.get('dono', 'o dono')}.
Agora: {DIAS[agora_.weekday()]}, {agora_.strftime('%Y-%m-%d %H:%M')} (hora de Lisboa). Próximos dias: {semana}.

Tom: {t.get('tom') or 'Português de Portugal, curto e simpático.'}
Escreves SEMPRE em português de Portugal (nunca do Brasil): "marcação", "telemóvel", "está bem", "pode ser". Tratas o cliente SEMPRE por "você" (3.ª pessoa: "pode", "quer", "consigo"), nunca por "tu". Respostas de 1 a 3 frases. Sem listas longas (no máximo 4 horas de cada vez).
Datas ao cliente sempre por extenso e curtas ("sexta, dia 2", "amanhã às 10:30"); nunca no formato 2026-10-02.

TABELA (da base de dados, é a verdade): {tabela}.
HORÁRIO: {horas}.
FICHA: morada {f.get('morada')}; telefone {f.get('telefone')}; Instagram {f.get('instagram')}; pagamento: {f.get('pagamento')}.
Notas do dono: {' '.join(f.get('notas') or [])}
Perguntas já respondidas pelo dono (podes usar estas respostas):
{aprendidas}

Cliente: {('chama-se ' + ct['nome']) if ct.get('nome') else 'nome desconhecido (não inventes; só usas o nome se ele o disser)'}.
{('Último serviço: ' + ct['ultimo_servico'] + '.') if ct.get('ultimo_servico') else ''}
{('FIO DA CONVERSA (o que ficou pendente): ' + fio) if fio else ''}

REGRAS (inquebráveis):
1. Preços, serviços e horário: SÓ a TABELA e o HORÁRIO acima; vagas: SÓ o que horarios_livres devolve. Nunca inventes um preço, uma hora livre ou um serviço.
1b. O que NÃO está escrito acima (formas de pagamento além do que diz a ficha, estacionamento, cartão, produtos, marcas, idade mínima, etc.): não afirmes nem SIM nem NÃO — chama perguntar_ao_dono. Ex.: "aceitam MB Way?" não está escrito → perguntar_ao_dono.
1c. Degradê = está incluído no Corte (mesmo preço do Corte); responde diretamente, não passes ao dono.
2. Para propor horas usa horarios_livres. Se a hora pedida estiver ocupada, oferece as 2 ou 3 mais próximas que a ferramenta devolver.
3. Para marcar precisas de serviço, dia, hora e nome. O telefone é este número de WhatsApp — não o peças. Antes de marcar, confirma em 1 frase; quando o cliente disser que sim, chama marcar. Depois confirma: serviço, dia, hora, preço e que paga na barbearia.
4. Não sabes a resposta e não está na ficha nem nas perguntas já respondidas? Chama perguntar_ao_dono e diz que confirmas e voltas. É PROIBIDO dizer "vou verificar"/"já lhe digo" sem chamar perguntar_ao_dono.
5. Freestyle/desenhos, madeixas, coloração, descontos, reclamações, dinheiro ou qualquer coisa fora da tabela: chama passar_ao_dono.
6. Desmarcar/remarcar: usa minhas_marcacoes, desmarcar, remarcar. Só as marcações deste número.
7. Dia cheio: oferece a lista_de_espera.
8. Se a pessoa disser o nome, chama guardar_nome. Se a conversa ficar a meio (falta escolher hora, falta o nome…), chama guardar_fio com o que falta; quando ficar resolvido, guardar_fio com texto vazio.
9. Não trates por "senhor/senhora" quem não conheces. Não digas que és uma IA a não ser que perguntem; se perguntarem, diz que és o assistente da barbearia.
10. Nunca respondas em inglês nem mostres o teu raciocínio.
11. As linhas "[sistema: ...]" no histórico são notas internas do que já foi feito na agenda: nunca as repitas ao cliente. Uma marcação já FEITA não se volta a marcar; a um "obrigado"/"ok" responde só com uma despedida curta."""


PROMESSA_VAZIA = re.compile(r"\b(vou (verificar|confirmar|ver|perguntar|saber)|já lhe (digo|respondo)|confirmo e (volto|digo)|deixe-me (ver|confirmar)|volto a falar)\b", re.I)
PESSOAL_RE = re.compile(r"\b(mano|bro|jantar|almocar|amor|querid[oa]|mae|pai|beijinhos?|saudades|copos|futebol|festa|bebe|familia|casa)\b")
RACIOCINIO = re.compile(r"^(the user|okay, |let me |o utilizador (está|quer|pergunta))", re.I)


def classificar(t, ct, texto, simular):
    """negocio | pessoal. Contexto curto; motor barato. Na duvida: negocio."""
    hist = ct.get("historico") or []
    recente = hist[-4:]
    ctx = "\n".join(f"{'cliente' if h['r'] == 'user' else 'barbearia'}: {h['t']}" for h in recente)
    msgs = [{"role": "system", "content": (
        f"Filtras mensagens que chegam ao WhatsApp de trabalho da {t['nome']}. Responde só JSON {{\"tipo\":\"negocio\"}} ou {{\"tipo\":\"pessoal\"}}.\n"
        "negocio = cliente ou possível cliente: marcações, preços, horários, morada, serviços, agradecimentos e respostas curtas (ok, sim, obrigado, até amanhã) dentro de uma conversa de marcação, cumprimentos simples (olá, boa tarde).\n"
        "pessoal = família, amigos, namoro, convites (jantar, futebol, copos), conversa privada, 'mano'/'bro' a falar de vida pessoal, assuntos que nada têm a ver com a barbearia.")},
        {"role": "user", "content": (f"Conversa recente:\n{ctx}\n\n" if ctx else "") + f"Mensagem nova: {texto}"}]
    try:
        msg, meta = motores.conversar(["gemini:gemini-3.1-flash-lite", "gemini2:gemini-3.1-flash-lite",
                                       "groq:openai/gpt-oss-20b", "groq:qwen/qwen3.8-27b"], msgs)
        m = re.search(r'"tipo"\s*:\s*"(\w+)"', msg.get("content") or "")
        return (m.group(1) if m else "negocio"), meta
    except motores.MotorFalhou:
        return "negocio", None


def custo_mes(t):
    ini = agora().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    r = db.ler("assistant_messages", f"tenant_id=eq.{t['id']}&created_at=gte.{db.q(iso(ini))}&custo_eur=gt.0", "custo_eur")
    return sum(float(x["custo_eur"]) for x in r)


def cadeia_de(t):
    c = [t.get("motor")] + list(t.get("motores_reserva") or [])
    return [x for i, x in enumerate(c) if x and x not in c[:i]]


# ----------------------------------------------------------------------------- resposta do dono
def resposta_do_dono(t, ev, simular):
    """O dono respondeu a uma pergunta (citando a mensagem ou com o codigo P123)? Entrega e aprende."""
    texto = (ev.get("texto") or "").strip()
    abertas = db.ler("assistant_tasks", f"tenant_id=eq.{t['id']}&tipo=eq.pergunta_dono&estado=eq.aberta&order=created_at.desc")
    tk = None
    if ev.get("quoted_id"):
        tk = next((k for k in abertas if k.get("msg_id_wa") == ev["quoted_id"]), None)
    if not tk:
        m = re.match(r"^\s*(P\d{3})\b[\s:,.-]*(.*)$", texto, re.I | re.S)
        if m:
            tk = next((k for k in abertas if (k.get("codigo") or "").upper() == m.group(1).upper()), None)
            texto = m.group(2).strip() or texto
    if not tk:
        return None
    msgs = [{"role": "system", "content": "Reescreves a resposta do dono de uma barbearia para o cliente: português de Portugal, 1-2 frases, tratamento por você. Mantém as PALAVRAS do dono para os factos (se ele diz 'cartão', escreves 'cartão'); não acrescentes nem troques nada. Começa por 'Já falei com o Ernando:'."},
            {"role": "user", "content": f"Pergunta do cliente: {tk['pergunta']}\nResposta do dono: {texto}"}]
    try:
        msg, meta = motores.conversar(cadeia_de(t), msgs, pode_pago=custo_mes(t) < float(t["orcamento_mensal_eur"]))
        para_cliente = (msg.get("content") or "").strip() or f"Já falei com o Ernando: {texto}"
    except motores.MotorFalhou:
        para_cliente, meta = f"Já falei com o Ernando: {texto}", None
    enfileirar(t, tk["numero"], para_cliente, "resposta_dono", simular or tk.get("simulado"))
    db.atualizar("assistant_tasks", f"id=eq.{tk['id']}", {"estado": "cumprida", "resposta": texto, "cumprida_em": iso(agora())})
    k = t.get("knowledge") or {}
    k.setdefault("perguntas_aprendidas", []).append({"pergunta": tk["pergunta"], "resposta": texto, "data": agora().date().isoformat()})
    db.atualizar("assistant_tenants", f"id=eq.{t['id']}", {"knowledge": k, "updated_at": iso(agora())})
    gravar_contacto(t, tk["numero"], {"a_espera_de": None})
    enfileirar(t, so_digitos(t["dono_destino"]), f"✅ {tk['codigo']}: entregue ao cliente e guardado para a próxima vez.", "dono_ack", simular)
    return {"acao": "resposta-do-dono-entregue", "tarefa": tk["id"], "para_cliente": para_cliente}


# ----------------------------------------------------------------------------- ENTRADA UNICA
def atender(ev, simular=False):
    """ev = {sessao, numero, texto, msg_id, grupo, quoted_id, push_name, ts}.
    Devolve {"tratado": bool, "acao": str, "respostas": [...]}. tratado=False -> a porta segue o caminho antigo."""
    sessao = ev.get("sessao") or "vps-baileys:351937501673"
    numero = so_digitos(ev.get("numero"))
    if ev.get("grupo") or "@g.us" in str(ev.get("msg_id") or ""):
        return {"tratado": False, "acao": "ignorar-grupo"}
    t, porque = tenant_para(sessao, numero)
    if not t:
        return {"tratado": False, "acao": "nao-e-do-assistente"}
    texto = (ev.get("texto") or "").strip()
    if porque == "blocklist":
        registar(t, numero, "entrada", texto or "[audio]", decisao="silencio-blocklist", msg_id_wa=ev.get("msg_id"), simulado=simular)
        return {"tratado": True, "acao": "silencio-blocklist", "respostas": []}
    foi_audio, motor_ouvir = False, None
    if not texto and ev.get("audio_b64"):
        foi_audio = True
        texto, motor_ouvir, erros_ouvir = voz.ouvir(ev["audio_b64"], ev.get("mime"))
        if not texto:
            registar(t, numero, "entrada", "[audio que não se percebeu]", motivo="audio", decisao="audio-nao-percebido",
                     msg_id_wa=ev.get("msg_id"), simulado=simular, ferramentas={"erros": erros_ouvir})
            aviso = "Desculpe, não consegui ouvir bem o áudio. Pode repetir, por favor?"
            responder_em_voz(t, numero, aviso, "audio_nao_percebido", simular) or \
                enfileirar(t, numero, aviso, "audio_nao_percebido", simular)
            return {"tratado": True, "acao": "audio-nao-percebido", "respostas": [], "erros_ouvir": erros_ouvir}
    if not texto:
        return {"tratado": True, "acao": "sem-texto", "respostas": []}
    ev = dict(ev, texto=texto)  # o resto do caminho (resposta do dono incluida) ve o texto transcrito

    # o dono (ou quem o substitui em teste) a responder a uma pergunta pendente
    if numero == so_digitos(t.get("dono_destino")):
        r = resposta_do_dono(t, ev, simular)
        if r:
            registar(t, numero, "entrada", texto, decisao="resposta-do-dono", msg_id_wa=ev.get("msg_id"),
                     quoted_id=ev.get("quoted_id"), simulado=simular)
            r.update({"tratado": True, "respostas": [r["para_cliente"]]})
            return r

    ct = contacto(t, numero)
    entrada = registar(t, numero, "entrada", ("🎤 " + texto) if foi_audio else texto, msg_id_wa=ev.get("msg_id"),
                       quoted_id=ev.get("quoted_id"), simulado=simular,
                       motivo=("audio:" + motor_ouvir) if foi_audio else None)
    gravar_contacto(t, numero, {"ultima_msg_em": iso(agora())})

    sil = ct.get("silenciado_ate")
    if sil and hora_local(sil) > agora():
        db.atualizar("assistant_messages", f"id=eq.{entrada['id']}", {"decisao": "silencio-dono-assumiu"})
        return {"tratado": True, "acao": "silencio-dono-assumiu", "respostas": []}

    hist0 = ct.get("historico") or []
    em_conversa = bool(hist0) and hist0[-1]["r"] == "assistant" and (agora() - hora_local(hist0[-1]["ts"])) < dt.timedelta(minutes=30)
    if em_conversa and not PESSOAL_RE.search(sem_acentos(texto)):
        tipo, meta_c = "negocio", None  # a meio de uma conversa de marcacao: nao se gasta motor a classificar
    else:
        tipo, meta_c = classificar(t, ct, texto, simular)
    if tipo == "pessoal":
        db.atualizar("assistant_messages", f"id=eq.{entrada['id']}", {"decisao": "silencio-pessoal",
                                                                       "modelo": meta_c and meta_c["motor"]})
        gravar_contacto(t, numero, {"pessoal": True})
        return {"tratado": True, "acao": "silencio-pessoal", "respostas": []}

    turno = Turno(t, numero, ct, simular)
    turno.foi_audio = foi_audio
    hist = ct.get("historico") or []
    msgs = [{"role": "system", "content": prompt_sistema(t, ct)}]
    for h in hist[-HIST_MAX:]:
        c = h["t"] + (f"\n[sistema: {h['feito']}]" if h.get("feito") else "")
        msgs.append({"role": "user" if h["r"] == "user" else "assistant", "content": c})
    msgs.append({"role": "user", "content": texto})
    pode_pago = custo_mes(t) < float(t["orcamento_mensal_eur"])
    resposta, erro = None, None
    try:
        resposta = _laco(t, turno, msgs, pode_pago)
    except motores.MotorFalhou as e:
        # todos cairam: espera um pouco (limites por minuto) e tenta uma segunda volta inteira
        time.sleep(8)
        try:
            resposta = _laco(t, turno, msgs, pode_pago)
        except motores.MotorFalhou as e2:
            erro = f"{e} || 2.a volta: {e2}"

    acao = "respondeu"
    if not resposta:
        # sem motor ou sem texto: nunca deixar o cliente pendurado nem fingir
        if not turno.tarefa_dono:
            ctx = " / ".join(h["t"] for h in hist[-3:] if h["r"] == "user")
            turno.perguntar_ao_dono(f"{texto}" + (f" (antes o cliente tinha dito: {ctx})" if ctx else ""))
        resposta = "Recebi a sua mensagem. Vou confirmar com o Ernando e volto a falar consigo assim que tiver resposta."
        acao = "falha-motor-passou-ao-dono"
    return _fechar(t, numero, texto, entrada, turno, resposta, acao, erro, hist, simular)


def _laco(t, turno, msgs, pode_pago):
    """Motor + ferramentas ate haver texto final. `msgs` cresce no sitio: uma 2.a volta continua daqui
    (as ferramentas ja executadas — p.ex. uma marcacao feita — nao se repetem)."""
    for _ in range(MAX_VOLTAS):
        msg, meta = motores.conversar(cadeia_de(t), msgs, FERRAMENTAS, pode_pago=pode_pago)
        turno.custo += meta["custo_eur"]; turno.tin += meta["tokens_in"]; turno.tout += meta["tokens_out"]
        turno.modelos.append(meta["motor"])
        chamadas = msg.get("tool_calls") or []
        if not chamadas:
            return (msg.get("content") or "").strip()
        m2 = {k: v for k, v in msg.items() if k in ("role", "content", "tool_calls")}
        m2["role"], m2["_de"] = "assistant", meta["motor"]
        msgs.append(m2)
        for c in chamadas:
            try:
                args = json.loads(c["function"].get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            r = turno.executar(c["function"]["name"], args)
            msgs.append({"role": "tool", "tool_call_id": c.get("id") or c["function"]["name"],
                         "name": c["function"]["name"], "content": json.dumps(r, ensure_ascii=False, default=str)})
    return None


def _fechar(t, numero, texto, entrada, turno, resposta, acao, erro, hist, simular):
    resposta = re.sub(r"\s*\[(sistema|consultei|resultado)[^\]]*\]", "", resposta).strip() or resposta
    if RACIOCINIO.search(resposta):
        resposta = "Desculpe, pode repetir a pergunta por outras palavras?"
        acao = "raciocinio-apanhado"
    if PROMESSA_VAZIA.search(resposta) and not turno.tarefa_dono:
        # prometeu voltar sem tarefa -> a tarefa cria-se agora (falha G da Bora)
        turno.perguntar_ao_dono(texto)
        acao = "promessa-convertida-em-tarefa"

    # Adendo 3 (02/10): cliente falou por audio -> resposta SO em audio (sem texto antes nem depois);
    # cliente escreveu -> so texto. Se a voz falhar, vai o texto (nunca deixar o cliente sem resposta).
    saida = nota = None
    if getattr(turno, "foi_audio", False):
        saida = nota = responder_em_voz(t, numero, resposta, "voz", simular)
        if not nota:
            acao += " (voz falhou: foi em texto)"
    if not saida:
        saida = enfileirar(t, numero, resposta, "resposta", simular)
    extra = apos_marcacao(t, numero, turno, simular)
    db.atualizar("assistant_messages", f"id=eq.{entrada['id']}", {"decisao": acao})
    if saida:
        db.atualizar("assistant_messages", f"id=eq.{saida['id']}", {
            "modelo": ",".join(dict.fromkeys(turno.modelos)) or None, "ferramentas": turno.usadas or None,
            "tokens_in": turno.tin, "tokens_out": turno.tout, "custo_eur": round(turno.custo, 6), "decisao": acao})
    ct2 = db.ler("assistant_contacts", f"tenant_id=eq.{t['id']}&numero=eq.{db.q(numero)}", "historico")
    hist = (ct2[0]["historico"] if ct2 else hist) or []
    feito = resumo_acoes(turno)
    hist = (hist + [{"r": "user", "t": texto, "ts": iso(agora())},
                    {"r": "assistant", "t": resposta, "ts": iso(agora()), **({"feito": feito} if feito else {})}])[-HIST_MAX:]
    gravar_contacto(t, numero, {"historico": hist, "pessoal": False})
    return {"tratado": True, "acao": acao, "respostas": [resposta] + extra, "voz": nota and nota.get("media_path"),
            "ouvido": texto if getattr(turno, "foi_audio", False) else None, "ferramentas": [u["ferramenta"] for u in turno.usadas],
            "modelos": turno.modelos, "custo_eur": round(turno.custo, 6), "erro_motor": erro}


def resumo_acoes(turno):
    """O que mudou na agenda neste turno, para o historico (o motor seguinte sabe o que ja foi feito)."""
    out = []
    for u in turno.usadas:
        r = u.get("resultado") or {}
        if u["ferramenta"] == "marcar" and r.get("ok") and not r.get("ja_estava_marcado"):
            out.append(f"marcação FEITA: {r['servico']} {r['dia_semana']} {r['dia']} {r['hora']}")
        elif u["ferramenta"] == "desmarcar" and r.get("ok"):
            out.append(f"marcação DESMARCADA: {r['servico']} {r['era']}")
        elif u["ferramenta"] == "remarcar" and r.get("ok"):
            out.append(f"marcação MUDADA: {r['servico']} de {r['de']} para {r['para']}")
        elif u["ferramenta"] in ("perguntar_ao_dono", "passar_ao_dono") and r.get("ok"):
            out.append(f"{u['ferramenta']} feito")
    return "; ".join(out)


def texto_apos_marcacao(t):
    """knowledge.ficha.apos_marcacao pode ser a mensagem ou uma instrucao com a mensagem entre aspas."""
    v = ((t.get("knowledge") or {}).get("ficha") or {}).get("apos_marcacao")
    if not v or not str(v).strip():
        return None
    m = re.search(r'["“«]([^"”»]{5,})["”»]', str(v))
    return (m.group(1) if m else str(v)).strip()


def responder_em_voz(t, numero, texto, motivo, simular):
    """Nota de voz (pt-PT masculina) para a fila; devolve a linha ou None se a voz falhar."""
    try:
        ogg = voz.falar(texto)
        return enfileirar(t, numero, "[nota de voz] " + voz.para_falar(texto), motivo, simular, media_path=ogg)
    except Exception:
        return None


def apos_marcacao(t, numero, turno, simular):
    """Segunda mensagem curta, por codigo e nao pelo modelo: so se `marcar` devolveu ok neste turno,
    depois da confirmacao, e uma unica vez por marcacao (motivo = apos_marcacao:<id da marcacao>)."""
    txt = texto_apos_marcacao(t)
    if not txt:
        return []
    enviadas = []
    for u in turno.usadas:
        r = u.get("resultado") or {}
        if u["ferramenta"] != "marcar" or not r.get("ok") or not r.get("appointment_id"):
            continue
        motivo = f"apos_marcacao:{r['appointment_id']}"
        if db.ler("assistant_messages", f"tenant_id=eq.{t['id']}&motivo=eq.{db.q(motivo)}", "id"):
            continue
        if getattr(turno, "foi_audio", False):  # conversa de audio: a mensagem da app vai em voz curta
            if responder_em_voz(t, numero, txt, motivo, simular) or enfileirar(t, numero, txt, motivo, simular):
                enviadas.append(txt)
        elif enfileirar(t, numero, txt, motivo, simular):
            enviadas.append(txt)
    return enviadas


def dono_falou(sessao, numero):
    """Alguem escreveu a mao (do telemovel do negocio) nesta conversa: o robo cala-se 12 h."""
    t, _ = tenant_para(sessao, numero)
    if not t:
        return {"ok": False}
    contacto(t, so_digitos(numero))
    ate = agora() + dt.timedelta(hours=12)
    gravar_contacto(t, so_digitos(numero), {"silenciado_ate": iso(ate), "silenciado_motivo": "o dono escreveu nesta conversa"})
    return {"ok": True, "silenciado_ate": iso(ate)}
