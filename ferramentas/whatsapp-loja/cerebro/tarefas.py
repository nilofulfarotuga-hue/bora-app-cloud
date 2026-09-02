# -*- coding: utf-8 -*-
"""tarefas.py — PROMESSA = TAREFA COM PRAZO. A invencao que resolve a Falha A.

O modelo esta proibido de terminar com "vou ver"/"ja lhe digo" sem uma tarefa com prazo <= 3 min.
Quem garante e a VIGIA (thread): ao vencer o prazo, ou ja saiu a resposta com o resultado (a
tarefa foi cumprida), ou sai "ainda estou a ver, dou-lhe resposta em X min" + aviso ao Danilo.
Nunca fica em silencio. Tambem aqui: o seguimento de 24 h aos prospects e o cron de atrasos de
pedidos (2 em 2 min).

As tarefas vivem no Supabase (partilhadas pelas duas portas) com um ficheiro local de reserva.
"""
import datetime
import json
import os
import threading
import time
import uuid

from . import supa

LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_tarefas.json")
_lock = threading.Lock()


def _agora():
    return datetime.datetime.now(datetime.timezone.utc)


def _iso(dt):
    return dt.isoformat(timespec="seconds")


def _local_ler():
    try:
        return json.load(open(LOCAL, encoding="utf-8"))
    except Exception:
        return []


def _local_escrever(lst):
    try:
        json.dump(lst, open(LOCAL, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    except OSError:
        pass


def criar(numero, motivo, minutos=3, criada_por="agente"):
    """Devolve a tarefa (dict com id). Supabase; se falhar, fica local -- a vigia ve os dois."""
    t = {"id": str(uuid.uuid4()), "numero": numero, "motivo": (motivo or "")[:300],
         "prazo": _iso(_agora() + datetime.timedelta(minutes=minutos)), "estado": "aberta",
         "criada_por": criada_por}
    try:
        r = supa.insert("whatsapp_tasks", t)
        if r:
            return r[0] if isinstance(r, list) else r
    except Exception:
        pass
    with _lock:
        lst = _local_ler()
        lst.append(t)
        _local_escrever(lst)
    return t


def abertas(numero=None):
    out = []
    try:
        params = {"select": "*", "estado": "eq.aberta", "order": "prazo.asc"}
        if numero:
            params["numero"] = "eq." + numero
        out += supa.select("whatsapp_tasks", **params)
    except Exception:
        pass
    ids = {t["id"] for t in out}
    for t in _local_ler():
        if t.get("estado") == "aberta" and t["id"] not in ids and (not numero or t["numero"] == numero):
            out.append(t)
    return out


def vencidas():
    agora = _agora()
    out = []
    for t in abertas():
        try:
            prazo = datetime.datetime.fromisoformat(str(t["prazo"]).replace("Z", "+00:00"))
        except Exception:
            continue
        if prazo <= agora:
            out.append(t)
    return out


def fechar(tarefa_id, estado="cumprida", resultado=""):
    patch = {"estado": estado, "resultado": (resultado or "")[:300], "cumprida_em": _iso(_agora())}
    try:
        supa.update("whatsapp_tasks", patch, id="eq." + str(tarefa_id))
    except Exception:
        pass
    with _lock:
        lst = _local_ler()
        for t in lst:
            if t["id"] == tarefa_id:
                t.update(patch)
        _local_escrever(lst)


def cumprir_todas(numero, resultado="respondido"):
    """Quando sai uma resposta com resultado para este numero, as promessas abertas ficam cumpridas."""
    n = 0
    for t in abertas(numero):
        fechar(t["id"], "cumprida", resultado)
        n += 1
    return n


class Vigia(threading.Thread):
    """Corre no servidor. `emitir(numero, texto, motivo)` poe uma mensagem na fila de saida;
    `avisar(texto)` fala com o Danilo. Nunca decide sozinha o conteudo alem da frase de espera."""

    def __init__(self, emitir, avisar, registar, intervalo=20):
        super().__init__(daemon=True)
        self.emitir, self.avisar, self.registar, self.intervalo = emitir, avisar, registar, intervalo
        self._parar = threading.Event()

    def run(self):
        while not self._parar.is_set():
            try:
                self.tique()
            except Exception as e:  # noqa: BLE001
                self.registar({"evento": "vigia-erro", "erro": str(e)[:200]})
            self._parar.wait(self.intervalo)

    def tique(self):
        for t in vencidas():
            numero, motivo = t["numero"], t.get("motivo") or ""
            if (t.get("criada_por") or "").startswith("danilo-"):
                # o Danilo nao respondeu em 30 min -> volta-se a pessoa
                texto = "Ainda estou a tratar do seu assunto com o Danilo — não me esqueci. Assim que tiver novidade, digo-lhe aqui."
                fechar(t["id"], "expirada", "danilo sem resposta; cliente avisado")
                self.emitir(numero, texto, "vigia:danilo-sem-resposta")
                self.avisar("WhatsApp da loja — %s continua à espera de ti (%s). Já lhe disse que ainda estás a tratar." % (numero, motivo[:100]))
            else:
                texto = "Ainda estou a ver isso — dou-lhe resposta em 5 minutos, no máximo."
                fechar(t["id"], "expirada", "prazo venceu; cliente avisado; Danilo avisado")
                self.emitir(numero, texto, "vigia:prazo-vencido")
                self.avisar("WhatsApp da loja — prometi verificar a %s (%s) e não consegui a tempo. Precisa de ti." % (numero, motivo[:100]))
                # uma segunda tarefa, de 5 min, para nao ficar de novo em silencio
                criar(numero, "2a volta: " + motivo, 5, "vigia")
            self.registar({"evento": "vigia", "tarefa": t["id"], "numero": numero, "motivo": motivo[:120]})

    def parar(self):
        self._parar.set()


# ---------------------------------------------------------------- seguimento 24 h e atrasos
def seguimentos_24h():
    """Prospects a meio ha >24 h sem resposta e sem lembrete -> UM lembrete, uma vez so."""
    out = []
    try:
        limite = _iso(_agora() - datetime.timedelta(hours=24))
        leads = supa.select("whatsapp_leads", select="id,numero,tipo,dados,updated_at",
                            estado="in.(novo,em_recolha)", lembrete_enviado_em="is.null", updated_at="lt." + limite)
    except Exception:
        leads = []
    for l in leads:
        out.append(l)
    return out


def marcar_lembrete(lead_id):
    try:
        supa.update("whatsapp_leads", {"lembrete_enviado_em": _iso(_agora())}, id="eq." + str(lead_id))
    except Exception:
        pass


AVISADOS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_atrasos_avisados.json")


def pedidos_atrasados(media_min):
    """Pedidos activos ha mais tempo do que a media real -> avisar o cliente (um aviso por pedido)."""
    try:
        avisados = set(json.load(open(AVISADOS, encoding="utf-8")))
    except Exception:
        avisados = set()
    out = []
    try:
        rows = supa.select("orders", select="id,status,created_at,client_phone,vendor_name,assigned_driver_id",
                           status="not.in.(delivered,cancelled)", is_test_order="not.is.true", order="created_at.asc", limit="50")
    except Exception:
        rows = []
    agora = _agora()
    for o in rows:
        if o["id"] in avisados or not o.get("client_phone"):
            continue
        try:
            criado = datetime.datetime.fromisoformat(o["created_at"].replace("Z", "+00:00"))
        except Exception:
            continue
        minutos = (agora - criado).total_seconds() / 60
        if minutos > media_min:
            o["minutos"] = round(minutos)
            out.append(o)
            avisados.add(o["id"])
    try:
        json.dump(sorted(avisados), open(AVISADOS, "w", encoding="utf-8"))
    except OSError:
        pass
    return out


if __name__ == "__main__":
    t = criar("351000000000", "prova de tarefa", 0)
    print("criada:", t.get("id"), "| vencidas:", len(vencidas()))
    fechar(t["id"], "cumprida", "prova")
    print("abertas para o numero de prova:", len(abertas("351000000000")))
