#!/usr/bin/env python3
"""Bloco 3 (omniroute-23-10): combos do melhor para o pior, estrategia "priority" (desce so quando falha).

So entram niveis provados um a um no dia 23/10 (logs/prova-nivel-*.jsonl). O OpenCode Go fica no topo
do `agentes` e do `privado` porque e o melhor e o Danilo paga-o — mas a chave EXPIROU (provado 23/10:
"This API key has expired"); enquanto nao houver chave nova o OmniRoute salta-o em ~0,2 s.
O ultimo nivel de cada combo e o Motor Bora antigo (reserva 7 dias, decisao da missao).
"""
import json
import subprocess

MOTOR = "motor/"

COMBOS = {
    "agentes": {
        "description": "Agentes com ferramentas (Hermes/Emerson, 5 bots, juiz). Melhor -> pior.",
        "models": [
            "opencode-go/glm-5.2",
            "opencode-go/qwen3.8-max",
            "gemini/gemini-3.6-flash",
            "nvidia/nvidia/nemotron-3-ultra-550b-a55b",
            "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free",
            "opencode-go/hy3",
            "cloudflare-ai/@cf/zai-org/glm-4.7-flash",
            "groq/openai/gpt-oss-120b",
            "gemini/gemini-3.7-flash",
            "groq/qwen/qwen3.8-27b",
            "gemini/gemini-3.1-flash-lite",
            MOTOR + "perfil:raciocinio",
        ],
    },
    "privado": {
        "description": "Para quem pode ver dados de clientes (torre). So fornecedores que nao treinam nem guardam: OpenCode Go, Groq, Cloudflare Workers AI.",
        "models": [
            "opencode-go/glm-5.2",
            "opencode-go/qwen3.8-max",
            # Os pedidos do Hermes tem ~11 mil tokens: o Groq gratis (8 mil/min) recusa-os com 413,
            # por isso o Cloudflare glm-4.7-flash (provado com pedido grande + ferramenta) vem antes.
            "cloudflare-ai/@cf/zai-org/glm-4.7-flash",
            "cloudflare-ai/@cf/google/gemma-4-26b-a4b-it",
            "groq/openai/gpt-oss-120b",
            "groq/qwen/qwen3.8-27b",
            "cloudflare-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast",
        ],
    },
    "rapido": {
        "description": "Espelho do perfil chat-rapido do Motor Bora: groq primeiro (resposta < 3 s).",
        "models": [
            "groq/qwen/qwen3.8-27b",
            "cloudflare-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast",
            "gemini/gemini-3.1-flash-lite",
            "groq/openai/gpt-oss-120b",
            "gemini/gemini-3-flash-preview",
            MOTOR + "perfil:chat-rapido",
        ],
    },
    "volume": {
        "description": "Espelho do perfil volume do Motor Bora (lotes; latencia nao manda).",
        "models": [
            "cloudflare-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast",
            "groq/openai/gpt-oss-120b",
            "gemini/gemini-3.1-flash-lite",
            "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free",
            MOTOR + "perfil:volume",
        ],
    },
    "visao": {
        "description": "Espelho do perfil visao do Motor Bora (imagens).",
        "models": [
            "gemini/gemini-3.1-flash-lite",
            "gemini/gemini-3-flash-preview",
            "nvidia/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
            MOTOR + "perfil:visao",
        ],
    },
}

# O Conselho (a segunda opiniao do juiz) pede 3 vozes pelo nome dos modelos do plano Go. Cada voz
# tem o seu combo, com um 2.o nivel DIFERENTE, para as 3 opinioes nao virem todas do mesmo modelo
# enquanto o Go estiver em baixo.
COMBOS.update({
    "voz-glm": {"description": "Conselho: voz glm-5.2 (desce para nemotron/cloudflare).",
                "models": ["opencode-go/glm-5.2", "nvidia/nvidia/nemotron-3-ultra-550b-a55b",
                           "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free",
                           "cloudflare-ai/@cf/zai-org/glm-4.7-flash", MOTOR + "perfil:raciocinio"]},
    "voz-qwen": {"description": "Conselho: voz qwen (desce para gemini/groq).",
                 "models": ["opencode-go/qwen3.8-max", "gemini/gemini-3.6-flash", "groq/openai/gpt-oss-120b",
                            "gemini/gemini-3.1-flash-lite", MOTOR + "perfil:raciocinio"]},
    "voz-minimax": {"description": "Conselho: voz minimax (desce para cloudflare/gemini 3.7).",
                    "models": ["opencode-go/minimax-m3", "cloudflare-ai/@cf/zai-org/glm-4.7-flash",
                               "gemini/gemini-3.7-flash", "groq/qwen/qwen3.8-27b", MOTOR + "perfil:raciocinio"]},
})

MAPAS = {"perfil:raciocinio": "agentes", "perfil:chat-rapido": "rapido", "perfil:volume": "volume", "perfil:visao": "visao",
         "glm-5.2": "voz-glm", "glm-5.1": "voz-glm",
         "qwen3.8-max": "voz-qwen", "qwen3.7-max": "voz-qwen", "qwen3.7-plus": "voz-qwen", "qwen3.6-plus": "voz-qwen",
         "minimax-m3": "voz-minimax", "minimax-m2.7": "voz-minimax", "minimax-m2.5": "voz-minimax"}


def admin(metodo, caminho, corpo=None):
    args = ["python3", "/opt/omniroute/or_admin.py", metodo, caminho] + ([json.dumps(corpo)] if corpo is not None else [])
    r = subprocess.run(args, capture_output=True, text=True, env={"OR_RAW": "1", "PATH": "/usr/bin:/bin"})
    st, _, corpo_txt = r.stdout.partition("\n")
    try:
        return int(st), json.loads(corpo_txt or "{}")
    except Exception:
        return 0, {"_t": r.stdout[:300] + r.stderr[:300]}


def main():
    _, atuais = admin("GET", "/api/combos")
    por_nome = {c["name"]: c for c in atuais.get("combos", [])}
    ids = {}
    for nome, c in COMBOS.items():
        corpo = {"name": nome, "description": c["description"], "models": c["models"], "strategy": "priority"}
        if nome in por_nome:
            st, r = admin("PUT", f"/api/combos/{por_nome[nome]['id']}", corpo)
        else:
            st, r = admin("POST", "/api/combos", corpo)
        cid = (r.get("combo") or r).get("id")
        ids[nome] = cid
        print(f"combo {nome}: {st} id={cid} niveis={len(c['models'])}" + ("" if st in (200, 201) else f" erro={json.dumps(r)[:300]}"))
    _, mp = admin("GET", "/api/model-combo-mappings")
    ja = {m.get("pattern") for m in (mp.get("mappings") or mp.get("data") or [])} if isinstance(mp, dict) else set()
    for padrao, combo in MAPAS.items():
        if padrao in ja:
            print(f"mapa {padrao}: ja existia")
            continue
        st, r = admin("POST", "/api/model-combo-mappings", {"pattern": padrao, "comboId": ids[combo], "enabled": True,
                                                             "description": f"nome antigo do Motor Bora -> combo {combo}"})
        print(f"mapa {padrao} -> {combo}: {st}" + ("" if st in (200, 201) else f" erro={json.dumps(r)[:300]}"))
    print(json.dumps(ids))


if __name__ == "__main__":
    main()
