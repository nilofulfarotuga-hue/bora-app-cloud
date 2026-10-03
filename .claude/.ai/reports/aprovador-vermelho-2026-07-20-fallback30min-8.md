---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-20
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-20, corrida — FALLBACK 30MIN, reconfirmação nº10)

## Gatilho
Invocação explícita do executor autónomo do loop noturno (headless, sem canal direto com o
Danilo neste momento) citando a "rede de segurança de 30 minutos" — item da fila `nova` reportado
como parado 202+ min (count=1, com aviso explícito para não confiar cegamente no count e
confirmar eu mesmo). Confirmado por SELECT direto: o item está parado **224 min** desde a criação
da sugestão (e **368 min / 6h08m** desde a criação do pedido-evidência). Isto NÃO é falha nova do
gatilho normal — é a **10ª reconfirmação** do MESMO item de Balde B hoje (reconfirmações 1–9 já
registadas em `admin_audit_log` entre 08:13 e 11:47:49 UTC, a última apenas ~4 min antes desta
corrida). Comportamento já documentado, não bug — ver
`permanente/procedural/aprovador-vermelho-triagem.md` (anomalia de backoff pendente de deploy
na VPS).

## Fila (SELECT direto, `robot_suggestions` WHERE status='nova')
Total: **1 item**. Nenhum item adicional além do já conhecido.

## Balde A (leitura/falso-positivo) — 0 itens
Nenhum item de Balde A na fila nesta corrida. Nada a promover/auto-aprovar.

## Balde B (dispatch/dinheiro real — precisa do Danilo) — 1 item
- **id** `8ccc09bb-e5b7-458e-89f9-f179df67f942`
  **categoria** `operacao_pedidos` · **dedup_key** `operacao_pedidos:pedido-preso-sem-atribuicao`
  **nível** 3 · **severidade** 5 · **criado** 2026-07-20 08:07:14 UTC
  **faz:** proposta pede investigar causa raiz de um pedido preso sem atribuição e
  "reatribuí-lo manualmente ou implementar um mecanismo de reatribuição automática com TTL".
  **evidência (fresca, reconfirmada nesta corrida via SELECT direto em `orders`, 11:51:58 UTC):**
  order `7aa2e5f7-75d1-4ef4-b854-e69b2e6fa62b` — `status='created'`, `payment_status='pending'`,
  `assigned_driver_id=NULL`, criado 2026-07-20 05:43:39 UTC, agora **~368 min (6h08m) parado**.
  Idêntico às 9 reconfirmações anteriores — zero prova nova, zero mudança de estado.
  **risco:** qualquer mecanismo de reatribuição automática (mesmo que a proposta concreta seja só
  "investigar") toca `dispatch_engine` — zona protegida vermelha (ver
  `permanente/semantica/zonas-protegidas.md`). Família já conhecida: qualquer item
  `operacao_pedidos:*` que mexa em (re)atribuição de pedido cai em Balde B sempre.

  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (dispatch). Está tudo pronto — confirma que eu aplico.

  **Ação tomada:** NÃO promovido, NÃO reaberto, sem mudança de estado. Registada 10ª reconfirmação
  em `admin_audit_log` (`action='robot_suggestion_baldeB_reconfirmado'`, id
  `cb52a3be-0437-4e0c-9d13-82071dac0d7f`, `created_at=2026-07-20 11:52:29.54627 UTC`,
  `reconfirmacao_numero=10`).
  **Telegram:** SUPRIMIDO deliberadamente — último envio real foi há ~54 min (reconfirmação #2,
  10:57:51 UTC) e a evidência é idêntica às reconfirmações #3–9 (mesmo order, mesmo estado, zero
  prova nova). Gap ainda abaixo do checkpoint periódico (~59-60 min) usado noutros itens da mesma
  família quando não há prova nova. **Se o Danilo estiver a ler isto e quiser decidir agora:** o
  item está visível na Central (`AdminRobotSuggestionsScreen`) e já foi entregue por Telegram 2x
  hoje (08:13 e 10:57 UTC) — não é preciso esperar por um 3º envio automático para agir.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado) — confirmado por SELECT
direto nesta corrida. Sem efeito nesta corrida porque não há itens Balde A na fila.

## Achados
- A fila `robot_suggestions` tem **apenas 1 item** em `status='nova'` — não há itens presos
  adicionais além do já conhecido e documentado.
- O gatilho normal continua sem falhar de forma nova — mesmo item reconfirmado ciclicamente a
  cada ~5-8 min nas últimas ~3h (última: 11:47:49 UTC, agora 11:52:29 UTC). Confirma mais uma vez
  que o backoff exponencial (commitado no repo, ver `aprovador-vermelho-triagem.md`) segue
  **PENDENTE DE DEPLOY na VPS** — ruído operacional, não risco de dinheiro (Balde B nunca foi nem
  será promovido sozinho).
- Nenhuma zona protegida foi tocada nesta corrida (só leitura em `robot_suggestions`/`orders`/
  `platform_settings`/`admin_audit_log` + 1 INSERT em `admin_audit_log`, via de auditoria normal).
- Nenhum item ambíguo — o único item da fila já tem prova positiva clara (fresca) de que toca
  `dispatch_engine`; nada foi classificado por dúvida/falta de prova, nada foi classificado como
  falso-positivo sem confirmação concreta (seguindo o alerta do orquestrador sobre não repetir o
  erro de diagnóstico de 2026-07-13/15/16).

## Próximo passo sugerido (não executado — fora do mandato deste agente)
Deploy do fix de backoff já commitado no repo (`.claude/scripts/hermes-aprovador-vermelho.sh`)
para `/usr/local/bin/hermes-aprovador-vermelho.sh` na VPS, para parar o refire a cada poucos
minutos. Candidato a ordem para `maestro-autonomia` ou ato manual do Danilo.

## HANDOFF
`bibliotecario-cerebro` — `escopo: agente:aprovador-vermelho`. Atualizar contador de
reconfirmações (agora 10) em `aprovador-vermelho-historico-corridas.md` na próxima consolidação;
nenhum facto novo além do já registado (mesmo item, mesma causa, mesma anomalia de backoff).
