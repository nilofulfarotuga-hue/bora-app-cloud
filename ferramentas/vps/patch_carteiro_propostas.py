#!/usr/bin/env python3
"""Remendo do carteiro do caça-clientes (geral-sabado-24-10, bloco 6 — Propostas para o Emerson).

1. Trava (flock) no `enviar`: o cron das 09:40 e o de hora a hora (:05) podiam correr ao mesmo
   tempo e mandar o mesmo email duas vezes (a fila só marca depois de cada envio).
2. Último seguimento com o texto próprio da proposta (`texto_final`, na língua da empresa, com o
   link direto da demo) em vez do texto fixo em português.
3. Rodapé na língua da empresa (pt-PT, fr, en, pt-BR — EUA com morada física, CAN-SPAM).
4. Guardas antes de enviar: nunca "google.com/url" no corpo, nunca endereço .es (Espanha).
Cópia antes: carteiro_caca.py.bak-propostas-2026-10-26. Uso: python3 patch_carteiro_propostas.py
"""
import io
import shutil

F = "/opt/data/rotinas/carteiro_caca.py"
s = io.open(F, encoding="utf-8").read()
if "RODAPES = {" in s:
    print("ja remendado")
    raise SystemExit(0)
shutil.copy2(F, F + ".bak-propostas-2026-10-26")


def troca(a, b):
    global s
    assert s.count(a) == 1, a[:60]
    s = s.replace(a, b)


troca('''RODAPE = ("--" + chr(10) + ASSINATURA + chr(10) + "boraguarda.com" + chr(10) +
          "Se preferir não receber mais mensagens nossas, basta responder «não».")''',
'''RODAPE = ("--" + chr(10) + ASSINATURA + chr(10) + "boraguarda.com" + chr(10) +
          "Se preferir não receber mais mensagens nossas, basta responder «não».")
# 26/10/2026 (Propostas para o Emerson): rodapé na língua da empresa; EUA com morada (CAN-SPAM).
RODAPES = {
    "pt-PT": RODAPE,
    "fr": "--" + chr(10) + "Bora" + chr(10) + "boraguarda.com" + chr(10) +
          "Si vous préférez ne plus recevoir nos messages, il suffit de répondre « non ».",
    "en": "--" + chr(10) + "Bora" + chr(10) + "boraguarda.com" + chr(10) +
          "If you'd rather not hear from us again, just reply \\"no\\".",
    "pt-BR": "--" + chr(10) + "Bora · Rua do Torreão 14, 6300-610 Guarda, Portugal" + chr(10) +
             "Se preferir não receber mais mensagens nossas, é só responder «não».",
}


def rodape_de(lingua):
    return RODAPES.get((lingua or "pt-PT"), RODAPE)


def corpo_seguro(para, texto):
    """Nunca link embrulhado (cara de spam, já bloqueou a MOYO a 04/10); nunca Espanha (LSSI)."""
    if "google.com/url" in texto or "ust=" in texto:
        raise RuntimeError("corpo com link embrulhado (google.com/url) — nao envio")
    if (para or "").lower().strip().endswith(".es"):
        raise RuntimeError("endereco .es (Espanha) — nunca envio")''')

troca('''def enviar_email(para, assunto, texto, thread_id=None, em_resposta_a=None):
    m = EmailMessage()''', '''def enviar_email(para, assunto, texto, thread_id=None, em_resposta_a=None, rodape=None):
    corpo_seguro(para, texto)
    m = EmailMessage()''')
troca('''    m.set_content(texto.rstrip() + chr(10) + chr(10) + RODAPE + chr(10))''',
      '''    m.set_content(texto.rstrip() + chr(10) + chr(10) + (rodape or RODAPE) + chr(10))''')

troca('''def enviar(forcar=False):
    fila = rpc("carteiro_fila", {"p_forcar": forcar})''', '''def enviar(forcar=False):
    import fcntl
    trava = open("/tmp/carteiro_caca_enviar.lock", "w")
    try:
        fcntl.flock(trava, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("enviar: outro envio a correr — saio (sem repetir emails)")
        return
    fila = rpc("carteiro_fila", {"p_forcar": forcar})''')
troca('''                r = enviar_email(x["para"], x["assunto"], x["texto"])''',
      '''                r = enviar_email(x["para"], x["assunto"], x["texto"], rodape=rodape_de(x.get("lingua")))''')
troca('''                enviar_email(x["para"], assunto, SEGUIMENTO[int(x["numero"])], thread_id=x.get("thread_id"), em_resposta_a=x.get("rfc_message_id"))''',
      '''                texto_seg = x.get("texto_final") if int(x["numero"]) == 2 and x.get("texto_final") else SEGUIMENTO[int(x["numero"])]
                enviar_email(x["para"], assunto, texto_seg, thread_id=x.get("thread_id"),
                             em_resposta_a=x.get("rfc_message_id"), rodape=rodape_de(x.get("lingua")))''')
io.open(F, "w", encoding="utf-8").write(s)
print("remendado; copia em", F + ".bak-propostas-2026-10-26")
