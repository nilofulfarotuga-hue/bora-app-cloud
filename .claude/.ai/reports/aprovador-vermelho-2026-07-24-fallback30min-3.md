---
tema: aprovador-vermelho-relatorio · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-24
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-24, corrida FALLBACK 30MIN #3 do dia)

## Contexto do gatilho
Gatilho `FALLBACK 30MIN`: item mais antigo em `status='nova'` parado ≥30 min (na prática ~3220 min,
53,7h). É a **3ª corrida FALLBACK 30MIN do mesmo lote no mesmo dia** (anteriores: 07:27:50 UTC e
07:39:28 UTC — ver `aprovador-vermelho-2026-07-24-fallback30min-1.md` e `-2.md`). Esta corrida:
~07:49 UTC. Gap face à anterior: ~10 min — mesmo padrão anómalo já documentado (ver secção "Causa
raiz" abaixo).

## Itens processados: 4 (total da fila `status='nova'`)

Todos os 4 pertencem à família `marcacoes:*` (reservas de restaurante com pré-pagamento €3 real,
tabela `reservations`), já classificada Balde B em corridas anteriores de 2026-07-24. Sem evidência
nova desde a última corrida — nenhum foi promovido.

### Balde A (leitura/falso-positivo) — 0 itens
Nenhum item qualifica. Nenhuma auto-aprovação feita nesta corrida (não por a flag estar desligada —
`platform_settings.aprovador_vermelho_auto_baldeA = true`, ligada — mas por não haver nenhum item
com prova positiva de "só leitura/sem cobrança" nesta fila).

### Balde B (dinheiro real — precisa do Danilo) — 4 itens

- **`1efa3e60-10de-423c-97fb-8a21148de370`** — "Libertar slots de marcações órfãs"
  (`marcacoes:liberar-slots-orfãos-ttl`) — faz: automatizar liberação de slot quando marcação fica
  órfã em `pending_payment` | risco: mexe em cancelamento de reserva com `prepayment_pi` real
  (Stripe), sem regra de refund definida.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`47a4a9e6-07c7-4846-864a-e400064c9b0a`** — "Ajustar TTL para marcações pendentes de pagamento"
  (`marcacoes:ttl-pending-payment`) — faz: reduzir `reservation_pending_payment_ttl_minutes` |
  risco: acelera expiração de reservas com pagamento Stripe em curso — pode cancelar pagamento
  legítimo em progresso.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`c068f901-e877-4df0-8b43-0ac1b1c04234`** — "Ajustar política de no-show para marcações"
  (`marcacoes:ajustar-politica-no-show`) — faz: propõe `deposit_required_threshold:0.5` (exigir
  depósito conforme taxa de no-show) | risco: cria nova exigência de cobrança de depósito —
  dinheiro real, regra de negócio (CLAUDE.md §5 "no-show e cancel <2h = Bora 100%").
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

- **`7cf1a393-82b5-40d6-8738-7d300e73f85a`** — "Resolver marcações pendentes órfãs"
  (`marcacoes:resolver-marcacoes-orfas`, `nivel=3` — o próprio maestro já classifica 🔴) — faz:
  mecanismo automático de cancelamento/reatribuição de reserva paga | risco: escreve/cancela
  reserva com pagamento real sem revisão humana caso a caso.
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram: NÃO reenviado nesta corrida (decisão deliberada)
Os mesmos 4 itens já foram avisados por Telegram/surfaced 2× nas últimas ~12 min (07:27:50 e
07:39:28 UTC, mesmo lote, zero informação nova). Reenviar uma 3ª vez em <10 min seria spam ao
Danilo sem valor novo — mesma lição já registada no Cérebro para o cron (`licao-spam-ordens-
autoreferencial.md`), aplicada aqui ao aviso Telegram. Registei reconfirmação em
`admin_audit_log` (4 linhas, `action=robot_suggestion_baldeB_reconfirmado`,
`details.telegram_enviado=false`, `reconfirmacao_numero=4`) para manter o rasto sem repetir o
aviso. Os itens continuam visíveis e pendentes no `AdminRobotSuggestionsScreen` para o Danilo
decidir quando quiser.

## Causa raiz do gatilho a refirar tão frequente (achado NOVO nesta corrida)
O Cérebro (`aprovador-vermelho-triagem.md`) registava que um **backoff exponencial** (30→60→120→
240→360 min) tinha sido **aplicado ao ficheiro canónico do repo**
`.claude/scripts/hermes-aprovador-vermelho.sh` em 2026-07-13, faltando só o deploy manual à VPS.
**Verificação nesta corrida (`git log --all -- .claude/scripts/hermes-aprovador-vermelho.sh` +
leitura do ficheiro atual) mostra que isso está desatualizado**: o ficheiro no repo, HOJE, ainda
usa `STALE_MIN=30` fixo tanto para o gatilho quanto para o cooldown (linhas 42, 72-79) — **não
existem** `MAX_BACKOFF_MIN` nem `STATE_FORCE_N`/`STATE_FORCE_COUNT` em lado nenhum do histórico de
commits deste ficheiro (5 commits ao todo, nenhum introduz backoff). Ou seja: o fix nunca chegou a
ser committado (ficou só na working tree de uma sessão anterior e foi perdido antes de commitar) —
não é "só falta deploy à VPS", é "falta re-implementar e commitar no repo primeiro". Isto explica
por que o gap entre disparos continua ~5-12 min em vez do padrão 30→60→120→240 esperado, mesmo
tanto tempo depois do fix supostamente aplicado.
**Fora do meu mandato** (só roteamento de aprovação, não infra/cron) — não editei o script. Deixo
como candidato de tarefa para o `maestro-autonomia` ou o Danilo decidir se quer reimplementar o
backoff no repo e desta vez confirmar o commit antes de dar como resolvido.

## Resumo
- Total processado: 4 (100% da fila `nova`)
- Balde A: 0 (nenhuma auto-aprovação)
- Balde B: 4 (aguardam Danilo via Central/Telegram — já avisado 2x hoje, não reavisado agora)
- Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA = true`) — irrelevante
  esta corrida (0 itens elegíveis)
- Causa raiz do refire frequente: fix de backoff exponencial nunca foi commitado no repo (achado
  novo — corrige nota anterior do Cérebro que dizia "só falta deploy")
