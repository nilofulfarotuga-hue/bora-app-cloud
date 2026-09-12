---
tema: aprovador-vermelho-relatorio · escopo: agente:aprovador-vermelho · estado: atual · data: 2026-07-19
---

# 🚦 APROVADOR-VERMELHO — TRIAGE DA FILA 🔴 (2026-07-19, gatilho FALLBACK 30MIN, 3ª corrida do dia)

**Gatilho recebido:** "item `nova` mais antigo parado ≥30 min (72+ min reportado, count=2)". Corri
`SELECT` direto sobre `robot_suggestions WHERE status='nova'` às 10:56:49 UTC — confirmado: **2
itens**, nenhum acumulado além dos já conhecidos (sem risco de teto 30).

## Fila completa (prova real, SELECT direto)

| id | criado (UTC) | idade agora | dedup_key | categoria |
|---|---|---|---|---|
| `77c31fff-0330-4981-813a-f2268c6f7bbe` | 09:07:13 | 109 min | `infra:otimizar-queries-cron-lentas` | infra_cron |
| `29ea4b41-1e28-420e-a7d3-2995c335d7e5` | 10:07:12 | 49 min | `infra:otimizar-queries-cron-lentas-v2` | infra_cron |

Ambos citam a mesma evidência (`evidencia.slow_queries_top3`): `_cron_check_orphan_orders`,
`_appointment_cron_auto_no_show`, `_cron_check_ghost_drivers`.

## Balde A (leitura/falso-positivo) — recomendo aprovar
**Nenhum item inteiro.** As funções `_cron_check_orphan_orders` e `_cron_check_ghost_drivers` são,
isoladamente, Balde A (confirmado por `pg_get_functiondef` em corridas anteriores — só `SELECT` +
`notify_admin_event`, zero escrita/dinheiro). Mas nenhuma das 2 linhas da fila as cita sozinhas.

## Balde B (dinheiro real — precisa de ti)
- **`77c31fff-0330-4981-813a-f2268c6f7bbe`** — faz: "otimizar queries lentas de cron" | risco:
  item **agrupado** — junta as 2 funções Balde A acima com `_appointment_cron_auto_no_show`
  (decide reter/devolver depósito de agendamento no-show = dinheiro real). Regra de item agrupado
  (confirmada 7+ vezes desde 2026-07-18): **não há aprovação parcial** — o item inteiro cai em
  Balde B. Esta é a **5ª reconfirmação** deste item (mesmo veredito desde 09:12 UTC).
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
- **`29ea4b41-1e28-420e-a7d3-2995c335d7e5`** — faz: mesma proposta, item "v2" (`dedup_key` distinto
  do primeiro — não é duplicado técnico, é uma 2ª geração do mesmo job periódico) | risco: mesmo
  padrão agrupado, mesma função `_appointment_cron_auto_no_show` citada. **3ª reconfirmação**
  (mesmo veredito desde 10:18 UTC).
  ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Telegram desta corrida
**Não reenviado.** A última reconfirmação real (10:38 UTC, `admin_audit_log`
`985b3a37`/`9bcdca61`) já avisou o Danilo há só 18 minutos, sem prova nova desde então — reenviar
agora seria spam sobre o mesmo veredito. Registei mesmo assim a reconfirmação em
`admin_audit_log` (`9b514bee-7bd5-4689-b580-792cbe1cb636` para `77c31fff`,
`621dadcf-8320-4c05-b816-cca7e28c185f` para `29ea4b41`, `created_at=2026-07-19 10:57:33 UTC`) para
manter o rasto, com `telegram_enviado:false` + motivo explícito.

## Auto-Balde-A
`platform_settings.aprovador_vermelho_auto_baldeA` = **true** (ligado) — mas irrelevante nesta
corrida: 0 itens Balde A isolados para aprovar.

## Observação fora do meu mandato (não corrigido, só reportado)
O job periódico que gera estes itens (categoria `infra_cron`) criou uma **2ª linha "v2"** para a
mesma evidência ~1h depois da 1ª (`dedup_key` sufixado `-v2` em vez de deduplicar contra
`infra:otimizar-queries-cron-lentas`). Isto sugere que o `dedup_key` upstream não está a colidir
como esperado para este gerador — é um assunto de quem escreve na fila (fora do meu mandato de
só roteamento), não mexi em nada. Sinalizo para o Bibliotecário/():quem desenhar o próximo gerador.

## Resumo
- Fila `nova` = **2 itens**, ambos já conhecidos (nenhum novo desde a última corrida).
- Balde A: **0** (nem promovidos nem prontos — nenhuma linha isolada cai em A).
- Balde B: **2**, ambos à espera do Danilo (nenhuma promoção automática, como sempre).
- Nada preso/inconclusivo — os 2 vereditos são reconfirmações consistentes (5ª e 3ª vez
  respetivamente) do mesmo padrão já documentado em
  `permanente/procedural/aprovador-vermelho-triagem.md`.
