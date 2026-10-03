# -*- coding: utf-8 -*-
"""Jev (TypeSafe "System One") a partir do Motor Bora — PREPARADO, desligado por defeito.

Missao fecho-manha-2026-09-24, bloco 3. O Jev nao e um modelo de conversa: responde a
perguntas TIPADAS (choice / score / noul) com probabilidades calibradas — o mesmo contrato
que a Edge Function `decidir` ja usa (supabase/functions/decidir/index.ts, viaJev).

Regras desta peca:
  * Feature flag MOTOR_JEV_ATIVO (env). Ausente ou "0" -> nunca chama a rede, devolve None.
  * Chave: TYPESAFE_API_KEY no env; se faltar e houver um cliente Supabase com service role,
    pergunta ao Vault pela RPC decisor_chave_typesafe(). Sem chave -> None.
  * Nunca levanta excepcao para quem chama: qualquer falha devolve None e o roteador segue
    com a regra que ja tinha. So biblioteca padrao (corre na VPS de 1 core).
"""
import json
import time
import urllib.error
import urllib.request

JEV_URL = "https://api.typesafe.ai/v1/systemone"
JEV_MODEL = "jev-latest"
TIMEOUT_S = 8

_VERDADEIRO = ("1", "true", "sim", "yes", "on")


def ativo(env):
    """A flag tem de estar explicitamente ligada. Por defeito o Jev esta desligado."""
    return str((env or {}).get("MOTOR_JEV_ATIVO", "0")).strip().lower() in _VERDADEIRO


def chave(env, supa=None):
    """TYPESAFE_API_KEY do env; senao, o Vault via RPC decisor_chave_typesafe (so service role)."""
    k = str((env or {}).get("TYPESAFE_API_KEY", "")).strip()
    if k:
        return k
    if supa is None:
        return None
    try:
        r = supa.rpc("decisor_chave_typesafe", {}).execute()
        v = getattr(r, "data", r)
        if isinstance(v, dict):
            v = v.get("data")
        v = v.strip() if isinstance(v, str) else None
        return v or None
    except Exception:  # noqa: BLE001 — sem chave e sem barulho: o roteador segue
        return None


def _pergunta(tipo, instrucoes, opcoes=None, escala=None, criterios_noul=None):
    q = {"type": tipo, "instructions": instrucoes}
    if tipo == "choice":
        if isinstance(opcoes, (list, tuple)):
            q["criteria"] = {str(o): None for o in opcoes}
        else:
            q["criteria"] = dict(opcoes or {})
    elif tipo == "score":
        q["criteria"] = list(escala or [])
    elif tipo == "noul" and criterios_noul:
        q["criteria"] = dict(criterios_noul)
    return q


def _fechar(tipo, resposta_jev):
    """Da resposta bruta do Jev para (resposta, probabilidades, confianca). Igual ao index.ts."""
    a = resposta_jev or {}
    if tipo == "noul":
        sim = float(a.get("noul", 0) or 0)
        sim = min(1.0, max(0.0, sim))
        probs = {"sim": round(sim, 4), "nao": round(1 - sim, 4)}
        return ("sim" if sim >= 0.5 else "nao"), probs, round(1 - min(sim, 1 - sim) * 2, 4)
    probs = {str(k): float(v) for k, v in (a.get("probabilities") or {}).items()}
    soma = sum(v for v in probs.values() if v > 0)
    if soma <= 0:
        raise ValueError("probabilidades vazias")
    probs = {k: round(max(v, 0) / soma, 4) for k, v in probs.items()}
    if tipo == "choice":
        if isinstance(a.get("choice"), str):
            resposta = a["choice"]
        else:
            resposta = max(probs, key=probs.get)
    else:
        if isinstance(a.get("score"), (int, float)):
            resposta = str(round(float(a["score"]), 2))
        else:
            resposta = str(round(sum(int(k) * v for k, v in probs.items()), 2))
    conf = a.get("confidence")
    if not isinstance(conf, (int, float)):
        conf = max(probs.values()) if probs else 0.0
    return resposta, probs, round(float(conf), 4)


def decidir(env, tipo, pergunta, estado, opcoes=None, escala=None, criterios_noul=None,
            supa=None, http=None):
    """Devolve dict {resposta, probabilidades, confianca, motor:'jev', modelo, latencia_ms}
    ou None (flag desligada, sem chave, tipo invalido, ou o Jev falhou). Nunca levanta."""
    if tipo not in ("choice", "score", "noul"):
        return None
    if not ativo(env):
        return None
    k = chave(env, supa)
    if not k:
        return None
    corpo = {"state": estado, "model": JEV_MODEL,
             "questions": {"d": _pergunta(tipo, pergunta, opcoes, escala, criterios_noul)}}
    t0 = time.time()
    try:
        status, j = (http or _http)(k, corpo)
        if status != 200 or not isinstance(j, dict):
            return None
        a = (j.get("answers") or {}).get("d")
        if not a:
            return None
        resposta, probs, conf = _fechar(tipo, a)
    except Exception:  # noqa: BLE001
        return None
    uso = j.get("usage") or {}
    return {"resposta": resposta, "probabilidades": probs, "confianca": conf, "motor": "jev",
            "modelo": j.get("model") or JEV_MODEL, "latencia_ms": int((time.time() - t0) * 1000),
            "tokens_entrada": uso.get("input_tokens"), "tokens_saida": uso.get("output_tokens")}


def _http(k, corpo):
    dados = json.dumps(corpo, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(JEV_URL, data=dados, method="POST", headers={
        "Authorization": "Bearer " + k, "Content-Type": "application/json",
        "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        return e.code, {}
    except Exception:  # noqa: BLE001
        return 0, {}
