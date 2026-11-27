"""Central do atendente de voz da Bora (missão atendente-voz-2026-11-25, bloco B2).

Fala o protocolo AudioSocket do Asterisk (TCP, áudio slin 8 kHz mono, 20 ms por pacote):
  ouvir  -> deteção de fala (webrtcvad) -> Groq whisper-large-v3-turbo (pt)
  pensar -> Edge Function voz-cerebro (Claude Opus 5.5; ferramentas e regras lá dentro)
  falar  -> edge-tts pt-PT (Raquel/Duarte) -> ffmpeg -> slin 8 kHz
e grava tudo pela Edge voz-ferramentas (chamada, falas, áudio no bucket privado, resumo, push).

Porquê sem Pipecat: o Pipecat não tem transporte AudioSocket nativo e a VPS tem 1 CPU e pouca RAM;
isto é a mesma cascata em ~400 linhas, sem modelos locais. Uma chamada de cada vez (VOZ_LINHAS).

Ambiente (.env da central, nunca no git): VOZ_SENHA (cabeçalho x-voz-token), GROQ_API_KEY,
SUPABASE_FN (https://<ref>.supabase.co/functions/v1), VOZ_PORTA (9092), VOZ_PASTA_CHAMADORES (/var/voz).
"""

import asyncio
import io
import json
import logging
import os
import random
import re
import struct
import time
import uuid
import wave

import httpx
import webrtcvad

LOG = logging.getLogger("central")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


def _env(nome: str, padrao: str = "") -> str:
    return os.environ.get(nome, padrao)


FN = _env("SUPABASE_FN", "https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1")
PORTA = int(_env("VOZ_PORTA", "9092"))
PASTA_CHAMADORES = _env("VOZ_PASTA_CHAMADORES", "/var/voz")

TAXA = 8000                 # slin 8 kHz
PACOTE = 320                # 20 ms de 16 bits mono
SILENCIO_FIM_MS = 600       # pausa que fecha uma frase
SILENCIO_MUDO_S = 8         # ninguém fala -> o cérebro recebe "[silêncio]"
INTERROMPER_MS = 240        # fala da pessoa por cima do atendente que o faz calar (barge-in)
ESPERA_APOS_S = 3.0         # só se o cérebro demorar mais do que isto é que se diz uma frase curta
# Ditas só quando o cérebro demora (procura longa), nunca a mesma duas vezes seguidas.
FRASES_ESPERA = ["Um segundo.", "Deixe-me confirmar.", "Só um instante.", "Vou verificar, um momento."]
MSG_OCUPADO = ("A linha está ocupada neste momento. Ligue dentro de momentos ou escreva para "
               "suporte arroba boraguarda ponto com. Obrigado.")
MSG_DESLIGADO = ("Olá, ligou para a Bora. De momento não temos atendimento por telefone. "
                 "Escreva para suporte arroba boraguarda ponto com e a equipa responde-lhe por escrito. Obrigado.")
NAO_GRAVAR = re.compile(r"n[aã]o (quero|aceito).{0,20}grava|sem grava|n[aã]o grave", re.I)

# Tipos do AudioSocket.
T_FIM, T_UUID, T_AUDIO, T_ERRO = 0x00, 0x01, 0x10, 0xFF

linhas = asyncio.Semaphore(int(_env("VOZ_LINHAS", "1")))
cache_tts: dict[str, bytes] = {}


async def edge(funcao: str, op: str, dados: dict, timeout: float = 30) -> dict:
    async with httpx.AsyncClient(timeout=timeout) as c:
        r = await c.post(f"{FN}/{funcao}", headers={"x-voz-token": _env("VOZ_SENHA")},
                         json={"op": op, "dados": dados})
        try:
            return r.json()
        except ValueError:
            return {"erro": f"http {r.status_code}"}


async def ouvir_texto(pcm: bytes) -> str:
    """Groq Whisper (rápido; a chave Groq já existe na VPS). Áudio curto em WAV 8 kHz."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(TAXA); w.writeframes(pcm)
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post("https://api.groq.com/openai/v1/audio/transcriptions",
                         headers={"Authorization": "Bearer " + _env("GROQ_API_KEY")},
                         files={"file": ("fala.wav", buf.getvalue(), "audio/wav")},
                         data={"model": "whisper-large-v3-turbo", "language": "pt", "temperature": "0"})
        if r.status_code != 200:
            LOG.warning("groq %s %s", r.status_code, r.text[:200])
            return ""
        return (r.json().get("text") or "").strip()


async def falar_pcm(texto: str, voz: str) -> bytes:
    """edge-tts (voz neural pt-PT) -> mp3 -> ffmpeg -> slin 8 kHz. Frases curtas ficam em cache."""
    chave = f"{voz}|{texto}"
    if chave in cache_tts:
        return cache_tts[chave]
    import edge_tts  # carregado só quando é preciso
    # O serviço da Microsoft falha ao acaso (~2 em 5 pedidos a 27/11/2026: NoAudioReceived).
    # Tenta várias vezes e, no fim, com a voz masculina pt-PT; só desiste se todas falharem.
    mp3, erro = bytearray(), None
    for tentativa, v in enumerate([voz, voz, voz, voz, "pt-PT-DuarteNeural", "pt-PT-DuarteNeural"]):
        mp3 = bytearray()
        try:
            async for parte in edge_tts.Communicate(texto, v).stream():
                if parte["type"] == "audio":
                    mp3.extend(parte["data"])
        except Exception as e:  # noqa: BLE001 — qualquer falha do serviço conta como tentativa
            erro = e
        if mp3:
            break
        await asyncio.sleep(0.15 * (tentativa + 1))
    if not mp3:
        raise RuntimeError(f"edge-tts sem áudio depois de várias tentativas: {erro}")
    p = await asyncio.create_subprocess_exec(
        "ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-f", "s16le", "-ac", "1", "-ar", str(TAXA), "pipe:1",
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
    pcm, _ = await p.communicate(bytes(mp3))
    if len(texto) < 200:
        cache_tts[chave] = pcm
    return pcm


def frases(texto: str) -> list[str]:
    return [p for p in re.split(r"(?<=[.!?])\s+", texto.strip()) if p]


async def falar(ch: "Chamada", texto: str, voz: str) -> tuple[bool, str]:
    """Fala frase a frase: a 1.ª começa logo e a seguinte prepara-se enquanto a outra toca.
    Devolve (interrompido, o que a pessoa chegou a ouvir)."""
    partes = frases(texto) or [texto]
    dito: list[str] = []
    ch.voz_seguida, ch.recente = 0, []
    proxima = asyncio.create_task(falar_pcm(partes[0], voz))
    for i, frase in enumerate(partes):
        try:
            pcm = await proxima
        except Exception as e:  # noqa: BLE001 — uma frase sem voz não derruba a chamada
            LOG.warning("frase sem voz: %s", e)
            pcm = b""
        if i + 1 < len(partes):
            proxima = asyncio.create_task(falar_pcm(partes[i + 1], voz))
        if pcm and await ch.tocar(pcm):
            if i + 1 < len(partes):
                proxima.cancel()
            dito.append(frase + " [interrompido aqui]")
            return True, " ".join(dito)
        dito.append(frase)
    return False, " ".join(dito)


class Chamada:
    def __init__(self, leitor: asyncio.StreamReader, escritor: asyncio.StreamWriter):
        self.r, self.w = leitor, escritor
        self.audio_entrada: asyncio.Queue[bytes] = asyncio.Queue()
        self.gravacao = bytearray()        # linha do tempo da chamada (quem fala, por ordem)
        self.aberta = True
        self.uuid = ""
        self.pre_fala = bytearray()        # o que a pessoa já disse quando interrompeu o atendente
        self.voz_seguida = 0               # contagem de voz por cima, contínua entre frases da mesma fala
        self.recente: list[bytes] = []

    async def ler(self):
        try:
            while self.aberta:
                cab = await self.r.readexactly(3)
                tipo, n = cab[0], struct.unpack(">H", cab[1:])[0]
                corpo = await self.r.readexactly(n) if n else b""
                if tipo == T_AUDIO:
                    await self.audio_entrada.put(corpo)
                elif tipo == T_UUID:
                    self.uuid = str(uuid.UUID(bytes=corpo))
                elif tipo in (T_FIM, T_ERRO):
                    break
        except (asyncio.IncompleteReadError, ConnectionError):
            pass
        self.aberta = False
        await self.audio_entrada.put(b"")

    async def tocar(self, pcm: bytes, interrompivel: bool = True) -> bool:
        """Manda áudio ao Asterisk ao ritmo real (20 ms por pacote) e grava-o na linha do tempo.
        Barge-in: se a pessoa falar por cima (INTERROMPER_MS de voz), o atendente cala-se logo e o que
        ela já disse fica em pre_fala para a frase seguinte. Devolve True se foi interrompido."""
        vad = webrtcvad.Vad(3)
        for i in range(0, len(pcm), PACOTE):
            if not self.aberta:
                return False
            bloco = pcm[i:i + PACOTE].ljust(PACOTE, b"\x00")
            self.w.write(bytes([T_AUDIO]) + struct.pack(">H", len(bloco)) + bloco)
            await self.w.drain()
            self.gravacao.extend(bloco)
            await asyncio.sleep(0.02)
            while not self.audio_entrada.empty():
                pac = self.audio_entrada.get_nowait()
                if not pac:                       # a chamada acabou: devolve o aviso à fila
                    await self.audio_entrada.put(b"")
                    return False
                self.recente = (self.recente + [pac])[-25:]
                fala = len(pac) == PACOTE and vad.is_speech(pac, TAXA)
                self.voz_seguida = self.voz_seguida + 1 if fala else max(0, self.voz_seguida - 1)
                if interrompivel and self.voz_seguida * 20 >= INTERROMPER_MS:
                    self.pre_fala = bytearray(b"".join(self.recente))
                    self.voz_seguida, self.recente = 0, []
                    return True
        return False

    async def ouvir_frase(self, limite_s: float) -> bytes | None:
        """Junta pacotes até haver fala seguida de SILENCIO_FIM_MS de pausa. None = silêncio total."""
        vad = webrtcvad.Vad(2)
        fala, ouviu, pausa_ms = bytearray(self.pre_fala), bool(self.pre_fala), 0
        self.gravacao.extend(self.pre_fala)
        self.pre_fala = bytearray()
        fim = time.monotonic() + limite_s
        while self.aberta:
            try:
                pac = await asyncio.wait_for(self.audio_entrada.get(), timeout=max(0.1, fim - time.monotonic()))
            except asyncio.TimeoutError:
                return bytes(fala) if ouviu else None
            if not pac:
                return bytes(fala) if ouviu else None
            self.gravacao.extend(pac)
            e_fala = len(pac) == PACOTE and vad.is_speech(pac, TAXA)
            if e_fala:
                ouviu, pausa_ms = True, 0
                fala.extend(pac)
            elif ouviu:
                fala.extend(pac)
                pausa_ms += 20
                if pausa_ms >= SILENCIO_FIM_MS:
                    return bytes(fala)
            if not ouviu and time.monotonic() >= fim:
                return None
        return bytes(fala) if ouviu else None

    def desligar(self):
        if self.aberta:
            try:
                self.w.write(bytes([T_FIM, 0, 0]))
            except Exception:
                pass
        self.aberta = False


def chamador_de(uid: str) -> str:
    """O dialplan escreve o número de quem liga em /var/voz/<uuid> antes de ligar à central."""
    try:
        with open(os.path.join(PASTA_CHAMADORES, uid)) as f:
            return f.read().strip()
    except OSError:
        return ""


async def atender(leitor: asyncio.StreamReader, escritor: asyncio.StreamWriter):
    ch = Chamada(leitor, escritor)
    tarefa_ler = asyncio.create_task(ch.ler())
    try:
        await asyncio.sleep(0.2)  # dá tempo ao pacote UUID
        uid = ch.uuid or str(uuid.uuid4())
        telefone = chamador_de(uid)
        cfg = await edge("voz-ferramentas", "config", {})
        defs = cfg.get("definicoes", {})
        voz = defs.get("voz_voz") or "pt-PT-RaquelNeural"
        if defs.get("voz_atendente_ativo") is not True:
            await ch.tocar(await falar_pcm(MSG_DESLIGADO, voz))
            return
        if linhas.locked():
            await ch.tocar(await falar_pcm(MSG_OCUPADO, voz))
            return
        async with linhas:
            await conversa(ch, uid, telefone, cfg, voz, defs)
    except Exception:
        LOG.exception("chamada falhou")
    finally:
        ch.desligar()
        tarefa_ler.cancel()
        try:
            escritor.close()
        except Exception:
            pass


async def conversa(ch: Chamada, uid: str, telefone: str, cfg: dict, voz: str, defs: dict):
    ab = await edge("voz-ferramentas", "abrir", {"telefone": telefone, "sip_call_id": uid, "motor": cfg.get("motor")})
    cid, quem, pedidos = ab.get("chamada_id"), ab.get("quem", {}), ab.get("pedidos", [])
    saudacao = defs.get("voz_saudacao") or ("Olá, está a falar com o assistente virtual da Bora. "
                                            "A chamada é gravada para qualidade. Em que posso ajudar?")
    t_inicio = time.monotonic()
    await ch.tocar(await falar_pcm(saudacao, voz))
    await edge("voz-ferramentas", "fala", {"chamada_id": cid, "quem": "atendente", "texto": saudacao, "ms": 0})

    mensagens, falas = [], [{"quem": "atendente", "texto": saudacao}]
    custo, escalado, consentiu, primeira_ms = 0.0, False, True, None
    interrompido, ouviu_so, ultima_espera = False, "", ""
    max_s = float(defs.get("voz_duracao_max_min") or 15) * 60
    while ch.aberta and time.monotonic() - t_inicio < max_s:
        pcm = await ch.ouvir_frase(SILENCIO_MUDO_S)
        if not ch.aberta:
            break
        t_fala = time.monotonic()
        texto = "[a pessoa não disse nada durante 8 segundos]" if pcm is None else await ouvir_texto(pcm)
        if not texto:
            texto = "[não se percebeu o que a pessoa disse]"
        if NAO_GRAVAR.search(texto):
            consentiu = False
        falas.append({"quem": "cliente", "texto": texto})
        asyncio.create_task(edge("voz-ferramentas", "fala", {"chamada_id": cid, "quem": "cliente", "texto": texto,
                                                             "ms": int((t_fala - t_inicio) * 1000)}))
        # Se a pessoa cortou o atendente, o cérebro sabe até onde ela ouviu (não repete tudo).
        para_cerebro = (f"[A pessoa interrompeu-te; só chegou a ouvir: «{ouviu_so}»] {texto}"
                        if interrompido else texto)
        mensagens.append({"role": "user", "content": para_cerebro})
        pensar = asyncio.create_task(edge("voz-cerebro", "responder", {
            "chamada_id": cid, "telefone": telefone, "quem": quem, "pedidos": pedidos,
            "mensagens": mensagens, "custo_acumulado_usd": custo}, timeout=60))
        # Frase curta de espera SÓ se o cérebro demorar (procura longa) e nunca a mesma seguida.
        if pcm is not None:
            feito, _ = await asyncio.wait({pensar}, timeout=ESPERA_APOS_S)
            if not feito:
                frase_espera = random.choice([f for f in FRASES_ESPERA if f != ultima_espera])
                ultima_espera = frase_espera
                try:
                    await ch.tocar(await falar_pcm(frase_espera, voz), interrompivel=False)
                except Exception as e:  # noqa: BLE001 — a espera nunca derruba a chamada
                    LOG.warning("frase de espera sem voz: %s", e)
        r = await pensar
        resposta = re.sub(r"\s+", " ", r.get("texto") or "").strip() or "Peço desculpa, pode repetir?"
        custo += float(r.get("custo_usd") or 0)
        escalado = escalado or bool(r.get("escalado"))
        mensagens.extend(r.get("novas_mensagens") or [{"role": "assistant", "content": resposta}])
        if primeira_ms is None and pcm is not None:
            primeira_ms = int((time.monotonic() - t_fala) * 1000)
        interrompido, ouviu_so = await falar(ch, resposta, voz)
        falas.append({"quem": "atendente", "texto": ouviu_so if interrompido else resposta})
        asyncio.create_task(edge("voz-ferramentas", "fala", {"chamada_id": cid, "quem": "atendente",
                                                             "texto": ouviu_so if interrompido else resposta,
                                                             "ms": int((time.monotonic() - t_inicio) * 1000)}))
        if r.get("terminar") and not interrompido:
            break

    ch.desligar()
    # Áudio (só com consentimento), resumo e fecho — mesmo que a pessoa tenha desligado.
    caminho = None
    if consentiu and ch.gravacao:
        up = await edge("voz-ferramentas", "audio_upload", {"chamada_id": cid, "ext": "wav"})
        if up.get("url"):
            buf = io.BytesIO()
            with wave.open(buf, "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(TAXA); w.writeframes(bytes(ch.gravacao))
            async with httpx.AsyncClient(timeout=60) as c:
                pr = await c.put(up["url"], content=buf.getvalue(), headers={"Content-Type": "audio/wav"})
                if pr.status_code < 300:
                    caminho = up["caminho"]
    rs = await edge("voz-cerebro", "resumir", {"falas": falas, "escalado": escalado})
    custo += float(rs.get("custo_usd") or 0)
    await edge("voz-ferramentas", "fechar", {
        "chamada_id": cid, "estado": rs.get("estado") or ("escalado" if escalado else "resolvido"),
        "resumo": rs.get("resumo"), "etiquetas": rs.get("etiquetas") or [], "custo_usd": round(custo, 5),
        "audio_path": caminho, "primeira_palavra_ms": primeira_ms, "gravacao_consentida": consentiu})
    LOG.info("chamada %s fechada: %.4f USD, escalado=%s", cid, custo, escalado)


async def vigia_diario():
    """Uma vez por dia: apaga áudios com mais de 90 dias (a Edge faz o trabalho)."""
    while True:
        r = await edge("voz-ferramentas", "limpar_audios", {})
        LOG.info("limpeza de áudios: %s", json.dumps(r)[:200])
        await asyncio.sleep(24 * 3600)


async def aquecer_frases():
    """Deixa as frases de espera já em cache (a voz da Microsoft falha ao acaso)."""
    for f in FRASES_ESPERA:
        try:
            await falar_pcm(f, "pt-PT-RaquelNeural")
        except Exception as e:  # noqa: BLE001
            LOG.warning("sem cache da frase de espera %r: %s", f, e)
    LOG.info("frases de espera em cache")


async def principal():
    # Só local: o Asterisk está na mesma máquina; ninguém de fora fala com a central.
    servidor = await asyncio.start_server(atender, _env("VOZ_ESCUTA", "127.0.0.1"), PORTA)
    LOG.info("central à escuta em %s", PORTA)
    asyncio.create_task(vigia_diario())
    asyncio.create_task(aquecer_frases())
    async with servidor:
        await servidor.serve_forever()


if __name__ == "__main__":
    asyncio.run(principal())
