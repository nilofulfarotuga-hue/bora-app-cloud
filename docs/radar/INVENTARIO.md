# Inventário do que está instalado e a funcionar — COM PROVA

Regra (M10, 09/11/2026): o radar só escreve "já temos" se a coisa estiver nesta lista, com a prova e a
data. O que não está aqui é "registado" ou "por fazer". Cada linha diz onde vive e como se provou.
Quem mudar uma destas peças atualiza a linha (data nova + prova nova). Provas antigas de mais de 30 dias
valem como "por reprovar".

Última revisão: 09/11/2026 00:00–01:00, sessão "M10 radar e VPS" (e2e_log fluxo
`m10-noite-toda-sem-travas-2026-11-08`, passos 2B.x e 2.15–2.18).

## Agentes e motores

| Peça | Onde vive | Prova (data) |
|---|---|---|
| Hermes/Emerson 0.17.0 (não 0.23) | VPS, contentor `hermes-agent-fvnc-hermes-agent-1` | gateway "telegram connected (polling)" no gateway.log às 23:56:24 de 08/11, depois de reiniciar |
| Painel do Hermes só pela rede privada | Tailscale, porta 4860 (com senha; o endereço não se escreve no repo público) | 09/11: `/api/status` 200 e `/api/config` 401 pela Tailscale; pela internet 404 (Traefik exclui) |
| Motor Bora (rotação de motores grátis) | VPS, `motor-bora.service`, porta 8792 | 09/11: `/motores` com 10 fornecedores com modelos vivos (Gemini 61, NVIDIA 84, LLM7 68, Mistral 55, OVH 21, OpenRouter 12, Groq 11, Kilo 7, SambaNova 5, Cerebras 2); chamadas `gemini:*` com max_tokens 64000 responderam OK |
| Porteiro do Claude (crédito da API) | VPS, `porteiro.py` do motor | 09/11 23:45: `perfil:claude-dipsy` → claude-sonnet-5-5 em 1,7 s, linha em `ia_gastos` |
| Dipsy (DeepSeek Harness) no PC | `~/.dsh`, lançador `DIPSY.cmd` | 08/11 20:48: resposta de 11 017 tokens sem corte (ia_gastos na VPS e no Supabase) |
| Reserva grátis do Dipsy com 64 000 tokens | VPS, `motor_bora/catalogo.py` | 09/11: import diz `claude-dipsy 64000`, `claude-opus 64000` |
| OmniRoute 3.8.52 | VPS, contentor `omniroute` | 08/11: `docker ps` "healthy"; porta 20128 aberta pela Tailscale a partir do PC |
| Córtex (MCP) | VPS, contentor `cortex-mcp`, https://cortex.srv1786862.hstgr.cloud | 09/11: `tools/list` e 30 chamadas (propor/arquivar/pendentes) por cliente próprio |
| Porteiro do Telegram (porta única, 5 casos urgentes) | VPS, `porteiro.service` | 08/11: depois das 20:40 só 1 URGENTE (voz); antes havia de radar, redes, carteiro |
| Radar de vídeos diário | PC, tarefas `RadarCrescimentoBora` 18:00 e `...TelegramBora` 19:00 | última linha em `radar_videos` a 08/11 18:06 (1362 vídeos desde 24/09) |
| Radar de IA semanal + varredura mundial por país | VPS, `scripts/radar-ia.sh` (domingo 09:00) | ver o passo `2B.4-radar-ia-reparado` no e2e_log (prova de 09/11 em ensaio, sem envio) |
| Livro comum (`claude_ai_memoria`) e `e2e_log` | Supabase | escritas e leituras de 09/11 |

## Redes e conteúdo

| Peça | Onde vive | Prova (data) |
|---|---|---|
| Filtro único de lojas nas redes (sem coming_soon, sem Ouro e Prata) | VPS, `social/lojas_permitidas.py` + RPC `social_lojas_permitidas` | 09/11: 22 permitidas, 8 bloqueadas; texto com "Ouro e Prata" → código 3 |
| Corte automático de pausas para reels | skill `corte-automatico-reels` | 09/11: vídeo de 15,05 s com fala → 9,26 s, fala 7,12 → 7,13 s (intacta), 0 pausas ≥ 0,5 s |

## Segurança da VPS

| Peça | Prova (data) |
|---|---|
| Firewall (ufw + DOCKER-USER, IPv4 e IPv6) | 09/11 de fora (IPv4): só 22, 80, 443 abertas; 8090, 8099, 32772, 20128, 8792, 11434, 5432, 6379 fechadas. IPv6 por configuração (o PC não tem IPv6) |
| Disco | 09/11: 69% (15 GB livres) depois da limpeza de 1,35 GB |

## NÃO temos (registado, sem prova) — não escrever "já temos"

- Hermes 0.23 (WebApp, gateway único): adiado, ver tarefa `radar-tarefa-hermes-023`.
- CRM de WhatsApp aberto (DeskcommCRM): não instalado, ver `radar-tarefa-crm-whatsapp-pmes`.
- Token Economizer: testado e desfeito na VPS; não está no PC (`radar-tarefa-token-economizer`).
- Executor `claude -p` da VPS: SEM sessão iniciada (utilizador `hermes-exec`, sem credenciais desde julho).
- Auditoria REA do APK: só a app web foi auditada (`radar-tarefa-rea-apk`).
- Atendente de WhatsApp do Mister Navalha: o radar marca-o como feito, mas não foi reprovado nesta revisão.
- Claude Duet: sem acesso em Portugal (lista de espera nos EUA).
