---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-20
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-20, corrida 6/dia — FALLBACK 30MIN)

## Gatilho
`hermes-aprovador-vermelho.sh` disparou FALLBACK 30MIN citando 1 item parado ≥132 min no
momento do disparo. Entre o disparo e a execução real desta corrida houve latência de sessão —
no momento da triagem o item já estava parado ~204 min (5h49m desde a criação do pedido-evidência).
Isto NÃO é falha do gatilho normal: é a 7ª vez que este MESMO item de Balde B é reconfirmado hoje
(reconfirmações 1–6 já registadas em `admin_audit_log` entre 08:13 e 11:25 UTC) — o gatilho normal
por item-novo funcionou na primeira vez (surfaced às 08:13:48); os disparos seguintes são o
FALLBACK 30MIN a repetir-se enquanto o item continuar em `nova` (comportamento esperado, não bug).

## Fila (SELECT direto, `robot_suggestions` WHERE status='nova')
Total: **1 item**.

## Balde A (leitura/falso-positivo) — 0 itens
Nenhum item de Balde A na fila nesta corrida. Nada a promover.

## Balde B (dinheiro/dispatch real — precisa do Danilo) — 1 item
- **id** `8ccc09bb-e5b7-458e-89f9-f179df67f942`
  **categoria** `operacao_pedidos` · **dedup_key** `operacao_pedidos:pedido-preso-sem-atribuicao`
  **nível** 3 · **severidade** 5 · **criado** 2026-07-20 08:07:14 UTC
  **faz:** proposta pede investigar causa raiz de um pedido preso sem atribuição e "reatribuí-lo
  manualmente ou implementar um mecanismo de reatribuição automática com TTL".
  **evidência (fresca, reconfirmada nesta corrida):** order `7aa2e5f7-75d1-4ef4-b854-e69b2e6fa62b`
  — `status='created'`, `payment_status='pending'`, `assigned_driver_id=NULL`, criado
  2026-07-20 05:43:39 UTC, agora **~349 min (5h49m) parado**. Idêntico às 6 reconfirmações
  anteriores — zero prova nova.
  **risco:** qualquer mecanismo de reatribuição automática (mesmo que a proposta concreta seja só
  "investigar") toca `dispatch_engine` — zona protegida vermelha (ver
  `permanente/semantica/zonas-protegidas.md`). Família já conhecida: qualquer item
  `operacao_pedidos:*` que mexa em (re)atribuição de pedido cai em Balde B sempre.

  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (dispatch). Está tudo pronto — confirma que eu aplico.

  **Ação tomada:** NÃO promovido. Registada 7ª reconfirmação em `admin_audit_log`
  (`action='robot_suggestion_baldeB_reconfirmado'`, id `6f70c2a5-3d25-4f5d-a4c7-f8c563befb28`,
  `created_at=2026-07-20 11:33:32.861968 UTC`, `reconfirmacao_numero=7`).
  **Telegram:** SUPRIMIDO deliberadamente — último envio real foi há ~34 min (reconfirmação #2,
  10:57:51 UTC) e a evidência é idêntica às reconfirmações #3/4/5/6 (mesmo order, mesmo estado,
  zero prova nova). Reenviar seria spam ao Danilo. Se ele quiser decidir, o item continua visível
  na Central (`AdminRobotSuggestionsScreen`) e no Telegram já entregue anteriormente.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado) — confirmado por SELECT
direto nesta corrida. Sem efeito nesta corrida porque não há itens Balde A na fila.

## Achados
- A fila `robot_suggestions` tem **apenas 1 item** em `status='nova'` — não há itens presos
  adicionais além do já conhecido e documentado (ver
  `permanente/procedural/aprovador-vermelho-triagem.md`, secção "Novo tipo de Balde B confirmado,
  não-cron (2026-07-20)").
- O gatilho normal NÃO falhou de forma nova — este é o mesmo item que já estava sendo
  reconfirmado ciclicamente a cada ~6-8 min nas últimas horas (ver timestamps em
  `admin_audit_log`: 10:57, 11:06, 11:13, 11:19, 11:25, agora 11:33). Isso sugere que o backoff
  exponencial documentado como "aplicado no repo mas PENDENTE DE DEPLOY na VPS" (ver
  `aprovador-vermelho-triagem.md` linha ~88-121) ainda não está a correr em produção — o script
  continua a refire a cada ciclo do cron (~/10 min) em vez de espaçar 30→60→120→240 min. Isto é
  ruído operacional (execução de agente desperdiçada), NÃO risco de dinheiro — Balde B nunca foi
  nem será promovido sozinho.
- Nenhuma zona protegida foi tocada nesta corrida (só leitura + 1 INSERT em `admin_audit_log`,
  que é a via de auditoria normal, não lógica de dinheiro).

## Próximo passo sugerido (não executado — fora do mandato deste agente)
Deploy do fix de backoff já commitado no repo (`.claude/scripts/hermes-aprovador-vermelho.sh`)
para `/usr/local/bin/hermes-aprovador-vermelho.sh` na VPS, para parar o refire a cada poucos
minutos. Candidato a ordem para `maestro-autonomia` ou ato manual do Danilo.
