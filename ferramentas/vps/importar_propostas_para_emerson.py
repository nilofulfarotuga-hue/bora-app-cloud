"""Importa a linha "Propostas diárias" para a fila do caça-clientes do Emerson (bloco 6, 26/10/2026).

Ordem do Danilo (24/10 08:16): "Sim pode desligar mas passa tudo pro Emerson".
- contactados.csv (29): nenhuma empresa repetida (fonte_id único 'propostas:<slug>' + email);
  MOYO (devolução por spam) -> 'recusou': nunca mais recebe nada;
  quem já levou o último seguimento (followup2_final) -> 'sem_resposta' (parado);
  os outros -> 'enviada' com seguimentos=1 e o último seguimento já hoje: SÓ o último
  (ordem 26/10), na língua da empresa, com o link direto https://bora-demos.pages.dev/<slug>/,
  no mesmo fio do Gmail (thread_id + Message-ID lidos pelo canal do Emerson). Depois pára.
- leads_lote1.csv (34): os que ainda não foram contactados entram como 'novo' (sem email
  publicado não há envio).
Uso: python -I importar_propostas_para_emerson.py <raiz_repo> <contactados.csv> <leads.csv> <threads.json> [--aplicar]
"""
import csv
import json
import re
import sys
import unicodedata
import urllib.parse
import urllib.request

raiz, f_cont, f_leads, f_threads = sys.argv[1:5]
APLICAR = "--aplicar" in sys.argv
defs = json.loads(open(f"{raiz}/.dart_defines", encoding="utf-8-sig").read())
URL = defs["SUPABASE_URL"].rstrip("/")
CHAVE = next(l.split("=", 1)[1].strip().strip('"') for l in open(f"{raiz}/backend/.env", encoding="utf-8")
             if l.startswith("SUPABASE_SERVICE_ROLE_KEY="))
H = {"apikey": CHAVE, "Authorization": f"Bearer {CHAVE}", "Content-Type": "application/json"}


def rest(metodo, caminho, corpo=None, prefer=None):
    h = dict(H)
    if prefer:
        h["Prefer"] = prefer
    req = urllib.request.Request(f"{URL}/rest/v1/{caminho}", method=metodo, headers=h,
                                 data=json.dumps(corpo).encode() if corpo is not None else None)
    with urllib.request.urlopen(req, timeout=60) as r:
        t = r.read()
        return json.loads(t) if t else None


def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", " ", s).strip()


LINGUA = {"PT": "pt-PT", "LU": "fr", "CH": "fr", "FR": "fr", "US": "pt-BR"}
TEXTO_FINAL = {
    "pt-PT": ("Bom dia,\n\nÉ a última mensagem que enviamos sobre isto, para não incomodar. A demonstração "
              "que preparámos para a {empresa} continua aqui:\nhttps://bora-demos.pages.dev/{slug}/\n\n"
              "Se um dia fizer sentido ter um assistente a responder aos pedidos de orçamento a qualquer hora, "
              "basta responder a este email."),
    "fr": ("Bonjour,\n\nC'est notre dernier message à ce sujet, pour ne pas vous déranger. La démonstration "
           "préparée pour {empresa} reste disponible ici :\nhttps://bora-demos.pages.dev/{slug}/\n\n"
           "Si un jour un assistant qui répond aux demandes de devis à toute heure vous intéresse, il suffit "
           "de répondre à cet e-mail."),
    "en": ("Hello,\n\nThis is our last message about this, so we don't take more of your time. The demo we "
           "built for {empresa} is still here:\nhttps://bora-demos.pages.dev/{slug}/\n\n"
           "If an assistant that answers quote requests at any hour ever makes sense for you, just reply "
           "to this email."),
}

threads = {t["slug"]: t for t in json.load(open(f_threads, encoding="utf-8"))}
cont = list(csv.DictReader(open(f_cont, encoding="utf-8")))
leads = list(csv.DictReader(open(f_leads, encoding="utf-8")))
web_por_email = {(l.get("email_generico") or "").lower(): l.get("site") for l in leads if l.get("email_generico")}
emails = [c["email"].lower() for c in cont]
ja = rest("GET", "prospects_presenca?select=id,email,fonte_id,nome&or=(email.in.(" +
          ",".join(urllib.parse.quote(e) for e in emails) + "),fonte_id.like.propostas*)")
ja_email = {(x["email"] or "").lower() for x in ja}
ja_fonte = {x["fonte_id"] for x in ja}
print("ja na fila (email ou fonte):", len(ja))

linhas, resumo = [], {"enviada": 0, "sem_resposta": 0, "recusou": 0, "repetidos": 0, "leads_novos": 0}
for c in cont:
    slug, email = c["slug"], c["email"].lower()
    fonte = f"propostas:{slug}"
    if email in ja_email or fonte in ja_fonte:
        resumo["repetidos"] += 1
        continue
    t = threads.get(slug, {})
    est = c["estado"]
    lingua = "en" if slug == "algarve-fix" else LINGUA.get(c["pais"], "pt-PT")
    demo = f"https://bora-demos.pages.dev/{slug}/"
    if est.startswith("saida") or t.get("devolucoes"):
        estado, prop_estado, seg = "recusou", "email_invalido", 0
    elif est.startswith("followup2_final"):
        estado, prop_estado, seg = "sem_resposta", "sem_resposta", 2
    else:
        estado, prop_estado, seg = "enviada", "enviada", 1
    if t.get("respostas"):
        estado, prop_estado = "respondeu", "respondeu"  # nunca seguimento a quem respondeu
    resumo[estado if estado in resumo else "enviada"] += 1
    prospect = {
        "fonte_id": fonte, "nome": c["empresa"], "categoria": "obras-remodelacao",
        "email": email, "website": web_por_email.get(email), "email_verificado": estado != "recusou",
        "email_fonte": "site da empresa (linha Propostas diárias)", "canal_preferido": "email",
        "estado": estado, "lingua": lingua, "cliente_tipo": "funcionario-digital",
        "gancho": "assistente de orçamentos para empresas de obras",
        "notas": (f"Importado 26/10 da linha Propostas diárias (repo propostas). pais={c['pais']}; demo {demo}; "
                  f"estado antigo: {est}" + ("; seguimento 1 saltado (ordem 26/10: só o último)" if est == "enviado" else "")
                  + ("; SAIDA: nunca mais escrever" if estado == "recusou" else "")),
        "ultimo_contacto_em": c["data"] + "T09:00:00Z",
        "proximo_seguimento_em": "now" if estado == "enviada" else None,
    }
    proposta = {
        "canal": "email", "assunto": t.get("assunto") or f"{c['empresa']} — demonstração",
        "texto": f"(Importado: email original enviado a {c['data']} pela linha Propostas diárias; demo {demo})",
        "estado": prop_estado, "destinatario": email, "gmail_thread_id": c.get("thread_id") or None,
        "rfc_message_id": t.get("ultima_nossa_msgid") or None, "enviado_em": c["data"] + "T09:00:00Z",
        "seguimentos": seg, "enviar_agora": False,
        "seguimento_final_texto": TEXTO_FINAL[lingua].format(empresa=c["empresa"], slug=slug) if estado == "enviada" else None,
    }
    linhas.append((prospect, proposta))

nomes_cont = {norm(c["empresa"]) for c in cont}
leads_novos = []
for l in leads:
    fonte = "propostas-lead:" + norm(l["nome"]).replace(" ", "-")[:60]
    if norm(l["nome"]) in nomes_cont or fonte in ja_fonte or (l.get("email_generico") or "").lower() in emails:
        continue
    pais = {"Portugal": "PT", "Luxemburgo": "LU"}.get(l["pais"], "CH")
    leads_novos.append({
        "fonte_id": fonte, "nome": l["nome"], "categoria": "obras-remodelacao", "concelho": l.get("cidade"),
        "website": l.get("site"), "telefone": l.get("telefone"), "email": None, "email_verificado": False,
        "sem_site": not l.get("site"), "estado": "novo", "lingua": LINGUA.get(pais, "pt-PT"),
        "cliente_tipo": "funcionario-digital", "gancho": "assistente de orçamentos para empresas de obras",
        "notas": f"Lead do lote 1 da linha Propostas diárias (26/10). pais={pais}; prioridade {l.get('prioridade')}; sinais: {l.get('sinais')}",
    })
resumo["leads_novos"] = len(leads_novos)
print("resumo:", resumo)
for p, r in linhas[:3]:
    print(" ex:", p["nome"], p["estado"], p["lingua"], r["seguimentos"], (r["seguimento_final_texto"] or "")[:60].replace("\n", " "))
if not APLICAR:
    print("ensaio (sem --aplicar): nada escrito")
    sys.exit(0)

feitos = 0
for p, r in linhas:
    agora = p.pop("proximo_seguimento_em")
    novo = rest("POST", "prospects_presenca", p, prefer="return=representation")[0]
    if agora == "now":
        rest("PATCH", f"prospects_presenca?id=eq.{novo['id']}", {"proximo_seguimento_em": "2026-10-26T09:00:00Z"})
    r["prospect_id"] = novo["id"]
    rest("POST", "prospect_propostas", r, prefer="return=minimal")
    feitos += 1
if leads_novos:
    rest("POST", "prospects_presenca", leads_novos, prefer="return=minimal")
print("importados:", feitos, "contactados +", len(leads_novos), "leads")
CHAVE = None
