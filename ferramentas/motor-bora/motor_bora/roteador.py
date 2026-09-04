# -*- coding: utf-8 -*-
"""roteador.py — o nucleo do Motor Bora (so biblioteca padrao).

  chamar(modelo_pedido, mensagens, ...)  modelo_pedido = "perfil:chat-rapido" | "groq:openai/gpt-oss-120b" | id solto
  - rotacao de chaves (GROQ_API_KEY=k1,k2 -> roda; 429 numa chave passa a seguinte)
  - failover entre fornecedores pela ordem do perfil
  - disjuntor: 429/5xx/timeout castigam o fornecedor (ou so o modelo) pelo tempo que o cabecalho
    disser (Retry-After, "try again in Xs", X-RateLimit-Reset), senao 65 s; 404 = modelo 24 h; 401/403 = 6 h
  - quota contada localmente (rpm/rpd/tpm do catalogo) para trocar ANTES do 429
  - descoberta viva (/models) valida os candidatos; auto-teste nocturno reordena os perfis
  - Telegram ao Danilo so quando 3 fornecedores seguidos falham (uma vez por 10 min), nunca por cada 429
"""
import collections
import datetime
import json
import os
import re
import threading
import time
import urllib.error
import urllib.request

from . import catalogo as C


def _hoje():
    return datetime.date.today().isoformat()


def _mediana(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else None


class Roteador:
    def __init__(self, env, maquina="pc", estado_path=None, avisar=None, registar=None, supa=None):
        self.env = dict(env or {})
        self.maquina = maquina
        self.estado_path = estado_path
        self.avisar = avisar or (lambda t: None)
        self.registar = registar or (lambda o: None)
        self.supa = supa
        self.lock = threading.Lock()
        self.castigos = {}          # "forn" | "forn|modelo" -> (ate_epoch, motivo)
        self.pausados = set()
        self.uso = {}
        self.modelos_vivos = {}     # forn -> set(ids); ausente = desconhecido (tenta-se na mesma)
        self.ultimo_erro = {}
        self.ordem = {p: list(v.get("candidatos") or []) for p, v in C.PERFIS.items()}
        self.chamadas = []
        self.chaves_rr = {}
        self.ultimo_aviso = 0.0
        self.autoteste_ultimo = None
        self.retirados = {}       # "forn:modelo" -> {quando, status, motivo}  (modelos que o fornecedor matou)
        self.mortes = {}          # contador antes de retirar (um 404 pontual nao chega)
        self.rr_perfil = {}       # rodizio: proximo indice por perfil
        self._carregar_estado()

    # ------------------------------------------------------------ chaves e urls
    def chaves(self, forn):
        spec = C.FORNECEDORES[forn]
        nome = spec.get("chave")
        if not nome:
            return [None]
        # GEMINI_API_KEYS=k1,k2 (plural) manda sobre GEMINI_API_KEY: o cerebro continua a ler a singular (uma chave)
        raw = self.env.get(nome + "S") or self.env.get(nome) or ""
        ks = [k.strip() for k in raw.split(",") if k.strip()]
        if not ks:
            return [None] if spec.get("opcional") else []
        i = self.chaves_rr.get(forn, 0)
        self.chaves_rr[forn] = i + 1
        return ks[i % len(ks):] + ks[:i % len(ks)]

    def tem_chave(self, forn):
        return bool(self.chaves(forn))

    def url(self, forn):
        u = C.FORNECEDORES[forn]["url"]
        if "{CLOUDFLARE_ACCOUNT_ID}" in u:
            u = u.replace("{CLOUDFLARE_ACCOUNT_ID}", self.env.get("CLOUDFLARE_ACCOUNT_ID", ""))
        return u

    # ------------------------------------------------------------ disjuntor
    def castigar(self, forn, modelo, segundos, motivo):
        with self.lock:
            self.castigos[forn + ("|" + modelo if modelo else "")] = (time.time() + segundos, motivo[:200])
            self.ultimo_erro[forn] = motivo[:300]

    def castigado(self, forn, modelo=None):
        with self.lock:
            for k in ([forn] + ([forn + "|" + modelo] if modelo else [])):
                c = self.castigos.get(k)
                if c and c[0] > time.time():
                    return c
                if c:
                    self.castigos.pop(k, None)
        return None

    # ------------------------------------------------------------ quota local
    POR_MODELO = ("groq", "gemini", "openrouter")   # nestes, os tectos por minuto sao POR MODELO (gpt-oss e qwen sao baldes diferentes)

    def _balde(self, forn, modelo=None):
        return forn + ("|" + modelo if modelo and forn in self.POR_MODELO else "")

    def _uso(self, forn):
        u = self.uso.get(forn)
        if not u:
            u = self.uso[forn] = {"min": collections.deque(), "hora": collections.deque(), "dia": _hoje(), "rpd": 0,
                                  "tokens_dia": 0, "custo_dia": 0.0, "lat": collections.deque(maxlen=60), "ok": 0, "falhas": 0}
        u.setdefault("hora", collections.deque())
        u.setdefault("custo_dia", 0.0)
        if u["dia"] != _hoje():
            u.update(dia=_hoje(), rpd=0, tokens_dia=0, custo_dia=0.0, ok=0, falhas=0)
        agora = time.time()
        while u["min"] and u["min"][0][0] < agora - 60:
            u["min"].popleft()
        while u["hora"] and u["hora"][0] < agora - 3600:
            u["hora"].popleft()
        return u

    def quota_ok(self, forn, tokens_est, modelo=None):
        lim = C.FORNECEDORES[forn].get("limites") or {}
        u = self._uso(forn)
        b = self._uso(self._balde(forn, modelo)) if modelo and forn in self.POR_MODELO else u
        if lim.get("rpm") and len(b["min"]) >= lim["rpm"]:
            return False, "rpm %d/min" % lim["rpm"]
        if lim.get("rph") and len(u["hora"]) >= lim["rph"]:
            return False, "rph %d/hora" % lim["rph"]
        if lim.get("rpd") and u["rpd"] >= lim["rpd"]:
            return False, "rpd %d/dia" % lim["rpd"]
        if lim.get("tpm") and sum(t for _t, t in b["min"]) + tokens_est > lim["tpm"]:
            return False, "tpm %d/min" % lim["tpm"]
        return True, ""

    def contar(self, forn, tokens, ms, ok, modelo=None):
        for chave in {forn, self._balde(forn, modelo)}:
            u = self._uso(chave)
            u["min"].append((time.time(), int(tokens or 0)))
            u["hora"].append(time.time())
            if chave == forn:
                u["rpd"] += 1
                u["tokens_dia"] += int(tokens or 0)
                # CUSTO SIMULADO: nao se paga nada; e o que isto custaria ao preco de tabela do fornecedor
                u["custo_dia"] += (int(tokens or 0) / 1_000_000.0) * C.PRECO_POR_MILHAO.get(forn, 0.0)
                if ok:
                    u["ok"] += 1
                    u["lat"].append(ms)
                else:
                    u["falhas"] += 1

    # ------------------------------------------------------------ vigia de modelos mortos
    MORTO = re.compile(r"model_not_found|does not exist|no such model|decommission|deprecat|retirement|"
                       r"has been (removed|retired|sunset)|unknown model|invalid model|model .* not (found|available)", re.I)

    def _talvez_retirar(self, forn, modelo, status, corpo):
        """404/410 ou mensagem de modelo morto -> sai da lista deste perfil e fica registado no relatorio.
        Um 404 pontual nao chega: exige-se 2 vezes, para nao apagar um modelo por causa de um soluco."""
        txt = json.dumps(corpo)[:600]
        if status not in (404, 410) and not self.MORTO.search(txt):
            return False
        chave = forn + ":" + modelo
        self.mortes[chave] = self.mortes.get(chave, 0) + 1
        if self.mortes[chave] < 2:
            return False
        if chave in self.retirados:
            return True
        self.retirados[chave] = {"quando": datetime.datetime.now().isoformat(timespec="seconds"),
                                 "status": status, "motivo": (txt[:200] or "").replace("\n", " ")}
        for p, ordem in self.ordem.items():
            self.ordem[p] = [x for x in ordem if not (x[0] == forn and x[1] == modelo)]
        self.registar({"evento": "modelo-retirado", "fornecedor": forn, "modelo": modelo, "status": status,
                       "motivo": self.retirados[chave]["motivo"][:160]})
        try:
            self.avisar("Motor Bora (%s): tirei o modelo %s da lista — o fornecedor diz que já não existe (%s). "
                        "Fica escrito no MOTORES.md; a fila segue com os outros." % (self.maquina, chave, status))
        except Exception:
            pass
        self.guardar_estado()
        return True

    # ------------------------------------------------------------ http
    def _http(self, forn, chave, caminho, corpo=None, timeout=30):
        h = {"Content-Type": "application/json", "Accept": "application/json", "User-Agent": C.UA_BROWSER}
        if chave:
            h["Authorization"] = "Bearer " + chave
        if forn == "openrouter":
            h["HTTP-Referer"] = "https://boraguarda.com"
            h["X-Title"] = "Bora Guarda"
        dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8") if corpo is not None else None
        req = urllib.request.Request(self.url(forn) + caminho, data=dados, headers=h, method="POST" if corpo is not None else "GET")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read().decode("utf-8", "replace")
                return r.status, (json.loads(raw) if raw.strip() else {}), {k.lower(): v for k, v in r.headers.items()}
        except urllib.error.HTTPError as e:
            try:
                b = e.read()[:1200].decode("utf-8", "replace")
            except Exception:
                b = ""
            return e.code, {"_erro": b}, {k.lower(): v for k, v in (e.headers or {}).items()}
        except Exception as e:  # noqa: BLE001
            return 0, {"_erro": "%s: %s" % (type(e).__name__, str(e)[:200])}, {}

    def _segundos_de_castigo(self, status, corpo, headers):
        ra = headers.get("retry-after")
        if ra and str(ra).strip().isdigit():
            return min(int(ra), 3600)
        txt = json.dumps(corpo)[:800]
        m = re.search(r"try again in (?:(\d+)m)?([\d.]+)s", txt)
        if m:
            return min(int(m.group(1) or 0) * 60 + int(float(m.group(2))) + 2, 3600)
        reset = headers.get("x-ratelimit-reset")
        if reset and str(reset).replace(".", "").isdigit():
            v = float(reset)
            v = v / 1000 if v > 1e12 else v
            if v > time.time():
                return min(int(v - time.time()) + 1, 3600)
        low = txt.lower()
        if status == 429:
            return 600 if ("day" in low or "daily" in low or "quota" in low or "limit reached" in low and "month" in low) else 65
        if status in (401, 403):
            return 3600 * 6
        if status == 404:
            return 3600 * 24
        if status == 0:
            return 45
        return 60

    # ------------------------------------------------------------ descoberta viva
    def descobrir(self):
        for forn, spec in C.FORNECEDORES.items():
            if not spec.get("modelos"):
                continue
            ks = self.chaves(forn)
            if not ks:
                continue
            st, d, _h = self._http(forn, ks[0], spec["modelos"], None, 20)
            if st == 200 and isinstance(d, dict) and isinstance(d.get("data"), list):
                ids = {m.get("id") for m in d["data"] if isinstance(m, dict) and m.get("id")}
                if spec.get("so_free"):        # OpenRouter e Kilo: os pagos exigem conta/creditos -> so os ":free"
                    ids = {i for i in ids if i.endswith(":free")}
                if forn == "gemini":
                    ids = {i.replace("models/", "") for i in ids}
                ids -= {k.split(":", 1)[1] for k in self.retirados if k.startswith(forn + ":")}
                self.modelos_vivos[forn] = ids
                self.registar({"evento": "descoberta", "fornecedor": forn, "modelos": len(ids)})
            else:
                self.registar({"evento": "descoberta-falhou", "fornecedor": forn, "status": st, "erro": str(d)[:160]})

    def _procurar_modelo(self, mid):
        for forn, ids in self.modelos_vivos.items():
            if mid in ids:
                return (forn, mid)
        for p in C.PERFIS.values():
            for forn, m in p.get("candidatos") or []:
                if m == mid:
                    return (forn, m)
        return None

    # ------------------------------------------------------------ escolha e chamada
    def candidatos(self, perfil, so_sensivel_ok=True):
        out = []
        for forn, modelo in self.ordem.get(perfil, []):
            spec = C.FORNECEDORES.get(forn)
            if not spec or forn in self.pausados:
                continue
            if so_sensivel_ok and not spec.get("sensivel_ok", True):
                continue
            if not self.chaves(forn):
                continue
            if (forn + ":" + modelo) in self.retirados:
                continue
            vivos = self.modelos_vivos.get(forn)
            if vivos and modelo not in vivos:
                continue
            if self.castigado(forn, modelo):
                continue
            out.append((forn, modelo))
        return out

    def _rodar(self, perfil, lista, p):
        """RODIZIO (04/09): em vez de bater sempre no mesmo primeiro, roda entre os `rodizio_topo` melhores
        a cada pedido e so depois desce a cadeia. Uma rajada espalha-se por varios fornecedores em vez de
        esgotar o tecto por minuto de um so. Fora do topo a ordem mantem-se (o resto continua cadeia)."""
        if p.get("modo") != "rodizio" or len(lista) < 2:
            return lista
        n = min(int(p.get("rodizio_topo") or 3), len(lista))
        with self.lock:
            i = self.rr_perfil.get(perfil, 0)
            self.rr_perfil[perfil] = (i + 1) % max(n, 1)
        topo = lista[:n]
        topo = topo[i % n:] + topo[:i % n]
        return topo + lista[n:]

    def chamar(self, modelo_pedido, mensagens, tools=None, max_tokens=None, temperatura=0.2, timeout=None, origem=""):
        perfil, alvo = None, None
        mp = (modelo_pedido or "").strip()
        if mp.startswith("perfil:"):
            perfil = mp[7:]
        elif ":" in mp and mp.split(":", 1)[0] in C.FORNECEDORES and not mp.split(":", 1)[0] == "ollama" or (mp.startswith("ollama:") and mp.count(":") >= 2):
            alvo = tuple(mp.split(":", 1))
        elif mp in ("", "auto", "motor-bora", "motor", "bora"):
            perfil = "chat-rapido"
        else:
            alvo = self._procurar_modelo(mp)
            if not alvo:
                perfil = "chat-rapido"
        if perfil and perfil not in C.PERFIS:
            perfil = "chat-rapido"
        p = C.PERFIS.get(perfil or "chat-rapido")
        lista = [alvo] if alvo else self._rodar(perfil, self.candidatos(perfil, p.get("sensivel", True)), p)
        if not lista:
            return {"error": {"message": "sem fornecedor disponivel para %s (sem chaves, castigados ou pausados)" % mp, "type": "motor_bora"}, "tentativas": []}
        t_ini = time.time()
        tentativas = []
        falhas_seguidas = 0
        tokens_est = len(json.dumps(mensagens, ensure_ascii=False)) // 4 + int(max_tokens or p.get("max_tokens") or 300)
        for forn, modelo in lista:
            if time.time() - t_ini > p.get("orcamento", 60):
                tentativas.append({"parou": "orcamento do perfil esgotado"})
                break
            if not alvo:
                ok_q, motivo_q = self.quota_ok(forn, tokens_est, modelo)
                if not ok_q:
                    tentativas.append({"fornecedor": forn, "modelo": modelo, "saltado": "quota local " + motivo_q})
                    continue
            spec = C.FORNECEDORES[forn]
            # pedido maior do que o tecto de tokens/min do fornecedor (o Hermes manda 10-20k tokens; o Groq gratis
            # aceita 8k): nem se tenta -- o 429 seria certo e gastava tempo
            lim_tpm = (spec.get("limites") or {}).get("tpm")
            if lim_tpm and tokens_est > lim_tpm and not alvo:
                tentativas.append({"fornecedor": forn, "modelo": modelo, "saltado": "pedido de ~%d tokens > tpm %d" % (tokens_est, lim_tpm)})
                continue
            corpo = {"model": modelo, "messages": mensagens, "max_tokens": int(max_tokens or p.get("max_tokens") or 300), "temperature": temperatura}
            if "gpt-oss" in modelo or "deepseek-r1" in modelo or "qwen3" in modelo.lower():
                # modelos "pensantes": o raciocinio gasta o max_tokens e vem uma resposta vazia (visto 02/09, max_tokens=80)
                corpo["max_tokens"] = max(corpo["max_tokens"], 320)
                if "gpt-oss" in modelo:
                    corpo["reasoning_effort"] = "low"
            if forn == "kilo" or modelo.endswith(":free"):
                # 04/09: os ":free" do Kilo pensam antes de escrever; com tecto curto devolvem 200 com texto vazio
                corpo["max_tokens"] = max(corpo["max_tokens"], 500)
            if tools and forn not in ("ovh", "llm7", "cloudflare"):
                corpo["tools"] = tools
            # tempo por fornecedor: o do perfil, ou o minimo do fornecedor (Zen/Ollama sao lentos), mas nunca alem do
            # orcamento que resta ao perfil -- no chat-rapido o Zen tem 12 s, no raciocinio tem 90 s
            resta = max(3, p.get("orcamento", 60) - (time.time() - t_ini))
            tmo = timeout or min(max(p.get("timeout", 30), spec.get("timeout_min") or 0), resta)
            chaves = self.chaves(forn) or [None]
            for i_chave, chave in enumerate(chaves):
                t0 = time.time()
                st, d, h = self._http(forn, chave, "/chat/completions", corpo, tmo)
                ms = int((time.time() - t0) * 1000)
                if st == 200 and isinstance(d, dict) and d.get("choices"):
                    msg = (d["choices"][0].get("message") or {})
                    texto = msg.get("content") or ""
                    if isinstance(texto, list):
                        texto = "".join(x.get("text", "") for x in texto if isinstance(x, dict))
                    if not (texto or "").strip():          # ha gateways que poem a resposta no campo do raciocinio
                        alt = msg.get("reasoning_content") or msg.get("reasoning") or ""
                        texto = alt if isinstance(alt, str) else ""
                    texto = re.sub(r"<think>.*?</think>\s*", "", texto, flags=re.S)
                    texto = re.sub(r"<think>.*$", "", texto, flags=re.S).strip()
                    msg["content"] = texto
                    d["choices"][0]["message"] = msg
                    if not texto and not msg.get("tool_calls"):
                        self.contar(forn, tokens_est, ms, False, modelo)
                        self.castigar(forn, modelo, 120, "resposta vazia")
                        tentativas.append({"fornecedor": forn, "modelo": modelo, "ms": ms, "erro": "resposta vazia"})
                        break
                    usage = d.get("usage") or {}
                    tokens = int(usage.get("total_tokens") or tokens_est)
                    self.contar(forn, tokens, ms, True, modelo)
                    self._registar_chamada(perfil, forn, modelo, True, ms, tokens, None, origem)
                    d["model"] = forn + ":" + modelo
                    d["motor"] = {"fornecedor": forn, "modelo": modelo, "latencia_ms": ms, "perfil": perfil, "tentativas": tentativas,
                                  "maquina": self.maquina, "chave": (i_chave + 1) if chave else None}
                    return d
                erro = str((d or {}).get("_erro") or d)[:400]
                self.contar(forn, 0, ms, False, modelo)
                self._registar_chamada(perfil, forn, modelo, False, ms, 0, "HTTP %s %s" % (st, erro[:150]), origem)
                seg = self._segundos_de_castigo(st, d, h)
                if st == 429 and i_chave < len(chaves) - 1:
                    tentativas.append({"fornecedor": forn, "modelo": modelo, "ms": ms, "status": 429, "erro": "429 nesta chave; roda para a seguinte"})
                    continue
                if self._talvez_retirar(forn, modelo, st, d):
                    tentativas.append({"fornecedor": forn, "modelo": modelo, "ms": ms, "status": st, "erro": "modelo retirado da lista (o fornecedor diz que ja nao existe)"})
                    break
                so_modelo = (st in (404, 410)) or (st == 429 and forn in ("groq", "gemini", "openrouter", "kilo")) or (st == 400 and "model" in erro.lower())
                self.castigar(forn, modelo if so_modelo else None, seg, "HTTP %s %s" % (st, erro[:160]))
                tentativas.append({"fornecedor": forn, "modelo": modelo, "ms": ms, "status": st, "erro": erro[:200], "castigo_s": seg})
                break
            falhas_seguidas += 1
            if falhas_seguidas == 3 and time.time() - self.ultimo_aviso > 600:
                self.ultimo_aviso = time.time()
                try:
                    self.avisar("Motor Bora (%s): 3 fornecedores seguidos falharam no perfil %s — %s. Continuo a descer a lista." % (
                        self.maquina, perfil or mp, "; ".join("%s: %s" % (t.get("fornecedor"), (t.get("erro") or t.get("saltado") or "")[:60]) for t in tentativas[-3:])))
                except Exception:
                    pass
        return {"error": {"message": "todos os fornecedores falharam para %s" % mp, "type": "motor_bora", "tentativas": tentativas}, "tentativas": tentativas}

    # ------------------------------------------------------------ registo e estado
    def _registar_chamada(self, perfil, forn, modelo, ok, ms, tokens, erro, origem):
        with self.lock:
            self.chamadas.append({"maquina": self.maquina, "perfil": perfil, "fornecedor": forn, "modelo": modelo, "ok": ok,
                                  "latencia_ms": ms, "tokens": tokens, "erro": (erro or "")[:200] or None,
                                  "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")})
            del self.chamadas[:-500]
        self.registar({"evento": "chamada", "origem": origem, "perfil": perfil, "fornecedor": forn, "modelo": modelo, "ok": ok, "ms": ms, "erro": erro})

    def estado(self):
        out = {}
        for forn, spec in C.FORNECEDORES.items():
            u = self._uso(forn)
            c = self.castigado(forn)
            cm = [k.split("|", 1)[1] for k, v in list(self.castigos.items()) if k.startswith(forn + "|") and v[0] > time.time()]
            lim = spec.get("limites") or {}
            out[forn] = {"chave": bool(self.chaves(forn)), "pausado": forn in self.pausados,
                         "custo_simulado_eur_hoje": round(u.get("custo_dia", 0.0), 4),
                         "ultima_hora": len(u.get("hora") or []),
                         "modelos_retirados": [k.split(":", 1)[1] for k in self.retirados if k.startswith(forn + ":")],
                         "castigado_ate": datetime.datetime.fromtimestamp(c[0]).isoformat(timespec="seconds") if c else None,
                         "castigo_motivo": c[1] if c else None, "modelos_castigados": cm,
                         "hoje": {"pedidos": u["rpd"], "tokens": u["tokens_dia"], "ok": u["ok"], "falhas": u["falhas"]},
                         "ultimo_minuto": len(u["min"]), "limites": lim,
                         "latencia_mediana_ms": _mediana(list(u["lat"])), "ultimo_erro": self.ultimo_erro.get(forn),
                         "modelos_vivos": len(self.modelos_vivos.get(forn) or []) if forn in self.modelos_vivos else None,
                         "sensivel_ok": spec.get("sensivel_ok", True), "nota": spec.get("nota")}
        return out

    def _carregar_estado(self):
        if not self.estado_path or not os.path.exists(self.estado_path):
            return
        try:
            d = json.load(open(self.estado_path, encoding="utf-8"))
            self.castigos = {k: tuple(v) for k, v in (d.get("castigos") or {}).items() if v[0] > time.time()}
            self.pausados = set(d.get("pausados") or [])
            self.retirados = dict(d.get("retirados") or {})
            self.rr_perfil = {k: int(v) for k, v in (d.get("rr_perfil") or {}).items()}
            for chave in self.retirados:                      # um modelo retirado nunca volta sozinho a lista
                f, m = chave.split(":", 1)
                for pp, ordem in self.ordem.items():
                    self.ordem[pp] = [x for x in ordem if not (x[0] == f and x[1] == m)]
            for forn, u in (d.get("uso") or {}).items():
                if u.get("dia") == _hoje():
                    x = self._uso(forn)
                    x.update(rpd=u.get("rpd", 0), tokens_dia=u.get("tokens_dia", 0), ok=u.get("ok", 0),
                             falhas=u.get("falhas", 0), custo_dia=float(u.get("custo_dia", 0.0)))
            for p, o in (d.get("ordem") or {}).items():
                if p in self.ordem and o:
                    self.ordem[p] = [tuple(x) for x in o]
            self.autoteste_ultimo = d.get("autoteste_ultimo")
        except Exception:
            pass

    def guardar_estado(self):
        if not self.estado_path:
            return
        d = {"castigos": {k: list(v) for k, v in self.castigos.items() if v[0] > time.time()}, "pausados": sorted(self.pausados),
             "uso": {f: {"dia": u["dia"], "rpd": u["rpd"], "tokens_dia": u["tokens_dia"], "ok": u["ok"], "falhas": u["falhas"],
                         "custo_dia": round(u.get("custo_dia", 0.0), 6)} for f, u in self.uso.items()},
             "retirados": self.retirados, "rr_perfil": self.rr_perfil,
             "ordem": {p: [list(x) for x in o] for p, o in self.ordem.items()}, "autoteste_ultimo": self.autoteste_ultimo,
             "guardado": datetime.datetime.now().isoformat(timespec="seconds")}
        tmp = self.estado_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(d, fh, ensure_ascii=False, indent=1)
        os.replace(tmp, self.estado_path)

    def sincronizar_supabase(self):
        """motor_estado: uma linha por fornecedor (o painel admin le e escreve `pausado`); motor_chamadas: o log."""
        if not self.supa:
            return
        est = self.estado()
        try:
            linhas = [{"fornecedor": f, "dados": dict(e, maquina=self.maquina), "pausado": f in self.pausados} for f, e in est.items()]
            self.supa.upsert_muitos("motor_estado", linhas, "fornecedor")
        except Exception as e:  # noqa: BLE001
            self.registar({"evento": "sync-estado-erro", "erro": str(e)[:160]})
        try:
            rows = self.supa.select("motor_estado", select="fornecedor,pausado", limit="100")
            novos = {r["fornecedor"] for r in rows if r.get("pausado")}
            if novos != self.pausados:
                self.registar({"evento": "pausados-do-painel", "pausados": sorted(novos)})
            self.pausados = novos
        except Exception as e:  # noqa: BLE001
            self.registar({"evento": "sync-pausados-erro", "erro": str(e)[:160]})
        with self.lock:
            lote, self.chamadas = list(self.chamadas), []
        if lote:
            try:
                self.supa.insert("motor_chamadas", lote, devolve=False)
            except Exception as e:  # noqa: BLE001
                self.registar({"evento": "sync-chamadas-erro", "erro": str(e)[:160], "n": len(lote)})

    # ------------------------------------------------------------ auto-teste nocturno
    def autoteste(self, sistema=None, perfis=("chat-rapido", "raciocinio")):
        """3 perguntas reais a cada candidato disponivel; reordena o perfil por (qualidade desc, latencia asc)."""
        sistema = sistema or ("Es o atendimento do Bora, uma app de entregas na Guarda, Portugal. Responde em portugues de Portugal, "
                              "1 a 3 frases, sem listas, sem inventar precos nem horarios; se nao sabes, diz que o Danilo responde.")
        relatorio = {}
        for perfil in perfis:
            resultados = []
            for forn, modelo in self.ordem.get(perfil, []):
                if not self.chaves(forn) or forn in self.pausados:
                    resultados.append((forn, modelo, None, None, "sem chave" if not self.chaves(forn) else "pausado"))
                    continue
                if self.castigado(forn, modelo):
                    resultados.append((forn, modelo, None, None, "castigado"))
                    continue
                lat, pontos, erro = [], 0, None
                for q in C.PERGUNTAS_TESTE:
                    r = self.chamar(forn + ":" + modelo, [{"role": "system", "content": sistema}, {"role": "user", "content": q}], max_tokens=220, timeout=40, origem="autoteste")
                    if r.get("error"):
                        erro = str(r["error"].get("message"))[:120]
                        break
                    lat.append(r["motor"]["latencia_ms"])
                    pontos += self._pontuar(q, r["choices"][0]["message"].get("content") or "")
                resultados.append((forn, modelo, (sum(lat) // len(lat)) if lat else None, pontos if lat else None, erro))
            vivos = [r for r in resultados if r[3] is not None]
            mortos = [r for r in resultados if r[3] is None]
            vivos.sort(key=lambda r: (-r[3], r[2]))
            self.ordem[perfil] = [(r[0], r[1]) for r in vivos] + [(r[0], r[1]) for r in mortos]
            relatorio[perfil] = [{"fornecedor": r[0], "modelo": r[1], "latencia_ms": r[2], "pontos": r[3], "erro": r[4]} for r in vivos + mortos]
        self.autoteste_ultimo = datetime.datetime.now().isoformat(timespec="seconds")
        self.guardar_estado()
        self.registar({"evento": "autoteste", "quando": self.autoteste_ultimo, "perfis": {p: [(x["fornecedor"], x["modelo"], x["latencia_ms"], x["pontos"]) for x in v[:5]] for p, v in relatorio.items()}})
        return relatorio

    @staticmethod
    def _pontuar(pergunta, resposta):
        """0-3 por pergunta: portugues e tamanho (1), obedece as regras (1), acerta o facto pedido (1)."""
        r = (resposta or "").strip()
        rl = r.lower()
        p = 0
        if 20 <= len(r) <= 600 and "<think" not in rl and not re.search(r"\b(the|you|your|hello)\b", rl):
            p += 1
        if not re.search(r"vou (ver|verificar|confirmar)|já lhe digo|um momento|\*\*|^- ", rl):
            p += 1
        q = pergunta.lower()
        if "funciona" in q and ("guarda" in rl or "bora" in rl or "app" in rl):
            p += 1
        elif "estafeta" in q and ("lista de espera" in rl or "vaga" in rl or "nome" in rl):
            p += 1
        elif "custa" in q and ("danilo" in rl or "não tenho" in rl or "nao tenho" in rl) and not re.search(r"\d+\s*(€|euros?)", rl):
            p += 1
        return p
