---
tema: aprovador-vermelho-corrida · escopo: agente:aprovador-vermelho · estado: atual · atualizado: 2026-07-27
---

# 🚦 APROVADOR-VERMELHO — TRIAGEM FALLBACK 30MIN (2026-07-27 ~17:50 UTC, 4ª corrida em ~1h)

## Gatilho
Item `nova` mais antigo (`1efa3e60-10de-423c-97fb-8a21148de370`, `marcacoes:liberar-slots-orfãos-ttl`)
parado há **8141+ minutos** (~5,65 dias, desde 2026-07-22 02:07 UTC). Disparo `FALLBACK 30MIN`
(caminho independente do watermark, ver CLAUDE.md do agente §"Rede de segurança de 30 minutos").

## Fila completa revista: 29 itens `status='nova'`
Todos os 29 revistos com prova positiva (evidência/proposta lida direto da linha, não "parece
seguro"). **0 Balde A · 29 Balde B.** `platform_settings.aprovador_vermelho_auto_baldeA = true`
(ligado) — mas não havia nenhum item Balde A na fila para auto-aprovar; nada a promover.

### Balde A (leitura/falso-positivo) — nenhum item nesta fila.

### Balde B (dinheiro real — precisa do Danilo) — 29 itens, agrupados por família já conhecida

**Família `marcacoes:ajustar-no-show-rate-threshold*` (18 itens: base + v2 a v17)** — propõem
`update_setting reservation_no_show_rate_threshold`, chave que **não existe** (distinta da real
`reservation_no_show_threshold_count=3`). Mexe em política de no-show de reserva com
pré-pagamento Stripe real (`prepayment_cents`/`prepayment_pi`). Balde B sempre.
IDs: `7b91d830`, `aca99667`(v2), `bb244433`(v3), `8b04e458`(v4), `1eb83b51`(v5), `38072232`(v6),
`a90f7a0e`(v7), `a65c6c52`(v8), `1633f4d1`(v9), `4e17a34e`(v10), `55a734bd`(v11), `b662d4d5`(v12),
`9e605549`(v13), `e1a6d24d`(v14), `c8f799f4`(v15), `42ec3820`(v16), `251649a7`(v17).

**Família `marcacoes:resolver-marcacoes(-pendentes)-orfas*` (5 itens)** — automatizam
cancelamento/liberação/reatribuição de reserva **paga** (Stripe `prepayment_pi`) sem regra de
refund definida. IDs: `7cf1a393` (base), `b8627b62`, `11f97170`(v2), `c3d1cd8b`(v3),
`c1caf38d` (`marcacoes:2efe0a26901c`).

**`marcacoes:liberar-slots-orfãos-ttl`** (`1efa3e60`, o item mais velho/gatilho) — TTL de
auto-liberação de slot de reserva paga via `update_setting`. Balde B.

**`marcacoes:ajustar-politica-no-show`** (`c068f901`) — inclui `deposit_required_threshold`
(exigir depósito) — dinheiro real (CLAUDE.md §5: no-show/cancel<2h = Bora 100%). Balde B.

**Família `catalogo:*ocultar*` (4 itens)** — `UPDATE is_available=false` em massa (escrita
direta), distinto do padrão Balde A já validado "marcar para revisão" (só flag). Impacto de
negócio (produtos deixam de poder ser comprados) sem precedente de auto-aprovação. Balde B por
cautela. IDs: `3a6d6cd0` (sem-foto-ocultar), `048e7340` (sem-foto-ocultar-v2), `222e0b2b`
(sem-categoria-ocultar), `b454e9bc` (sem-categoria-revisao-ocultar, dedup_key funde os 2
subpadrões antagônicos revisão/ocultar — classificado pela intenção final = ocultação).

**`infra:otimizar-queries-lentas-cron`** (`13ec022c`) — item agrupado: evidência cita
`_cron_check_orphan_orders()` (Balde A isolado) + `_cron_check_ghost_drivers()` (Balde A isolado)
+ `_appointment_cron_auto_no_show()` (Balde B sempre — escreve `deposit_status`). Regra já
confirmada: item inteiro cai em Balde B, sem aprovação parcial de uma linha da fila.

⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO (reservas com pré-pagamento Stripe real). Está tudo
mapeado — os 29 itens aguardam o Danilo na Central (`AdminRobotSuggestionsScreen`) ou "vai" no
Telegram. Nenhum foi promovido.**

## Telegram: suprimido nesta corrida (decisão consciente, não falha)
Gap desde o último aviso real: ~9 min (reconfirmado 17:40:33 UTC) / ~28 min (surfaced 17:22:09
UTC) / ~53 min (surfaced 16:57:45 UTC) — **4ª corrida no mesmo lote idêntico de 29 IDs em <1h**,
zero item novo. Abaixo do limiar anti-spam de ~60min já estabelecido pela corrida anterior
(17:40:33 UTC). Enviar mais uma ronda de 29 avisos individuais seria puro ruído repetido —
decisão de **não** reenviar Telegram desta vez, mas **registar a reconfirmação em
`admin_audit_log`** (29 linhas, ação `robot_suggestion_baldeB_reconfirmado`) para rasto e para o
próximo agente não re-derivar a análise.

## Causa-raiz do disparo repetido (já documentada, não nova)
`hermes-aprovador-vermelho.sh` dispara `FALLBACK 30MIN` sem backoff efetivo — o fix de backoff
exponencial (commit `e4444a4`) foi revertido em silêncio por `f169f96` (dano colateral de commit
de outro domínio) e nunca foi reaplicado no repo. Isto **não é** uma falha nova desta corrida:
é a mesma anomalia já registada em
`.claude/.ai/knowledge/permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md`.
Gap real observado entre corridas hoje (16:57→17:22→17:40→17:50, ~25/18/9 min) é **bem menor**
que o piso de 30min do próprio `STALE_MIN` não corrigido — sugere que o disparo desta ronda pode
ter vindo por um caminho diferente do cron de 30min fixo da VPS (ex.: gatilho manual/orquestrador
externo), não necessariamente o mesmo script. Não investigado a fundo nesta corrida (fora do
mandato de roteamento; candidato a ordem para `maestro-autonomia`/Danilo revisar o script).

## Nenhuma mudança na fila desde a corrida anterior (17:40:33 UTC)
Os mesmos 29 IDs, mesmos `dedup_key`, mesma evidência — confirmado por SELECT direto. Não há
sinal de que o gerador de sugestões (bug de dedupe já conhecido) tenha criado itens novos nos
últimos ~10 min.

## Ver também
- `permanente/procedural/aprovador-vermelho-triagem.md` (famílias Balde A/B já validadas)
- `permanente/procedural/aprovador-vermelho-anomalia-backoff-script.md` (anomalia do gatilho)
- `.claude/.ai/reports/aprovador-vermelho-2026-07-27-fallback30min.md`,
  `aprovador-vermelho-2026-07-27-1707z.md`, `aprovador-vermelho-2026-07-27-fallback30min-29itens.md`
  (corridas anteriores do mesmo dia)
