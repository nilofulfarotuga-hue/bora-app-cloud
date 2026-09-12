---
tema: aprovador-vermelho-relatorio · data: 2026-07-27 · corrida: 5a (FALLBACK_30MIN) ~18:02 UTC
---

# 🚦 APROVADOR-VERMELHO — TRIAGEM DA FILA 🔴 (2026-07-27, 5ª corrida ~18:02 UTC)

## Achado principal: NÃO é a fila que está partida — é o gatilho que está a martelar

Este é o **5º disparo do mesmo lote de 29 itens em menos de 1h20**:
`16:57:45 → 17:22:09 (25min) → 17:40:33 (18min) → 17:51:43 (11min) → agora ~18:02 (≈10min)`.

A fila **não mudou** desde a corrida anterior — mesmos 29 IDs, mesma classificação. O backoff
exponencial que devia espaçar estes disparos (30→60→120→240→360min) continua **revertido** no
repo (commit `e4444a4` aplicado e depois desfeito em silêncio por `f169f96`; ver
`permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md`). Isto não é risco de
dinheiro (Balde B nunca é promovido sozinho), mas é execução de agente desperdiçada e
`admin_audit_log`/Telegram a encher de ruído repetido. **Recomendação:** aplicar o fix de backoff
(recuperável via `git show e4444a4 -- .claude/scripts/hermes-aprovador-vermelho.sh`) isolado num
commit próprio, sem depender de outro domínio.

## Contagem
- **Total na fila `status='nova'`:** 29
- **Balde A (recomendo aprovar/promover agora):** 0 — nenhum item novo, na sua evidência concreta,
  justifica leitura/falso-positivo. A staleness (item mais antigo: 8155 min) NÃO foi usada como
  motivo de promoção, conforme a regra.
- **Balde B (fica para o Danilo):** 29 — todos já triados em corridas anteriores hoje, sem
  novidade de conteúdo.
- **Não classificável com confiança:** 0.

## Balde B — por família (nenhuma promovida; todas exigem "vai" do Danilo)

**Família `marcacoes:*` (reservas com pré-pagamento Stripe real) — 21 itens:**
`1efa3e60`(liberar-slots-orfãos-ttl), `c068f901`(ajustar-politica-no-show), `7cf1a393`
(resolver-marcacoes-orfas, nível 3), `7b91d830`+`aca99667`+`bb244433`+`8b04e458`+`1eb83b51`+
`38072232`+`a90f7a0e`+`a65c6c52`+`1633f4d1`+`4e17a34e`+`55a734bd`+`b662d4d5`+`9e605549`+
`e1a6d24d`+`c8f799f4`+`42ec3820`+`251649a7` (17 variantes v1-v17 de "ajustar-no-show-rate-threshold"
— propõem `platform_settings` de reservas que não existem hoje), `b8627b62`+`11f97170`+`c3d1cd8b`
(3 variantes "resolver-marcacoes-pendentes-orfas"), `c1caf38d` (mesma família). Motivo: qualquer
escrita/automação sobre `reservations` (pré-pagamento €3 real) é dinheiro real — família
reconhecida desde 2026-07-24.

**Família `catalogo:*ocultar` (escrita direta `is_available=false` em massa) — 4 itens:**
`3a6d6cd0`+`048e7340` (produtos-sem-foto-ocultar v1/v2, 59 produtos), `222e0b2b`
(produtos-sem-categoria-ocultar, 1546 produtos), `b454e9bc` (dedup fundido revisão+ocultar, 1546
produtos). Distinto do padrão Balde A já confirmado ("marcar para revisão" = só flag, sem
escrita) — aqui a proposta esconde produtos do catálogo, impacto de negócio direto, sem
precedente de auto-aprovação. Balde B por cautela desde 2026-07-27.

**Item agrupado `infra:otimizar-queries-lentas-cron` (`13ec022c`) — 1 item:** cita 3 funções na
evidência (`_cron_check_orphan_orders`, `_cron_check_ghost_drivers` — isoladamente Balde A —
e `_appointment_cron_auto_no_show` — Balde B sempre, mexe em `deposit_status`). Regra confirmada
(4× em 2026-07-18): item agrupado que cite qualquer função Balde B cai inteiro em Balde B, sem
aprovação parcial.

## Ação tomada nesta corrida
- 1 linha em `admin_audit_log` (`robot_suggestion_baldeB_reconfirmado_lote`, lote consolidado dos
  29 IDs) — **não** repeti as 29 linhas individuais que as 4 corridas anteriores já escreveram na
  última hora, para não somar mais ruído ao mesmo achado.
- Telegram: **suprimido** — gap de ~10min desde o aviso anterior (17:51:43 UTC), muito abaixo do
  limiar anti-spam (~60min) já estabelecido pelas corridas anteriores do mesmo dia.

Auto-Balde-A: **ligado** (`platform_settings.aprovador_vermelho_auto_baldeA=true`) — sem efeito
nesta corrida por não haver nenhum item Balde A no lote.

## Ver também
- `.claude/.ai/reports/aprovador-vermelho-2026-07-27-fallback30min.md` (1ª corrida, achado do bug
  de dedupe do gerador)
- `.claude/.ai/reports/aprovador-vermelho-2026-07-27-fallback30min-29itens.md`,
  `aprovador-vermelho-2026-07-27-1707z.md`, `aprovador-vermelho-2026-07-27-1750z-4a-corrida.md`
  (corridas 2ª-4ª, mesmo lote)
- `.claude/.ai/knowledge/permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md`
