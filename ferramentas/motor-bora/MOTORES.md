# MOTORES — o roteador Motor Bora (pc), gerado 2026-09-04T07:37

Chaves vivem so nos `.env` (PC: `motor-bora/.env` + `whatsapp-loja/cerebro/.env`; VPS: `/opt/whatsapp-bora/.env` + `/opt/data/.env`).
Perfis: `chat-rapido` (WhatsApp ao vivo) · `raciocinio` (juiz, revisão, propostas) · `volume` (lotes) · `visao` · `audio`.

| fornecedor | chave | hoje (pedidos/ok/falhas) | tokens hoje | latência mediana | castigado | último erro | nota |
|---|---|---|---|---|---|---|---|
| groq | sim | 38/38/0 | 85745 | 699 ms | não |  | o mais rapido; 8 000 tokens/min por modelo no plano gratis |
| cerebras | **sem chave** | 0/0/0 | 0 | — | não |  | ~1 M tokens/dia, muito rapido |
| gemini | sim | 20/18/2 | 8363 | 3241 ms | modelos: gemini-3-flash-preview | HTTP 429 [{ "error": { "code": 429, "message": "You exceeded | quota gratis por PROJETO e por modelo; esgota cedo |
| openrouter | **sem chave** | 0/0/0 | 0 | — | não |  | modelos :free (DeepSeek, Qwen, Llama); ~20/min |
| nvidia | **sem chave** | 0/0/0 | 0 | — | não |  | NIM: DeepSeek, Llama, Qwen, Mistral gratis com chave |
| sambanova | **sem chave** | 0/0/0 | 0 | — | não |  | 2.o nivel |
| cohere | **sem chave** | 0/0/0 | 0 | — | não |  | 2.o nivel (trial) |
| github | sim | 0/0/0 | 0 | — | não |  | GitHub Models: gpt-4o/4.1 com limite diario (conta GitHub do Danilo) |
| cloudflare | **sem chave** | 0/0/0 | 0 | — | não |  | Workers AI: 10 000 neuronios/dia |
| mistral | sim | 2/1/1 | 53 | — | não |  | Experiment: ~1 B tokens/mes MAS treina com os dados -> nunca conversas |
| zhipu | **sem chave** | 0/0/0 | 0 | — | não |  | GLM-4.x-flash gratis; reserva |
| kilo | sim | 37/29/8 | 88545 | 4693 ms | modelos: stepfun/step-3.7-flash:free, liquid/lfm-2.5-2.6b:free | resposta vazia | Kilo Gateway: sem chave, sem conta; so modelos ':free'; ~200 pedidos/h |
| ollama-cloud | **sem chave** | 0/0/0 | 0 | — | não |  | Ollama Cloud (chave em OLLAMA_API_KEY): gpt-oss:120b e outros, sem ins |
| ovh | sim | 6/0/6 | 0 | — | não | HTTP 429 { "message":"API rate limit exceeded", "request_id" | SEM CHAVE (anonimo): 429 quase sempre (medido 03-04/09); so reserva |
| llm7 | sim | 0/0/0 | 0 | — | não |  | chave opcional; pool publico -> nao para conversas de clientes |
| zen | sim | 2/0/2 | 0 | — | não | HTTP 0 TimeoutError: The read operation timed out | OpenCode Zen free: nemotron; lento (40-90 s); aceita contextos grandes |
| ollama | sim | 3/0/3 | 0 | — | 2026-09-04T07:37:33 (HTTP 0 TimeoutError: timed out) | HTTP 0 TimeoutError: timed out | local; ultimo recurso e transcricao offline |

**Custo simulado de hoje: 0.0895 €** (não se paga nada — é o que isto custaria ao preço de tabela dos modelos pagos equivalentes; por fornecedor na coluna abaixo).

| fornecedor | custo simulado hoje (€) | pedidos na última hora |
|---|---|---|
| groq | 0.0472 | 22 |
| gemini | 0.0025 | 9 |
| mistral | 0.0000 | 0 |
| kilo | 0.0398 | 27 |
| ovh | 0.0000 | 5 |
| zen | 0.0000 | 2 |
| ollama | 0.0000 | 3 |

## Ordem por perfil (o auto-teste das 05:30 reordena; `rodizio` roda entre os melhores a cada pedido)
- **chat-rapido** (rodizio, topo 6): groq:openai/gpt-oss-120b → groq:qwen/qwen3.8-27b → cerebras:gpt-oss-120b → cerebras:llama-3.3-70b → gemini:gemini-3.1-flash-lite → gemini:gemini-3-flash-preview → kilo:stepfun/step-3.7-flash:free → kilo:dots-studio/dots-3-note-preview:free → sambanova:Meta-Llama-3.3-70B-Instruct → openrouter:deepseek/deepseek-chat-v3.1:free → openrouter:meta-llama/llama-3.3-70b-instruct:free → nvidia:meta/llama-3.3-70b-instruct → cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast → zhipu:glm-4.5-flash → cohere:command-r-08-2024 → kilo:liquid/lfm-2.5-2.6b:free → ollama-cloud:gpt-oss:120b → ovh:gpt-oss-120b → ovh:Meta-Llama-3_3-70B-Instruct → ollama:qwen2.5:7b-instruct → zen:nemotron-3-ultra-free
- **raciocinio** (cadeia): gemini:gemini-3-flash-preview → groq:openai/gpt-oss-120b → cerebras:qwen-3-235b-a22b-instruct-2507 → openrouter:deepseek/deepseek-r1:free → openrouter:deepseek/deepseek-chat-v3.1:free → nvidia:deepseek-ai/deepseek-r1 → github:openai/gpt-4.1 → sambanova:DeepSeek-V3.1 → ovh:Qwen3.5-397B-A17B → ovh:gpt-oss-120b → zen:nemotron-3-ultra-free → gemini:gemini-3.1-flash-lite → mistral:ministral-8b-latest → ollama-cloud:gpt-oss:120b → kilo:stepfun/step-3.7-flash:free → ollama:qwen2.5:7b-instruct
- **volume** (rodizio, topo 3): cerebras:gpt-oss-120b → cerebras:llama-3.3-70b → mistral:ministral-8b-latest → nvidia:meta/llama-3.3-70b-instruct → openrouter:deepseek/deepseek-chat-v3.1:free → github:openai/gpt-4o-mini → cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast → ovh:gpt-oss-120b → groq:openai/gpt-oss-120b → gemini:gemini-3.1-flash-lite → zen:nemotron-3-ultra-free → kilo:stepfun/step-3.7-flash:free → kilo:dots-studio/dots-3-note-preview:free → ollama-cloud:gpt-oss:120b → ollama:qwen2.5:7b-instruct
- **visao** (cadeia): gemini:gemini-3.1-flash-lite → gemini:gemini-3-flash-preview → openrouter:qwen/qwen2.5-vl-72b-instruct:free → nvidia:meta/llama-3.2-90b-vision-instruct → groq:meta-llama/llama-4-scout-17b-16e-instruct → ollama:llava:7b
- **audio** (cadeia): groq:whisper-large-v3-turbo
