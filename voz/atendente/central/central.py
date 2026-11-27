"""Central do atendente de voz da Bora (missão atendente-voz-2026-11-25, bloco B2).

Fala o protocolo AudioSocket do Asterisk (TCP, áudio slin 8 kHz mono, 20 ms por pacote):
  ouvir  -> deteção de fala (webrtcvad) -> Groq whisper-large-v3-turbo (pt)
  pensar -> Edge Function voz-cerebro (Claude Opus 5.5; ferramentas e regras lá dentro)
  falar  -> voz da Google (Gemini TTS, pt-PT, sempre a mesma voz feminina) -> ffmpeg -> slin 8 kHz
            (recurso: edge-tts pt-PT Raquel, também feminina; nunca muda para voz de homem)
e grava tudo pela Edge voz-ferramentas (chamada, falas, áudio no bucket privado, resumo, push).

Porquê sem Pipecat: o Pipecat não tem transporte AudioSocket nativo e a VPS tem 1 CPU e pouca RAM;
isto é a mesma cascata em ~400 linhas, sem modelos locais. Uma chamada de cada vez (VOZ_LINHAS).

Ambiente (.env da central, nunca no git): VOZ_SENHA (cabeçalho x-voz-token), GROQ_API_KEY,
SUPABASE_FN (https://<ref>.supabase.co/functions/v1), VOZ_PORTA (9092), VOZ_PASTA_CHAMADORES (/var/voz),
GEMINI_TTS_KEY (chave Google da Bora, copiada de ficheiro para ficheiro na VPS), VOZ_GEMINI_TTS, VOZ_GEMINI_VOZ.
"""

import array
import asyncio
import base64
import io
import math
import json
import logging
import os
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
SILENCIO_FIM_MS = 500       # pausa que fecha uma frase (27/11: 600 -> 500, "demora")
SILENCIO_MUDO_S = 8         # ninguém fala -> o cérebro recebe "[silêncio]"
INTERROMPER_MS = 500        # voz forte da pessoa por cima do atendente que o faz calar (barge-in)
ENERGIA_INTERROMPER = 700   # RMS mínimo (int16) para um pacote contar como voz por cima (o eco é mais fraco)
VOZ_MINIMA_MS = 300         # menos voz do que isto numa "frase" = ruído, não vai ao Whisper
TTS_TIMEOUT_S = 2.5         # cada tentativa de voz tem este tempo máximo; falhou, passa logo à seguinte
# Frases que o Whisper inventa em ruído ou silêncio (português): nunca chegam ao cérebro.
ALUCINACOES = re.compile(
    r"^(obrigad[oa]( por (assistir|ver))?|tchau|legendas?\b.*|.*amara\.org.*|inscreva-se.*|"
    r"subt[ií]tulos.*|m[uú]sica|\W*)$", re.I)
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


def rms(pac: bytes) -> float:
    a = array.array("h", pac[: len(pac) // 2 * 2])
    return math.sqrt(sum(x * x for x in a) / len(a)) if a else 0.0


def voz_ms(pcm: bytes) -> int:
    """Quantos ms de voz a sério (VAD) há neste áudio."""
    vad = webrtcvad.Vad(2)
    n = 0
    for i in range(0, len(pcm) - PACOTE + 1, PACOTE):
        if vad.is_speech(pcm[i:i + PACOTE], TAXA):
            n += 1
    return n * 20


async def ouvir_texto(pcm: bytes) -> str:
    """Groq Whisper (rápido; a chave Groq já existe na VPS). Áudio curto em WAV 8 kHz.
    Ruído e alucinações do Whisper ("Obrigado.", "Legendas…") devolvem "" e não vão ao cérebro."""
    if voz_ms(pcm) < VOZ_MINIMA_MS:
        return ""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(TAXA); w.writeframes(pcm)
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.post("https://api.groq.com/openai/v1/audio/transcriptions",
                         headers={"Authorization": "Bearer " + _env("GROQ_API_KEY")},
                         files={"file": ("fala.wav", buf.getvalue(), "audio/wav")},
                         data={"model": "whisper-large-v3-turbo", "language": "pt", "temperature": "0",
                               "response_format": "verbose_json"})
        if r.status_code != 200:
            LOG.warning("groq %s %s", r.status_code, r.text[:200])
            return ""
        j = r.json()
    texto = (j.get("text") or "").strip()
    segs = j.get("segments") or []
    if segs:
        sem_fala = max(float(sg.get("no_speech_prob") or 0) for sg in segs)
        confianca = sum(float(sg.get("avg_logprob") or 0) for sg in segs) / len(segs)
        if sem_fala > 0.6 and confianca < -0.4:
            LOG.info("ignorado (sem fala %.2f, conf %.2f): %r", sem_fala, confianca, texto)
            return ""
    if ALUCINACOES.match(texto.strip(" .!?…")):
        LOG.info("ignorado (alucinação): %r", texto)
        return ""
    return texto


VOZ_GOOGLE = {"nome": _env("VOZ_GOOGLE", "")}
# 27/11/2026 (Danilo: "é uma pessoa só que atende", "demora"): a voz principal passa a ser a da Google
# (Gemini TTS em stream). Medido na VPS: 1.º áudio 0,66 s e frase de 6 s pronta em 1,4 s, sem as falhas
# da Microsoft (que obrigavam a trocar para a voz de homem e chegavam a 20 s).
GEMINI_MODELO = _env("VOZ_GEMINI_TTS", "gemini-3.8-flash-lite-tts")
GEMINI_VOZ = _env("VOZ_GEMINI_VOZ", "Kore")


async def gemini_pcm(texto: str) -> bytes:
    """Voz da Google pelo Gemini TTS (pt-PT), em stream; devolve slin 8 kHz."""
    chave = _env("GEMINI_TTS_KEY")
    corpo = {"contents": [{"parts": [{"text": texto}]}],
             "generationConfig": {"responseModalities": ["AUDIO"], "speechConfig": {
                 "languageCode": "pt-PT", "voiceConfig": {"prebuiltVoiceConfig": {"voiceName": GEMINI_VOZ}}}}}
    pcm24 = bytearray()
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODELO}:streamGenerateContent?alt=sse"
    async with httpx.AsyncClient(timeout=httpx.Timeout(10, connect=3)) as c:
        async with c.stream("POST", url, headers={"x-goog-api-key": chave}, json=corpo) as r:
            if r.status_code != 200:
                raise RuntimeError(f"gemini tts {r.status_code} {(await r.aread())[:150]!r}")
            async for linha in r.aiter_lines():
                if not linha.startswith("data:"):
                    continue
                d = json.loads(linha[5:])
                for parte in (d.get("candidates") or [{}])[0].get("content", {}).get("parts", []):
                    if "inlineData" in parte:
                        pcm24.extend(base64.b64decode(parte["inlineData"]["data"]))
    if not pcm24:
        raise RuntimeError("gemini tts sem áudio")
    p = await asyncio.create_subprocess_exec(
        "ffmpeg", "-loglevel", "error", "-f", "s16le", "-ar", "24000", "-ac", "1", "-i", "pipe:0",
        "-f", "s16le", "-ac", "1", "-ar", str(TAXA), "pipe:1",
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE)
    pcm, _ = await p.communicate(bytes(pcm24))
    return pcm


async def google_pcm(texto: str) -> bytes:
    """Google Text-to-Speech (pt-PT) direto em LINEAR16 8 kHz — rápido e estável. Só com GOOGLE_TTS_KEY."""
    chave = _env("GOOGLE_TTS_KEY")
    async with httpx.AsyncClient(timeout=TTS_TIMEOUT_S + 1) as c:
        if not VOZ_GOOGLE["nome"]:
            rv = await c.get("https://texttospeech.googleapis.com/v1/voices", params={"languageCode": "pt-PT", "key": chave})
            nomes = [v["name"] for v in rv.json().get("voices", [])]
            pref = [n for n in nomes if "Chirp3-HD" in n] or [n for n in nomes if "Neural2" in n] or \
                   [n for n in nomes if "Wavenet" in n] or nomes
            VOZ_GOOGLE["nome"] = pref[0] if pref else "pt-PT-Wavenet-A"
            LOG.info("voz Google: %s", VOZ_GOOGLE["nome"])
        r = await c.post("https://texttospeech.googleapis.com/v1/text:synthesize", params={"key": chave}, json={
            "input": {"text": texto},
            "voice": {"languageCode": "pt-PT", "name": VOZ_GOOGLE["nome"]},
            "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": TAXA}})
        if r.status_code != 200:
            raise RuntimeError(f"google tts {r.status_code} {r.text[:150]}")
        wav = base64.b64decode(r.json()["audioContent"])
    with wave.open(io.BytesIO(wav)) as w:
        return w.readframes(w.getnframes())


async def edge_mp3(texto: str, v: str) -> bytes:
    import edge_tts  # carregado só quando é preciso
    mp3 = bytearray()
    async for parte in edge_tts.Communicate(texto, v).stream():
        if parte["type"] == "audio":
            mp3.extend(parte["data"])
    return bytes(mp3)


async def falar_pcm(texto: str, voz: str) -> bytes:
    """Voz: Google TTS se houver chave; senão edge-tts (pt-PT). Cada tentativa tem TTS_TIMEOUT_S no
    máximo (a Microsoft falha ao acaso a partir da VPS e uma falha chegava a custar vários segundos).
    Frases curtas ficam em cache."""
    chave = f"{voz}|{texto}"
    if chave in cache_tts:
        return cache_tts[chave]
    if _env("GEMINI_TTS_KEY"):
        for tentativa in (1, 2):
            try:
                pcm = await asyncio.wait_for(gemini_pcm(texto), 4 + len(texto) / 40)
                if len(texto) < 200:
                    cache_tts[chave] = pcm
                return pcm
            except Exception as e:  # noqa: BLE001 — tenta outra vez; à 2.ª cai para a Microsoft
                LOG.warning("voz Google falhou (tentativa %s): %r", tentativa, e)
    if _env("GOOGLE_TTS_KEY"):
        try:
            pcm = await google_pcm(texto)
            if len(texto) < 200:
                cache_tts[chave] = pcm
            return pcm
        except Exception as e:  # noqa: BLE001 — cai para o edge-tts
            LOG.warning("google tts falhou: %s", e)
    mp3, erro = b"", None
    for v in [voz, voz, voz]:  # sempre a mesma voz (feminina): nunca troca para a do Duarte
        try:
            # Frases compridas demoram mais a sintetizar: o limite cresce com o texto (2,5 s + ~1 s por 70 letras).
            mp3 = await asyncio.wait_for(edge_mp3(texto, v), TTS_TIMEOUT_S + len(texto) / 70)
        except Exception as e:  # noqa: BLE001 — falha ou demora: tenta logo a seguinte
            erro = e or "tempo esgotado"
            mp3 = b""
        if mp3:
            break
    if not mp3:
        raise RuntimeError(f"voz sem áudio depois de várias tentativas: {erro!r}")
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


def resto(resposta: str, dito: str) -> str:
    """O que ficou por dizer de uma resposta cortada (a partir da frase interrompida, inclusive)."""
    cortada = "[interrompido aqui]" in dito
    ditas = frases(dito.replace(" [interrompido aqui]", ""))
    n = max(0, len(ditas) - (1 if cortada else 0))
    return " ".join(frases(resposta)[n:])


FIM_FRASE = re.compile(r"[.!?…](?=\s)")


async def cerebro_stream(dados: dict, fila: asyncio.Queue) -> dict:
    """Lê o NDJSON do voz-cerebro (op responder_stream) e mete cada frase completa na fila assim que
    chega. Devolve a linha final ("fim") com a resposta inteira e as mensagens para a conversa."""
    buf, fim, enviou = "", {}, False

    async def soltar(tudo: bool):
        nonlocal buf, enviou
        while True:
            m = FIM_FRASE.search(buf)
            if not m:
                break
            frase, buf = buf[:m.end()].strip(), buf[m.end():]
            if frase:
                await fila.put(frase)
                enviou = True
        if tudo and buf.strip():
            await fila.put(buf.strip())
            enviou = True
            buf = ""

    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(60, read=45)) as c:
            async with c.stream("POST", f"{FN}/voz-cerebro", headers={"x-voz-token": _env("VOZ_SENHA")},
                                json={"op": "responder_stream", "dados": dados}) as r:
                async for linha in r.aiter_lines():
                    if not linha.strip():
                        continue
                    try:
                        o = json.loads(linha)
                    except ValueError:
                        continue
                    t = o.get("t")
                    if t == "texto":
                        buf += o.get("v", "")
                        await soltar(False)
                    elif t == "pausa":
                        await soltar(True)
                    elif t == "fim":
                        fim = o
                    elif t == "erro":
                        LOG.warning("cérebro (stream): %s", o.get("v"))
        await soltar(True)
    except Exception as e:  # noqa: BLE001 — rede/servidor: a pessoa ouve uma desculpa, a chamada segue
        LOG.warning("cérebro falhou: %s", e)
    if not enviou:
        desculpa = "Peço desculpa, não percebi bem. Pode repetir, por favor?"
        await fila.put(desculpa)
        fim = fim or {"texto": desculpa}
    await fila.put(None)
    return fim


async def pipeline_voz(fila_txt: asyncio.Queue, fila_audio: asyncio.Queue, voz: str):
    """Transforma cada frase em som logo que chega (a seguinte prepara-se enquanto a anterior toca)."""
    while True:
        frase = await fila_txt.get()
        if frase is None:
            await fila_audio.put(None)
            return
        try:
            pcm = await falar_pcm(frase, voz)
        except Exception as e:  # noqa: BLE001 — uma frase sem voz não derruba a chamada
            LOG.warning("frase sem voz: %s", e)
            pcm = b""
        await fila_audio.put((frase, pcm))


async def tocar_fila(ch: "Chamada", fila_audio: asyncio.Queue) -> tuple[bool, str, float]:
    """Toca as frases pela ordem. Devolve (interrompido, o que a pessoa ouviu, hora da 1.ª voz)."""
    dito: list[str] = []
    t_primeira = 0.0
    ch.voz_seguida, ch.recente = 0, []
    while True:
        item = await fila_audio.get()
        if item is None:
            return False, " ".join(dito), t_primeira
        frase, pcm = item
        if not pcm:
            continue
        if not t_primeira:
            t_primeira = time.monotonic()
        if await ch.tocar(pcm):
            dito.append(frase + " [interrompido aqui]")
            return True, " ".join(dito), t_primeira
        dito.append(frase)


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
                self.recente = (self.recente + [pac])[-40:]
                fala = len(pac) == PACOTE and rms(pac) >= ENERGIA_INTERROMPER and vad.is_speech(pac, TAXA)
                self.voz_seguida = self.voz_seguida + 1 if fala else max(0, self.voz_seguida - 2)
                if interrompivel and self.voz_seguida * 20 >= INTERROMPER_MS:
                    LOG.info("interrompido pela pessoa (rms %.0f)", rms(pac))
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
    # Enquanto a saudação toca, o cérebro põe o prompt na cache do Claude: a 1.ª resposta sai mais cedo.
    asyncio.create_task(edge("voz-cerebro", "aquecer", {}, timeout=20))
    ab = await edge("voz-ferramentas", "abrir", {"telefone": telefone, "sip_call_id": uid, "motor": cfg.get("motor")})
    cid, quem, pedidos = ab.get("chamada_id"), ab.get("quem", {}), ab.get("pedidos", [])
    saudacao = defs.get("voz_saudacao") or ("Olá, está a falar com o assistente virtual da Bora. "
                                            "A chamada é gravada para qualidade. Em que posso ajudar?")
    t_inicio = time.monotonic()
    await ch.tocar(await falar_pcm(saudacao, voz))
    await edge("voz-ferramentas", "fala", {"chamada_id": cid, "quem": "atendente", "texto": saudacao, "ms": 0})

    mensagens, falas = [], [{"quem": "atendente", "texto": saudacao}]
    custo, escalado, consentiu, primeira_ms = 0.0, False, True, None
    interrompido, ouviu_so, pendente = False, "", ""
    max_s = float(defs.get("voz_duracao_max_min") or 15) * 60
    while ch.aberta and time.monotonic() - t_inicio < max_s:
        pcm = await ch.ouvir_frase(SILENCIO_MUDO_S)
        if not ch.aberta:
            break
        t_fala = time.monotonic()
        if pcm is None:
            texto = "[a pessoa não disse nada durante 8 segundos]"
        else:
            texto = await ouvir_texto(pcm)
            if not texto:
                # Ruído ou eco: não vai ao cérebro. Se tinha cortado o atendente a meio, ele continua.
                if interrompido and pendente:
                    LOG.info("interrupção falsa: continua a resposta")
                    interrompido, dito = await falar(ch, pendente, voz)
                    ouviu_so = (ouviu_so.replace(" [interrompido aqui]", "") + " " + dito).strip()
                    pendente = resto(pendente, dito) if interrompido else ""
                    if not interrompido:
                        interrompido, ouviu_so = False, ""
                continue
        if NAO_GRAVAR.search(texto):
            consentiu = False
        falas.append({"quem": "cliente", "texto": texto})
        asyncio.create_task(edge("voz-ferramentas", "fala", {"chamada_id": cid, "quem": "cliente", "texto": texto,
                                                             "ms": int((t_fala - t_inicio) * 1000)}))
        # Se a pessoa cortou o atendente, o cérebro sabe até onde ela ouviu (não repete tudo).
        para_cerebro = (f"[A pessoa interrompeu-te; só chegou a ouvir: «{ouviu_so}»] {texto}"
                        if interrompido else texto)
        mensagens.append({"role": "user", "content": para_cerebro})
        # O cérebro responde em stream: cada frase completa vai logo para a voz e é dita enquanto
        # ele ainda escreve a seguinte (ou corre uma ferramenta). Sem frases de espera fixas.
        fila_txt: asyncio.Queue = asyncio.Queue()
        fila_audio: asyncio.Queue = asyncio.Queue(maxsize=3)
        t_cerebro = asyncio.create_task(cerebro_stream({
            "chamada_id": cid, "telefone": telefone, "quem": quem, "pedidos": pedidos,
            "mensagens": mensagens, "custo_acumulado_usd": custo}, fila_txt))
        t_voz = asyncio.create_task(pipeline_voz(fila_txt, fila_audio, voz))
        interrompido, ouviu_so, t_primeira = await tocar_fila(ch, fila_audio)
        if not t_voz.done():
            t_voz.cancel()
        r = await t_cerebro
        if primeira_ms is None and pcm is not None and t_primeira:
            primeira_ms = int((t_primeira - t_fala) * 1000)
        resposta = re.sub(r"\s+", " ", r.get("texto") or "").strip() or "Peço desculpa, pode repetir?"
        custo += float(r.get("custo_usd") or 0)
        escalado = escalado or bool(r.get("escalado"))
        mensagens.extend(r.get("novas_mensagens") or [{"role": "assistant", "content": resposta}])
        pendente = resto(resposta, ouviu_so) if interrompido else ""
        falas.append({"quem": "atendente", "texto": ouviu_so if interrompido else resposta})
        asyncio.create_task(edge("voz-ferramentas", "fala", {"chamada_id": cid, "quem": "atendente",
                                                             "texto": ouviu_so if interrompido else resposta,
                                                             "ms": int((time.monotonic() - t_inicio) * 1000)}))
        LOG.info("volta: 1.ª voz %s ms depois de a pessoa acabar", int((t_primeira - t_fala) * 1000) if t_primeira else "-")
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
    """Deixa em cache as frases curtas que se repetem (a voz da Microsoft falha ao acaso)."""
    voz, frases = "pt-PT-RaquelNeural", [MSG_OCUPADO, MSG_DESLIGADO, "Peço desculpa, não percebi bem. Pode repetir, por favor?"]
    try:
        defs = (await edge("voz-ferramentas", "config", {})).get("definicoes", {})
        voz = defs.get("voz_voz") or voz
        if defs.get("voz_saudacao"):
            frases.insert(0, defs["voz_saudacao"])
    except Exception as e:  # noqa: BLE001
        LOG.warning("sem definições para aquecer: %s", e)
    frases.insert(0, "Olá, está a falar com o assistente virtual da Bora. "
                     "A chamada é gravada para qualidade. Em que posso ajudar?")
    for f in frases:
        try:
            await falar_pcm(f, voz)
        except Exception as e:  # noqa: BLE001
            LOG.warning("sem cache de %r: %s", f[:30], e)
    LOG.info("frases fixas em cache")


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
