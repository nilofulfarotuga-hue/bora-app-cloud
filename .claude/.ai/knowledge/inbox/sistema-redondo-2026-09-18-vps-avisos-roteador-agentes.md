---
id: sistema-redondo-2026-09-18-vps-avisos-roteador-agentes
tema: infra-automacao
estado: candidato
origem: Claude Code
data: 2026-09-18
missao: sistema-redondo-2026-09-18
zona: verde
---

# O aviso do Instagram, o roteador e a empresa de agentes — o que era e o que ficou a valer

> Escrito directo no inbox (MCP do Córtex sem OAuth nesta sessão) para o `bibliotecario-cerebro`
> consolidar. Tudo medido na VPS `srv1786862`, 18/09 23:00–23:30 UTC.

## 1. O aviso "responder Instagram" que não parava (Bloco 2)

**Quem mandava:** `/opt/data/social/ig_auto_dm.py` (cron `*/10 * * * *` — de **10 em 10 min**, não
de hora a hora). Como a app da Meta está em modo de desenvolvimento (falta
`instagram_manage_messages`), cada corrida encontrava o mesmo comentário por responder, chamava
`avisar_telegram_por_responder` e mandava ao Telegram o mesmo texto ("Instagram: 1 pessoa(s) à
espera de resposta … O robô não pode enviar sozinho"). Medido no `log.md`: 6 por hora.

**O que ficou a valer:** o aviso ao Telegram fica **desligado enquanto faltar a permissão**
(`AVISAR_TELEGRAM_POR_RESPONDER=0`, por omissão). Quando a Meta aprovar, o robô envia sozinho e
não precisa de avisar. Se um dia se quiser o aviso de volta: `AVISAR_TELEGRAM_POR_RESPONDER=1` no
`.env` — e mesmo assim só sai **uma vez por dia** e só se houver comentário novo (assinatura dos
`cid`). A linha "AUTO-DM INERTE" no `log.md` também passou a uma por dia (eram 144).
Backup: `ig_auto_dm.py.bak-aviso-uma-vez-20260918`. Este caminho não chama modelo nenhum (só
`urllib`) — não gasta o plano Go. Prova: corridas do cron às 23:10 e 23:20 sem nenhuma linha
"mandadas ao Telegram" (a última foi às 23:00, antes do patch).

## 2. O roteador (Motor Bora, `/opt/motor-bora`, porta 8792) e o plano Go (Bloco 3)

**O que era verdade e o que não era:**
- O castigo **já tinha hora de fim** (`castigos[k] = (ate_epoch, motivo)`; `castigado()` limpa ao
  expirar). Às 23:06 a torre já tinha voltado a correr `ok` sozinha. O 503 das 18:05–22:07 foi uma
  janela em que os grátis estavam todos castigados/429 ao mesmo tempo.
- O "glm-5.2 respondeu pelo Conselho em 0,1 s" **não era o Go**: o `CONSELHO_BASE` aponta para o
  próprio Motor, e o Motor não conhecia `glm-5.2` → caía no perfil chat-rapido → **Groq
  qwen3.8-27b em 59 ms**. O Go nunca tinha respondido a nada.
- O Go **não é crédito de API**: `/zen/v1` com a chave Zen → `401 CreditsError "Insufficient
  balance"`; `/zen/go` sem cabeçalho → `MissingSessionID`. Funciona com
  `https://opencode.ai/zen/go/v1/chat/completions` + `OPENCODE_GO_KEY` + cabeçalho
  `x-opencode-session` (medido: glm-5.2 1,9 s · qwen3.8-max 2,6 s · minimax-m3 1,1 s).

**O que ficou a valer:** fornecedor `go` no catálogo do Motor (`pago: True`, cabeçalho fixo), os
três modelos no fim da cadeia `raciocinio` **antes do ollama local**; o auto-teste das 05:30 ordena
**grátis primeiro, pago depois** (senão o Go subia ao topo por ser rápido); chave em
`/opt/motor-bora/.env`. Prova nível a nível por alvo directo (`go:glm-5.2` etc. = sem fallback) e
o perfil inteiro a responder pelo grátis. Conselho → `glm-5.2` → agora vai mesmo ao `go` (1 950 ms
no log). Backups `catalogo.py.bak-go-*`, `roteador.py.bak-go-*`.

**Tokens e custo:** o Motor passou a gravar `custo_eur` por chamada em `motor_chamadas`
(estimativa da tabela `PRECO_POR_MILHAO`); a função `preencher_custos_corridas()` (pg_cron de 10
em 10 min) soma tokens e custo por corrida em `agentes_corridas` a partir da janela
`[quando − ms, quando]` do mesmo perfil. Migration
`20260918213000_motor_chamadas_custo_e_corridas_tokens.sql` no repo. Uma ronda da torre gasta
13–42 mil tokens (o prompt dela é pesado) — 0,006–0,02 € estimados nos grátis.

## 3. A empresa de agentes (Bloco 4)

Dos 25, só `torre` e `crescimento` tinham relógio. Ligados ao relógio (1×/dia, hora em UTC no
`ultima_chamada_do_relogio` para a 1.ª ronda cair à hora certa): **cobrador** (~09:05 Lisboa),
**qualidade** (~08:05), **gestor-parceiros** (~10:05), **seguranca** (segunda ~08:05). Ficam a
pedido (ligados, sem relógio): atendimento, recrutador, fiscal, escriba, designer, critico, redes,
gestor-em-dia. **Desligados com o porquê na nota:** agenda, arquiteto-sites, assinaturas, batedor,
burocracia, estudio, gestor-clientes, trader, vendedor, vendedor-servicos, lancamentos (corre no
PC; o relógio só o apanha com o PC ligado).

**Regra de fala:** o molde `pedido-ronda.txt` obriga a última linha a ser `ALERTA: <frase>` ou
`SEM NOVIDADE`; o Emerson (`emerson.py`, `_alerta_da_ronda` / `_alerta_repetido`) só manda ao
Telegram os `ALERTA:` e nunca o mesmo texto duas vezes em 24 h (`.alertas-enviados.json`). Ronda
sem novidade = silêncio (era já assim; agora há o meio-termo). Backups `emerson.py.bak-alerta-*`,
`pedido-ronda.txt.bak-alerta-*`.
