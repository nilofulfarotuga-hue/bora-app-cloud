# -*- coding: utf-8 -*-
"""catalogo.py — os fornecedores gratis e os perfis. Chaves NUNCA aqui: so o NOME da variavel de ambiente.

`sensivel_ok`: pode ver conversas de clientes. Mistral "Experiment" treina com os dados -> False (so
tarefas nao sensiveis: perfis raciocinio/volume). `limites`: tectos do plano gratis (por minuto/dia/
tokens por minuto) contados LOCALMENTE para trocar ANTES do 429. `ua_browser`: o Cloudflare do
fornecedor devolve 403/1010 sem User-Agent de browser (Groq, OpenCode Zen).
Modelos: sao candidatos; a descoberta viva (/models) valida-os e um 404 castiga o modelo 24 h.
"""
import os

UA_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36"

FORNECEDORES = {
    "groq":       {"url": "https://api.groq.com/openai/v1", "chave": "GROQ_API_KEY", "modelos": "/models", "ua_browser": True,
                   "limites": {"rpm": 30, "rpd": 1000, "tpm": 8000}, "sensivel_ok": True, "nota": "o mais rapido; 8 000 tokens/min por modelo no plano gratis"},
    "cerebras":   {"url": "https://api.cerebras.ai/v1", "chave": "CEREBRAS_API_KEY", "modelos": "/models",
                   "limites": {"rpm": 30, "rpd": 14400, "tpm": 60000}, "sensivel_ok": True, "nota": "~1 M tokens/dia, muito rapido"},
    "gemini":     {"url": "https://generativelanguage.googleapis.com/v1beta/openai", "chave": "GEMINI_API_KEY", "modelos": "/models",
                   "limites": {"rpm": 10, "rpd": 20}, "sensivel_ok": True, "nota": "quota gratis por PROJETO e por modelo; esgota cedo"},
    "openrouter": {"url": "https://openrouter.ai/api/v1", "chave": "OPENROUTER_API_KEY", "modelos": "/models", "so_free": True,
                   "limites": {"rpm": 20, "rpd": 200}, "sensivel_ok": True, "nota": "modelos :free (DeepSeek, Qwen, Llama); ~20/min"},
    "nvidia":     {"url": "https://integrate.api.nvidia.com/v1", "chave": "NVIDIA_API_KEY", "modelos": "/models",
                   "limites": {"rpm": 40}, "sensivel_ok": True, "nota": "NIM: DeepSeek, Llama, Qwen, Mistral gratis com chave"},
    "sambanova":  {"url": "https://api.sambanova.ai/v1", "chave": "SAMBANOVA_API_KEY", "modelos": "/models",
                   "limites": {"rpm": 30}, "sensivel_ok": True, "nota": "2.o nivel"},
    "cohere":     {"url": "https://api.cohere.ai/compatibility/v1", "chave": "COHERE_API_KEY", "modelos": None,
                   "limites": {"rpm": 20, "rpd": 1000}, "sensivel_ok": True, "nota": "2.o nivel (trial)"},
    "github":     {"url": "https://models.github.ai/inference", "chave": "GITHUB_TOKEN", "modelos": None,
                   "limites": {"rpm": 15, "rpd": 150}, "sensivel_ok": True, "nota": "GitHub Models: gpt-4o/4.1 com limite diario (conta GitHub do Danilo)"},
    "cloudflare": {"url": "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1", "chave": "CLOUDFLARE_API_TOKEN", "modelos": None,
                   "limites": {"rpd": 300}, "sensivel_ok": True, "nota": "Workers AI: 10 000 neuronios/dia"},
    "mistral":    {"url": "https://api.mistral.ai/v1", "chave": "MISTRAL_API_KEY", "modelos": "/models",
                   "limites": {"rpm": 60}, "sensivel_ok": False, "nota": "Experiment: ~1 B tokens/mes MAS treina com os dados -> nunca conversas de clientes"},
    "zhipu":      {"url": "https://api.z.ai/api/paas/v4", "chave": "ZHIPU_API_KEY", "modelos": None,
                   "limites": {"rpm": 30}, "sensivel_ok": True, "nota": "GLM-4.x-flash gratis; reserva"},
    # 04/09: SEM CHAVE NENHUMA e sem conta -- o unico que nao depende de cliques do Danilo. Provado neste
    # dia: /models responde 200 sem Authorization e os modelos ":free" respondem. Os pagos devolvem
    # PAID_MODEL_AUTH_REQUIRED, por isso `so_free` filtra a descoberta. Tecto: ~200 pedidos/hora por IP.
    "kilo":       {"url": "https://api.kilo.ai/api/gateway", "chave": None, "modelos": "/models", "so_free": True,
                   "limites": {"rpm": 12, "rph": 180}, "sensivel_ok": True, "timeout_min": 20,
                   "nota": "Kilo Gateway: sem chave, sem conta; so modelos ':free'; ~200 pedidos/hora por IP"},
    "ollama-cloud": {"url": "https://ollama.com/v1", "chave": "OLLAMA_API_KEY", "modelos": "/models",
                     "limites": {"rpm": 20}, "sensivel_ok": True, "timeout_min": 40,
                     "nota": "Ollama Cloud (chave em OLLAMA_API_KEY): gpt-oss:120b e outros, sem instalar nada"},
    "ovh":        {"url": "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1", "chave": None, "modelos": "/models",
                   "limites": {"rpm": 2, "rpd": 40}, "sensivel_ok": True, "timeout_min": 6, "nota": "SEM CHAVE (anonimo): 429 quase sempre (medido 03-04/09); so reserva"},
    "llm7":       {"url": "https://api.llm7.io/v1", "chave": "LLM7_API_KEY", "opcional": True, "modelos": "/models",
                   "limites": {"rpm": 8}, "sensivel_ok": False, "timeout_min": 6, "nota": "chave opcional; pool publico -> nao para conversas de clientes"},
    "zen":        {"url": "https://opencode.ai/zen/v1", "chave": "OPENCODE_ZEN_API_KEY", "modelos": None, "ua_browser": True,
                   "limites": {}, "sensivel_ok": True, "timeout_min": 90, "nota": "OpenCode Zen free: nemotron; lento (40-90 s); aceita contextos grandes"},
    "ollama":     {"url": (os.environ.get("OLLAMA_URL") or "http://127.0.0.1:11434").rstrip("/") + "/v1", "chave": None, "modelos": "/models",
                   "limites": {}, "sensivel_ok": True, "nota": "local; ultimo recurso e transcricao offline", "timeout_min": 60},
}

# CUSTO SIMULADO (EUR por 1 M de tokens, misto entrada+saida, preco de tabela do modelo equivalente pago).
# Nao se paga nada: serve para o Danilo ver quanto ISTO custaria se fosse a pagar. Fonte: preco publico
# do fornecedor a 04/09/2026; e uma ESTIMATIVA, nao uma fatura.
PRECO_POR_MILHAO = {
    "groq": 0.55, "cerebras": 0.60, "gemini": 0.30, "openrouter": 0.50, "nvidia": 0.45, "sambanova": 0.60,
    "cohere": 1.20, "github": 0.50, "cloudflare": 0.20, "mistral": 0.25, "zhipu": 0.10, "ovh": 0.40,
    "llm7": 0.40, "zen": 0.80, "kilo": 0.45, "ollama-cloud": 0.30, "ollama": 0.0,
}

# candidatos por perfil, POR ORDEM; o auto-teste nocturno reordena pela velocidade e qualidade do dia.
# `modo`: "cadeia" = tenta pela ordem (o melhor primeiro, desce quando falha) · "rodizio" = roda entre os
# `rodizio_topo` melhores a cada pedido, para uma rajada nao esgotar sempre o mesmo fornecedor (04/09:
# 5 mensagens em 30 s esgotaram os 8 000 tokens/min do Groq e a prova 4 ficou com 5 respostas acima de 5 s).
PERFIS = {
    "chat-rapido": {"timeout": 7, "orcamento": 12, "max_tokens": 300, "sensivel": True,
                    # 04/09 (2.a volta): o Kilo estava no fim da lista e o topo-4 nunca lá chegava — nunca serviu uma
                    # resposta real. Sobe para o topo e o rodizio passa a 6: o unico fornecedor que nao depende de
                    # cliques entra na rotacao a valer (~1 em cada 3 respostas), e nao so como ultimo recurso.
                    "modo": "rodizio", "rodizio_topo": 6, "candidatos": [
        ("groq", "openai/gpt-oss-120b"), ("groq", "qwen/qwen3.8-27b"), ("cerebras", "gpt-oss-120b"), ("cerebras", "llama-3.3-70b"),
        ("gemini", "gemini-3.1-flash-lite"), ("gemini", "gemini-3-flash-preview"),
        ("kilo", "stepfun/step-3.7-flash:free"), ("kilo", "dots-studio/dots-3-note-preview:free"),
        ("sambanova", "Meta-Llama-3.3-70B-Instruct"),
        ("openrouter", "deepseek/deepseek-chat-v3.1:free"), ("openrouter", "meta-llama/llama-3.3-70b-instruct:free"),
        ("nvidia", "meta/llama-3.3-70b-instruct"), ("cloudflare", "@cf/meta/llama-3.3-70b-instruct-fp8-fast"),
        ("zhipu", "glm-4.5-flash"), ("cohere", "command-r-08-2024"),
        ("kilo", "liquid/lfm-2.5-2.6b:free"), ("ollama-cloud", "gpt-oss:120b"),
        ("ovh", "gpt-oss-120b"), ("ovh", "Meta-Llama-3_3-70B-Instruct"),
        ("ollama", "qwen2.5:7b-instruct"), ("zen", "nemotron-3-ultra-free")]},
    "raciocinio": {"timeout": 45, "orcamento": 130, "max_tokens": 900, "sensivel": True, "modo": "cadeia", "candidatos": [
        ("gemini", "gemini-3-flash-preview"), ("groq", "openai/gpt-oss-120b"), ("cerebras", "qwen-3-235b-a22b-instruct-2507"),
        ("openrouter", "deepseek/deepseek-r1:free"), ("openrouter", "deepseek/deepseek-chat-v3.1:free"), ("nvidia", "deepseek-ai/deepseek-r1"),
        ("github", "openai/gpt-4.1"), ("sambanova", "DeepSeek-V3.1"), ("ovh", "Qwen3.5-397B-A17B"), ("ovh", "gpt-oss-120b"),
        ("zen", "nemotron-3-ultra-free"), ("gemini", "gemini-3.1-flash-lite"), ("mistral", "ministral-8b-latest"),
        ("ollama-cloud", "gpt-oss:120b"), ("kilo", "stepfun/step-3.7-flash:free"), ("ollama", "qwen2.5:7b-instruct")]},
    "volume": {"timeout": 60, "orcamento": 180, "max_tokens": 1200, "sensivel": False, "modo": "rodizio", "rodizio_topo": 3, "candidatos": [
        ("cerebras", "gpt-oss-120b"), ("cerebras", "llama-3.3-70b"), ("mistral", "ministral-8b-latest"), ("nvidia", "meta/llama-3.3-70b-instruct"),
        ("openrouter", "deepseek/deepseek-chat-v3.1:free"), ("github", "openai/gpt-4o-mini"), ("cloudflare", "@cf/meta/llama-3.3-70b-instruct-fp8-fast"),
        ("ovh", "gpt-oss-120b"), ("groq", "openai/gpt-oss-120b"), ("gemini", "gemini-3.1-flash-lite"), ("zen", "nemotron-3-ultra-free"),
        ("kilo", "stepfun/step-3.7-flash:free"), ("kilo", "dots-studio/dots-3-note-preview:free"),
        ("ollama-cloud", "gpt-oss:120b"), ("ollama", "qwen2.5:7b-instruct")]},
    "visao": {"timeout": 40, "orcamento": 90, "max_tokens": 400, "sensivel": True, "candidatos": [
        ("gemini", "gemini-3.1-flash-lite"), ("gemini", "gemini-3-flash-preview"), ("openrouter", "qwen/qwen2.5-vl-72b-instruct:free"),
        ("nvidia", "meta/llama-3.2-90b-vision-instruct"), ("groq", "meta-llama/llama-4-scout-17b-16e-instruct"), ("ollama", "llava:7b")]},
    "audio": {"timeout": 60, "orcamento": 90, "candidatos": [("groq", "whisper-large-v3-turbo")]},
}

# 3 perguntas reais do WhatsApp para o auto-teste nocturno (com o prompt real do cerebro, se estiver a mao)
PERGUNTAS_TESTE = ["Como funciona o Bora?", "Quero ser estafeta, têm vagas?", "Vocês entregam em Gonçalo? Quanto custa?"]
