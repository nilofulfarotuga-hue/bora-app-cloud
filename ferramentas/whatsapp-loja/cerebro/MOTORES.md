# MOTORES — o roteador Motor Bora (pc), gerado 2026-09-02T23:39

Chaves vivem so nos `.env` (PC: `motor-bora/.env` + `whatsapp-loja/cerebro/.env`; VPS: `/opt/whatsapp-bora/.env` + `/opt/data/.env`).
Perfis: `chat-rapido` (WhatsApp ao vivo) · `raciocinio` (juiz, revisão, propostas) · `volume` (lotes) · `visao` · `audio`.

| fornecedor | chave | hoje (pedidos/ok/falhas) | tokens hoje | latência mediana | castigado | último erro | nota |
|---|---|---|---|---|---|---|---|
| groq | sim | 20/18/2 | 24533 | — | não |  | o mais rapido; 8 000 tokens/min por modelo no plano gratis |
| cerebras | **sem chave** | 0/0/0 | 0 | — | não |  | ~1 M tokens/dia, muito rapido |
| gemini | sim | 12/9/3 | 7289 | — | modelos: gemini-3-flash-preview |  | quota gratis por PROJETO e por modelo; esgota cedo |
| openrouter | **sem chave** | 0/0/0 | 0 | — | não |  | modelos :free (DeepSeek, Qwen, Llama); ~20/min |
| nvidia | **sem chave** | 0/0/0 | 0 | — | não |  | NIM: DeepSeek, Llama, Qwen, Mistral gratis com chave |
| sambanova | **sem chave** | 0/0/0 | 0 | — | não |  | 2.o nivel |
| cohere | **sem chave** | 0/0/0 | 0 | — | não |  | 2.o nivel (trial) |
| github | **sem chave** | 0/0/0 | 0 | — | não |  | GitHub Models: gpt-4o/4.1 com limite diario (conta GitHub do Danilo) |
| cloudflare | **sem chave** | 0/0/0 | 0 | — | não |  | Workers AI: 10 000 neuronios/dia |
| mistral | **sem chave** | 0/0/0 | 0 | — | não |  | Experiment: ~1 B tokens/mes MAS treina com os dados -> nunca conversas |
| zhipu | **sem chave** | 0/0/0 | 0 | — | não |  | GLM-4.x-flash gratis; reserva |
| ovh | sim | 4/0/4 | 0 | — | não |  | SEM CHAVE (anonimo): gpt-oss-120b, Llama 3.3 70B; limita depressa |
| llm7 | sim | 0/0/0 | 0 | — | não |  | chave opcional; pool publico -> nao para conversas de clientes |
| zen | sim | 5/4/1 | 5867 | — | não |  | OpenCode Zen free: nemotron; lento (40-90 s) |
| ollama | sim | 4/0/4 | 0 | — | não |  | local; ultimo recurso e transcricao offline |

## Ordem por perfil (o auto-teste das 05:30 reordena)
- **chat-rapido**: groq:qwen/qwen3.8-27b → groq:openai/gpt-oss-120b → gemini:gemini-3.1-flash-lite → zen:nemotron-3-ultra-free → cerebras:gpt-oss-120b → cerebras:llama-3.3-70b → gemini:gemini-3-flash-preview → sambanova:Meta-Llama-3.3-70B-Instruct → openrouter:deepseek/deepseek-chat-v3.1:free → openrouter:meta-llama/llama-3.3-70b-instruct:free → nvidia:meta/llama-3.3-70b-instruct → github:openai/gpt-4o-mini → cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast → zhipu:glm-4.5-flash → cohere:command-r-08-2024 → ovh:gpt-oss-120b → ovh:Meta-Llama-3_3-70B-Instruct → ollama:qwen2.5:7b-instruct
- **raciocinio**: groq:openai/gpt-oss-120b → gemini:gemini-3.1-flash-lite → gemini:gemini-3-flash-preview → cerebras:qwen-3-235b-a22b-instruct-2507 → openrouter:deepseek/deepseek-r1:free → openrouter:deepseek/deepseek-chat-v3.1:free → nvidia:deepseek-ai/deepseek-r1 → github:openai/gpt-4.1 → sambanova:DeepSeek-V3.1 → ovh:Qwen3.5-397B-A17B → ovh:gpt-oss-120b → zen:nemotron-3-ultra-free → mistral:mistral-small-latest → ollama:qwen2.5:7b-instruct
- **volume**: cerebras:gpt-oss-120b → cerebras:llama-3.3-70b → mistral:mistral-small-latest → nvidia:meta/llama-3.3-70b-instruct → openrouter:deepseek/deepseek-chat-v3.1:free → github:openai/gpt-4o-mini → cloudflare:@cf/meta/llama-3.3-70b-instruct-fp8-fast → ovh:gpt-oss-120b → groq:openai/gpt-oss-120b → gemini:gemini-3.1-flash-lite → zen:nemotron-3-ultra-free → ollama:qwen2.5:7b-instruct
- **visao**: gemini:gemini-3.1-flash-lite → gemini:gemini-3-flash-preview → openrouter:qwen/qwen2.5-vl-72b-instruct:free → nvidia:meta/llama-3.2-90b-vision-instruct → groq:meta-llama/llama-4-scout-17b-16e-instruct → ollama:llava:7b
- **audio**: groq:whisper-large-v3-turbo
