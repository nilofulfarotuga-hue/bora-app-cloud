# -*- coding: utf-8 -*-
"""ia_visao.py — olhos dos robôs do PC sem o Gemini do projeto Google "bora-juiz".

Missão fechar-tudo-2026-11-10, bloco H. O bora-juiz tem a conta de pagamento vencida (o juiz de
visão levou HTTP 402 a 09/11) e o Danilo não põe pagamento novo em nenhum projeto Google. Ordem
dele (31/10 e 01/11): os robôs usam PRIMEIRO a API do Claude e, se falhar ou acabar o crédito, a
rotação de motores grátis. A API do Claude é só para os robôs, nunca para o Claude Code.

Ordem deste módulo:
  1. Claude API direto — só se existir a variável CLAUDE_ROBOS_API_KEY (o nome que o porteiro da VPS
     já usa). NUNCA a ANTHROPIC_API_KEY: um Claude Code aberto no PC apanhava-a e passava a gastar a API.
     Modelo claude-haiku-5-5 (o mais barato que vê imagens: 0,10/0,50 USD por milhão de tokens),
     thinking desligado, esforço baixo.
  2. Claude pelo porteiro do Motor Bora (VPS, pela Tailscale), perfil "claude-so-volume": só Claude
     (Haiku), sem cauda grátis — sem crédito responde 503 logo. O porteiro regista em public.ia_gastos
     (robo = cabeçalho X-Motor-Origem).
  3. Rotação grátis de visão do Motor Bora pelo mesmo porteiro, perfil "visao" (Gemini grátis →
     OpenRouter :free → NVIDIA; lista medida a 08/09 em ferramentas/vps/motor-bora/catalogo.py).
  4. Erro claro: {"ok": False, "erro": "nenhum motor respondeu — <cada motor e o que disse>"}.

Porteiro: PORTEIRO_URL (por defeito http://100.120.181.115:8792, a Tailscale) e a senha num ficheiro
(PORTEIRO_SENHA_FICHEIRO, por defeito ~/.dsh/secrets/porteiro.token — o mesmo do Dipsy). A senha e
as chaves nunca se imprimem nem vão para o log. Só usar com imagens que não sejam dados privados de
clientes (o passo 3 é grátis e o fornecedor pode guardar o que recebe): as capturas do juiz são de
ecrãs de teste.
"""
from __future__ import annotations

import base64
import json
import os
import re
import time
import urllib.error
import urllib.request
from typing import Callable

URL_CLAUDE = "https://api.anthropic.com/v1/messages"
VERSAO_CLAUDE = "2023-06-01"
MODELO_CLAUDE = "claude-haiku-5-5"
NOME_VAR_CLAUDE = "CLAUDE_ROBOS_API_KEY"
PORTEIRO_URL_PADRAO = "http://100.120.181.115:8792"
FICHEIRO_SENHA_PADRAO = os.path.join(os.path.expanduser("~"), ".dsh", "secrets", "porteiro.token")
PERFIL_SO_CLAUDE = "claude-so-volume"
PERFIL_VISAO_GRATIS = "visao"
# USD por milhão de tokens (Haiku 5.5 até 100 mil tokens de entrada), lidos a 10/11/2026.
PRECO_ENTRADA, PRECO_SAIDA = 0.10, 0.50


def _senha_porteiro(env: dict) -> str:
    caminho = env.get("PORTEIRO_SENHA_FICHEIRO") or FICHEIRO_SENHA_PADRAO
    try:
        with open(caminho, "r", encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def motores_configurados(env: dict | None = None) -> list[str]:
    """Que passos podem correr nesta máquina (sem rede): ['claude-direto', 'porteiro']."""
    env = os.environ if env is None else env
    out = []
    if env.get(NOME_VAR_CLAUDE):
        out.append("claude-direto")
    if _senha_porteiro(env):
        out.append("porteiro")
    return out


def _b64(dados: bytes | str) -> str:
    return dados if isinstance(dados, str) else base64.b64encode(dados).decode("ascii")


def _post(urlopen: Callable, url: str, corpo: dict, cabecalhos: dict, timeout: int):
    """Devolve (http, json|None, texto_curto_de_erro|None). Nunca lança."""
    pedido = urllib.request.Request(url, data=json.dumps(corpo).encode("utf-8"),
                                    headers={"Content-Type": "application/json", **cabecalhos}, method="POST")
    try:
        with urlopen(pedido, timeout=timeout) as resp:
            bruto = resp.read().decode("utf-8", errors="replace")
            return resp.status, (json.loads(bruto) if bruto.strip() else {}), None
    except urllib.error.HTTPError as e:
        try:
            texto = e.read().decode("utf-8", errors="replace")
        except Exception:  # noqa: BLE001
            texto = ""
        curto = re.sub(r"\s+", " ", texto)[:200]
        return e.code, None, f"http {e.code}: {curto}"
    except Exception as e:  # noqa: BLE001 — timeout, rede, Tailscale em baixo
        return None, None, f"{type(e).__name__}: {str(e)[:160]}"


def _claude_direto(sistema, texto, imagens, max_tokens, urlopen, env):
    blocos = [{"type": "image", "source": {"type": "base64", "media_type": m, "data": _b64(d)}} for m, d in imagens]
    corpo = {
        "model": MODELO_CLAUDE,
        "max_tokens": max(1024, int(max_tokens)),
        "system": sistema,
        "messages": [{"role": "user", "content": blocos + [{"type": "text", "text": texto}]}],
        "thinking": {"type": "disabled"},
        "output_config": {"effort": "low"},
    }
    cab = {"x-api-key": env.get(NOME_VAR_CLAUDE, ""), "anthropic-version": VERSAO_CLAUDE}
    http, j, erro = _post(urlopen, URL_CLAUDE, corpo, cab, timeout=60)
    if erro:
        if http == 400 and "credit balance" in erro.lower():
            erro = erro.replace("http 400", "http 400 (sem credito)", 1)
        return None, http, erro, {}
    if (j or {}).get("stop_reason") == "refusal":
        return None, http, "recusa do modelo", {}
    resposta = "".join(b.get("text", "") for b in (j or {}).get("content", []) if b.get("type") == "text").strip()
    uso = (j or {}).get("usage") or {}
    return (resposta or None), http, (None if resposta else "resposta vazia"), uso


def _porteiro(perfil, sistema, texto, imagens, max_tokens, robo, urlopen, env):
    partes = [{"type": "text", "text": texto}] + [
        {"type": "image_url", "image_url": {"url": f"data:{m};base64,{_b64(d)}"}} for m, d in imagens]
    corpo = {"model": f"perfil:{perfil}", "max_tokens": max(1024, int(max_tokens)),
             "messages": [{"role": "system", "content": sistema}, {"role": "user", "content": partes}]}
    url = (env.get("PORTEIRO_URL") or PORTEIRO_URL_PADRAO).rstrip("/") + "/v1/chat/completions"
    cab = {"X-Porteiro-Token": _senha_porteiro(env), "X-Motor-Origem": robo}
    http, j, erro = _post(urlopen, url, corpo, cab, timeout=120)
    if erro:
        return None, http, erro, ""
    try:
        conteudo = j["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        conteudo = ""
    if isinstance(conteudo, list):
        conteudo = "".join(x.get("text", "") if isinstance(x, dict) else str(x) for x in conteudo)
    conteudo = (conteudo or "").strip()
    return (conteudo or None), http, (None if conteudo else "resposta vazia"), str((j or {}).get("model") or "")


def pedir(sistema: str, texto: str, imagens: list[tuple[str, bytes | str]], *, max_tokens: int = 1024,
          robo: str = "juiz-visao", urlopen: Callable = urllib.request.urlopen, env: dict | None = None,
          livro: Callable[[dict], None] | None = None) -> dict:
    """Claude primeiro → rotação grátis → erro claro. Nunca lança.

    imagens: [(mime, bytes ou base64)]. Devolve {"ok": True, "texto", "motor", "modelo", "tentativas"}
    ou {"ok": False, "erro", "tentativas"}. `livro` (opcional) recebe uma linha para public.ia_gastos
    quando o Claude é chamado direto (pelo porteiro, quem regista é o próprio porteiro)."""
    env = os.environ if env is None else env
    tentativas: list[dict] = []

    # 1. Claude direto (só com a chave própria dos robôs)
    if env.get(NOME_VAR_CLAUDE):
        t0 = time.time()
        resposta, http, erro, uso = _claude_direto(sistema, texto, imagens, max_tokens, urlopen, env)
        ms = int((time.time() - t0) * 1000)
        if livro:
            entrada, saida = int(uso.get("input_tokens") or 0), int(uso.get("output_tokens") or 0)
            try:
                livro({"maquina": "pc", "robo": robo, "perfil": robo, "prioridade": 3, "modelo": MODELO_CLAUDE,
                       "tokens_entrada": entrada, "tokens_saida": saida, "tokens_cache_escrita": 0, "tokens_cache_leitura": 0,
                       "custo_usd": round((entrada * PRECO_ENTRADA + saida * PRECO_SAIDA) / 1e6, 6),
                       "ms": ms, "ok": bool(resposta), "erro": erro})
            except Exception:  # noqa: BLE001 — o livro nunca derruba a resposta
                pass
        tentativas.append({"motor": "claude-direto", "modelo": MODELO_CLAUDE, "ok": bool(resposta), "http": http, "erro": erro, "ms": ms})
        if resposta:
            return {"ok": True, "texto": resposta, "motor": "claude-direto", "modelo": MODELO_CLAUDE, "tentativas": tentativas}
    else:
        tentativas.append({"motor": "claude-direto", "modelo": "", "ok": False, "http": None,
                           "erro": f"sem {NOME_VAR_CLAUDE} (normal no PC: vai pelo porteiro)", "ms": 0})

    # 2 e 3. Porteiro: primeiro só Claude, depois a rotação grátis de visão
    if not _senha_porteiro(env):
        tentativas.append({"motor": "porteiro", "modelo": "", "ok": False, "http": None,
                           "erro": "sem a senha do porteiro (PORTEIRO_SENHA_FICHEIRO)", "ms": 0})
    else:
        for perfil in (PERFIL_SO_CLAUDE, PERFIL_VISAO_GRATIS):
            t0 = time.time()
            resposta, http, erro, modelo = _porteiro(perfil, sistema, texto, imagens, max_tokens, robo, urlopen, env)
            ms = int((time.time() - t0) * 1000)
            motor = "porteiro-claude" if perfil == PERFIL_SO_CLAUDE else "porteiro-gratis"
            tentativas.append({"motor": motor, "modelo": modelo or f"perfil:{perfil}", "ok": bool(resposta),
                               "http": http, "erro": erro, "ms": ms})
            if resposta:
                return {"ok": True, "texto": resposta, "motor": motor, "modelo": modelo or f"perfil:{perfil}",
                        "tentativas": tentativas}
            if http is None and perfil == PERFIL_SO_CLAUDE:
                # porteiro inalcançável (Tailscale em baixo): o perfil grátis passa pelo mesmo sítio
                tentativas.append({"motor": "porteiro-gratis", "modelo": f"perfil:{PERFIL_VISAO_GRATIS}", "ok": False,
                                   "http": None, "erro": "saltado: o porteiro não responde", "ms": 0})
                break

    resumo = "; ".join(f"{t['motor']}: {t['erro'] or ('ok' if t['ok'] else 'falhou')}" for t in tentativas)
    return {"ok": False, "erro": f"nenhum motor respondeu — {resumo}"[:1200], "tentativas": tentativas}
