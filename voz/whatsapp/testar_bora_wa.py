"""Conversas simuladas do WhatsApp da Bora (nada sai para o telemóvel: simulado=true, número de teste falso).

    cd /opt/assistente-negocio && python3 /opt/voz/voz/whatsapp/testar_bora_wa.py [aprender]

Mostra, mensagem a mensagem, o que a assistente responderia, quanto tempo levou e se a nota de voz ficou feita."""
import base64
import os
import sys
import time

sys.path.insert(0, "/opt/assistente-negocio")
os.chdir("/opt/assistente-negocio")
for l in open(".env", encoding="utf-8"):
    l = l.strip()
    if l and not l.startswith("#") and "=" in l:
        k, v = l.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"'))

import bora_wa  # noqa: E402

NUM = "351900000099"
t = bora_wa.tenant_bora()
assert t, "tenant bora não existe"


def manda(texto=None, audio_ogg=None, num=NUM):
    ev = {"numero": num, "texto": texto or "", "msg_id": f"teste-{time.time()}"}
    if audio_ogg:
        ev["audio_b64"] = base64.b64encode(open(audio_ogg, "rb").read()).decode()
        ev["mime"] = "audio/ogg"
    t0 = time.time()
    r = bora_wa.atender(t, "teste", ev, simular=True)
    print(f"\n>> {texto or '[áudio]'}\n   [{r.get('acao')} · {r.get('motor') or '-'} · {int((time.time() - t0) * 1000)} ms]")
    for x in r.get("respostas") or []:
        print("   " + x.replace("\n", "\n   "))
    return r


if len(sys.argv) > 1 and sys.argv[1] == "aprender":
    r = bora_wa.cerebro("aprender", {"canal": "whatsapp", "conversa": f"{t['id']}:{NUM}", "papel": "desconhecido", "falas": [
        {"quem": "pessoa", "texto": "Olá, o Jyosmi faz entregas?", "hora": "21:00"},
        {"quem": "assistente", "texto": "Olá! Está a falar com a assistente virtual da Bora. Claro, o Jyosmi Sushi está na app. Em que posso ajudar? Obrigada por ligar.", "hora": "21:00"},
        {"quem": "pessoa", "texto": "Ok obrigado", "hora": "21:01"}]}, 200)
    print({k: r.get(k) for k in ("ok", "nota", "falhas", "licoes_novas", "novas")})
    sys.exit(0)

manda("Boa noite")
manda("Queria saber se o Josemim está aberto agora")
manda("E quanto custa a entrega até à Sé?")
manda("Mano, logo vens jantar cá a casa? Tenho saudades", num="351900000098")
nota = bora_wa.falar("Olá, eu queria ser estafeta da Bora. Como é que faço?")
print("\n(nota de voz de teste feita:", nota, os.path.getsize(nota), "bytes)")
r = manda(audio_ogg=nota)
print("   resposta em voz:", bool(r.get("respostas")), "· ficheiros de voz recentes:",
      sorted(f for f in os.listdir(bora_wa.voz.PASTA_VOZ) if "-bora-" in f)[-2:])
