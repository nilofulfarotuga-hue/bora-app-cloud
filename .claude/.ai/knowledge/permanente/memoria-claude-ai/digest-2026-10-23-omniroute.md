---
id: memoria-claude-ai-digest-2026-10-23-omniroute
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-23
zona: verde
confianca: alta
estado: atual
---

# Claude Code 23/10 — OmniRoute na VPS (agentes nunca param)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `digest-2026-10-23-omniroute`, origem `claude-code`, atualizada em 2026-10-23T06:17:29.324731+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: digest 2026 10 23 omniroute · memoria claude.ai · claude_ai_memoria

O que funciona agora: o OmniRoute (roteador de IA) corre na VPS no contentor omniroute, porta 20128 so em 127.0.0.1, na rede docker do Hermes (http://omniroute:20128/v1) e no Tailscale (http://100.120.181.115:20128/v1, via tailscale serve dentro do contentor do Hermes). Nunca exposto a internet. So fornecedores por chave de API: Gemini (2 chaves), NVIDIA, OpenRouter gratis, Groq, Cloudflare Workers AI e o Motor Bora antigo como ultimo nivel de reserva. Nada de contas Claude/ChatGPT/Gemini web, nada de revendedores, sem TLS stealth, sem compressao, sem cache.
Combos (descem sozinhos quando um nivel falha): agentes (Emerson, fiscal, batedor, escriba, critico, vendedor, OpenCode do PC), privado (torre: so OpenCode Go, Cloudflare e Groq, que nao treinam com os dados), rapido, volume, visao, e tres vozes do Conselho do juiz (voz-glm, voz-qwen, voz-minimax). Os nomes antigos perfil:raciocinio, glm-5.2, qwen3.7-max, minimax-m3 estao mapeados para os combos.
Como se usa: agentes do Hermes ja apontados (config.yaml + .env de cada perfil, chave OMNIROUTE_API_KEY). Os outros 18 perfis continuam no Motor Bora; mudam-se com /opt/omniroute/or_ligar_hermes.py (lista ALVOS). No PC, quando o limite do Claude Code acaba: SEM-LIMITE.cmd no Ambiente de Trabalho abre o OpenCode com omniroute/agentes. Painel: /admin/motores tem o cartao OmniRoute (tabela omniroute_estado, escrita de 10 em 10 min pela VPS).
O que falta: a chave do OpenCode Go EXPIROU (provado no proprio OpenCode do PC); o Go fica no topo dos combos e volta sozinho quando o Danilo criar chave nova em opencode.ai/console. Cerebras sem saldo (402), desligado. OpenCode Zen gratis nao entra (so e permitido dentro do OpenCode). Codigo e README: ferramentas/omniroute/ (commit 40c9c2ec). Robos do app (Edge Functions) NAO foram mexidos.
