---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-20
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-20, corrida 7/dia — FALLBACK 30MIN)

## Gatilho
Invocação explícita do orquestrador citando "rede de segurança de 30 minutos" — item da fila
`nova` parado ≥162 min no momento do pedido. No momento real da triagem o item já estava parado
~213 min desde a criação da sugestão (e ~357 min/5h57m desde a criação do pedido-evidência).
Isto NÃO é uma falha nova do gatilho normal: é a 8ª reconfirmação do MESMO item de Balde B hoje
(reconfirmações 1–7 já registadas em `admin_audit_log` entre 08:13 e 11:33 UTC) — o gatilho normal
por item-novo funcionou na primeira vez (surfaced às 08:13:48 UTC); os disparos seguintes são o
FALLBACK 30MIN a repetir-se enquanto o item continuar em `nova` (comportamento já documentado,
não bug — ver `permanente/procedural/aprovador-vermelho-triagem.md`, anomalia de backoff pendente
de deploy na VPS).

## Fila (SELECT direto, `robot_suggestions` WHERE status='nova')
Total: **1 item**.

## Balde A (leitura/falso-positivo) — 0 itens
Nenhum item de Balde A na fila nesta corrida. Nada a promover.

## Balde B (dispatch/dinheiro real — precisa do Danilo) — 1 item
- **id** `8ccc09bb-e5b7-458e-89f9-f179df67f942`
  **categoria** `operacao_pedidos` · **dedup_key** `operacao_pedidos:pedido-preso-sem-atribuicao`
  **nível** 3 · **severidade** 5 · **criado** 2026-07-20 08:07:14 UTC
  **faz:** proposta pede investigar causa raiz de um pedido preso sem atribuição e "reatribuí-lo
  manualmente ou implementar um mecanismo de reatribuição automática com TTL".
  **evidência (fresca, reconfirmada nesta corrida via SELECT direto em `orders`):** order
  `7aa2e5f7-75d1-4ef4-b854-e69b2e6fa62b` — `status='created'`, `payment_status='pending'`,
  `assigned_driver_id=NULL`, criado 2026-07-20 05:43:39 UTC, agora **~357 min (5h57m) parado**.
  Idêntico às 7 reconfirmações anteriores — zero prova nova, zero mudança de estado.
  **risco:** qualquer mecanismo de reatribuição automática (mesmo que a proposta concreta seja só
  "investigar") toca `dispatch_engine` — zona protegida vermelha (ver
  `permanente/semantica/zonas-protegidas.md`). Família já conhecida: qualquer item
  `operacao_pedidos:*` que mexa em (re)atribuição de pedido cai em Balde B sempre.

  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (dispatch). Está tudo pronto — confirma que eu aplico.

  **Ação tomada:** NÃO promovido, NÃO reaberto, sem mudança de estado. Registada 8ª reconfirmação
  em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`, id
  `b9394b2d-cf80-4b53-893f-b5a13fede7ef`, `created_at=2026-07-20 11:41:42.065646 UTC`,
  `reconfirmacao_numero=8`).
  **Telegram:** SUPRIMIDO deliberadamente — último envio real foi há ~44 min (reconfirmação #2,
  10:57:51 UTC) e a evidência é idêntica às reconfirmações #3–7 (mesmo order, mesmo estado, zero
  prova nova). Gap ainda abaixo do checkpoint periódico (~59-60 min) usado noutros itens da mesma
  família quando não há prova nova (ver `infra:otimizar-queries-cron-lentas` em
  `aprovador-vermelho-historico-corridas.md`). Chave SSH `id_ed25519_vps` confirmada acessível
  nesta sessão (`test -f` → FOUND) — pronta a usar assim que o gap justificar reenvio ou surgir
  prova nova. Reenviar agora seria spam ao Danilo; o item continua visível na Central
  (`AdminRobotSuggestionsScreen`) e já foi entregue por Telegram 2x hoje (08:13 e 10:57 UTC).

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado) — confirmado por SELECT
direto nesta corrida. Sem efeito nesta corrida porque não há itens Balde A na fila.

## Achados
- A fila `robot_suggestions` tem **apenas 1 item** em `status='nova'` — não há itens presos
  adicionais além do já conhecido e documentado.
- O gatilho normal continua sem falhar de forma nova — mesmo item reconfirmado ciclicamente a
  cada ~6-8 min nas últimas horas (10:57, 11:06, 11:13, 11:19, 11:25, 11:33, agora 11:41). Confirma
  mais uma vez que o backoff exponencial (commitado no repo, ver
  `aprovador-vermelho-triagem.md`) segue **PENDENTE DE DEPLOY na VPS** — ruído operacional, não
  risco de dinheiro (Balde B nunca foi nem será promovido sozinho).
- Nenhuma zona protegida foi tocada nesta corrida (só leitura em `robot_suggestions`/`orders`/
  `platform_settings`/`admin_audit_log` + 1 INSERT em `admin_audit_log`, via de auditoria normal).
- Nenhum item ambíguo — o único item da fila já tem prova positiva clara (fresca) de que toca
  `dispatch_engine`; nada foi classificado por dúvida/falta de prova.

## Próximo passo sugerido (não executado — fora do mandato deste agente)
Deploy do fix de backoff já commitado no repo (`.claude/scripts/hermes-aprovador-vermelho.sh`)
para `/usr/local/bin/hermes-aprovador-vermelho.sh` na VPS, para parar o refire a cada poucos
minutos. Candidato a ordem para `maestro-autonomia` ou ato manual do Danilo.
