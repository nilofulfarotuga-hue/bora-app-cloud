# PLANO DO FLUXO — Hermes → Claude Code (worker) → resultado

Definido pelo Danilo (28 Jun 2026). Objetivo: o Danilo fala, o sistema faz tudo
sozinho, e devolve o resultado. Sem ping-pong de perguntas.

## O fluxo
1. **Danilo → Hermes** (Telegram, voz ou texto): diz o que quer.
2. **Hermes → Claude Code**: envia a tarefa pela ponte SSH (sem flags). Hermes só
   classifica/encaminha; não tenta resolver código sozinho.
3. **Claude Code (worker, no PC, Opus 4.8)**: executa a tarefa **toda, sozinho**,
   toma todas as decisões **reversíveis** por conta própria, **sem perguntar**.
4. **Claude Code → Hermes**: devolve um RESULTADO claro e conciso em PT-BR.
5. **Hermes → Danilo**: reenvia o resultado (em voz, se foi por voz).

```
Danilo ──fala──▶ Hermes ──tarefa(SSH)──▶ Claude Code (Opus 4.8, autonomia total)
                                                  │
Danilo ◀──voz/texto── Hermes ◀──RESULTADO────────┘
```

## Regra de decisão (reversível vs irreversível)
- **REVERSÍVEL** (quase tudo: ler, analisar, editar código, criar ficheiros,
  testar, builds locais) → o worker **decide e faz sozinho**, sem perguntar.
- **IRREVERSÍVEL / Lista Vermelha** → o worker **NÃO faz**; devolve uma linha
  `CONFIRMAÇÃO NECESSÁRIA: <o quê>`. O Hermes mostra ao Danilo e espera "sim".
  Inclui: apagar dados/branches, force-push, Stripe/dinheiro/payouts, migrations
  destrutivas, RLS/auth, disparos em massa, builds de produção, ficheiros sensíveis
  (dispatch_engine, pricing, triggers financeiros), e commit/push sem pedido.

## Configuração que implementa isto
Ficheiro: `run-claude.cmd`
- **Autonomia total por defeito**: `--dangerously-skip-permissions` (faz tudo sem
  prompts). Para voltar ao modo seguro pontualmente: `set BORA_BRIDGE_SAFE=1 & ...`.
- **Modelo por defeito Opus 4.8**: `--model opus`. Override: `set BORA_MODEL=<id> & ...`.
- **GUARD** (system prompt injetado): codifica "modo padrão = AGIR; reversível →
  faz; irreversível/Lista Vermelha → CONFIRMAÇÃO NECESSÁRIA; PT-BR; nunca expõe
  credenciais; sem commit/push sem pedido".

Ficheiro: `hermes-soul-snippet.md` — ensina o Hermes a usar o fluxo (só enviar a
tarefa; relaiar só as linhas `CONFIRMAÇÃO NECESSÁRIA`).

## Trade-off de segurança (consciente)
Autonomia total por defeito significa que o worker pode correr qualquer comando
sem prompt. A única barreira passa a ser o GUARD (o modelo a cumprir a regra do
reversível/irreversível). É o que o Danilo pediu. Mitigações: GUARD forte, Opus
4.8 (capaz de cumprir a fronteira), sem commit/push automático, e `BORA_BRIDGE_SAFE=1`
disponível se algum dia quiser apertar.
