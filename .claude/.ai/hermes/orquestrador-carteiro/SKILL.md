---
name: orquestrador-carteiro
description: >
  Carteiro do loop de orquestração. Acionado pela CAMPAINHA (webhook do cortex-mcp) quando há
  ordem nova em orquestracao/. Pega a ordem, aplica os tetos T1-T5, executa Claude Code no PC
  (via o stub 'claude' que redireciona), escreve a saída na fila e marca 'respondida'.
  STAGED: fonte no repo; deploy ao Hermes é um passo humano.
zona: amarela
tetos: [T1_5_tentativas, T2_budget, T3_zona_vermelha_fora, T4_allowedTools_restrito, T5_kill_switch]
status: staged
---

# orquestrador-carteiro (o "carteiro" do loop)

> **Contrato:** este skill NÃO decide qualidade (isso é o Claude-juiz). Ele só **executa** a ordem
> com os tetos e devolve a saída. Todo o juízo de aprovado/corrigir é do juiz.

## Gatilho
Webhook do `cortex-mcp` quando um `cortex_escrever` cria/atualiza uma ordem `estado: aberta` em
`orquestracao/`. Debounce: uma campainha por lote. Fallback: cron lento (1x/hora) varre `aberta`
sem resposta. **NÃO fazer polling** (desperdiça o modelo grátis).

## Passos (ao ser acionado)
1. **T5 — kill switch.** `cortex_ler orquestracao/controlo` → se `orquestracao_enabled: false` → **não faz nada**, sai.
2. Lê ordens `estado: aberta` (via `cortex_listar` filtro `orquestracao`).
3. Para cada ordem:
   a. **T3 — zona.** Se a tarefa toca **dispatch_engine · pricing_service · finalizePurchase ·
      bora_tokens · Stripe webhook · RLS de orders/wallets/ledger** → marcar `estado: zona_vermelha`,
      escrever na fila de aprovação do admin, **NÃO executar**. (Além disto, a Trava `protege-banco.sh`
      no PC bloqueia à força qualquer edição financeira — prioridade absoluta.)
   b. Ler `tentativa` atual. **T1 — se já houve 5 tentativas** sem aprovação → `estado: travada` +
      **Telegram ao Danilo** + PARA (nunca 6.ª, nunca loop infinito).
   c. **T4/T2 — executar** no workdir do bora_app (o `claude` no VPS redireciona para o PC):
      ```
      claude -p "<tarefa>" \
        --allowedTools '<restrito ao que a tarefa precisa>' \
        --permission-mode acceptEdits \
        --max-turns <N> \
        --max-budget-usd <X>        # teto de custo por ordem — flag confirmada
      ```
      Se estourar budget/turns → `estado: travada` + Telegram. (T2 protege o VPS 4GB e a carteira.)
   d. Escrever a `saida` na ordem (resumo + ficheiros/commits tocados), incrementar `tentativa`,
      marcar `estado: respondida` (via `cortex_escrever`). Registar no `log.md` (lado: vps, autor: hermes).
4. A marcação `respondida` toca a campainha do **Claude-juiz** (Scheduled Task/cron), que avalia.
   `aprovada` → fim + Telegram "terminei, aprovado". `corrigir` → ordem volta a `aberta` (+nota) → nova volta.

## Formato da ordem (na fila `orquestracao/`)
```
--- ordem: <id> | estado: <aberta|executando|respondida|aprovada|corrigir|zona_vermelha|travada> ---
autor: claude.ai | criada: <ts>
tarefa: <o comando exato para o Claude Code>
zona: <verde|vermelha>
teto_tentativas: 5           # FIXO — regra do sistema, não configurável por ordem
--- resposta (Hermes) ---
tentativa: <k> | ts: <ts>
saida: <resumo + ficheiros/commits>
--- veredito (Claude-juiz) ---
estado: <aprovada|corrigir>
nota: <o que corrigir>
```

## Invariantes (não-negociáveis)
- **T1=5** sempre. **T3** zona vermelha nunca entra no loop; a Trava tem prioridade sobre tudo.
- **T5** respeita `orquestracao_enabled`. **T4** `--allowedTools` nunca "tudo".
- Só o Danilo é pingado quando: (a) terminou aprovado, ou (b) travou (5 tentativas / budget / zona vermelha).

## Deploy (passo humano — staged)
Copiar esta pasta para `/docker/hermes-agent-fvnc/data/skills/orquestrador-carteiro/` e confirmar
com `hermes` que a skill aparece. Só ligar depois do webhook + juiz prontos e de 1 dry-run verde.
