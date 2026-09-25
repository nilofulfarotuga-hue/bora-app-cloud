# CONTINUAR — contas-claras-20260920

> Escrito pelo Claude Code (Opus) a 20/09/2026 ~21h35, no fecho do B6. O Córtex MCP estava sem
> autorização OAuth nesta sessão (não houve `cortex_nova_ordem`); este ficheiro é a ordem de
> continuação. Estado exacto abaixo. A sessão seguinte arranca daqui sem perguntar nada.

## Estado (provado)

- Commits locais no ramo `autonomous-night-2026-04-29`: `d7eb1426` (missão inteira) e `5b368b71`
  (mapa +1.15). **Sem push.** `git status` tem 132 ficheiros de outras sessões por fora — não são desta missão.
- Em produção (aplicado por MCP, confirmado): migrations `contas_claras_b1_saldo_igual_historico`,
  `contas_claras_b1_talao_dois_caminhos`, `contas_claras_refund_split_idempotente_2026_09_20` (Claude.ai),
  `contas_claras_b2_extrato_prestador` (+ `_fix_alias`, `_semana_em_curso_sem_dobrar`, `_semana_em_curso_v0`),
  `contas_claras_b3_extrato_parceiro`, `contas_claras_b4_extrato_dono`, `contas_claras_b5_vigia_dinheiro`
  (cron `vigia-dinheiro-diario` 06:10). Ficheiros gémeos em `supabase/migrations/20260920*`.
- `e2e_log` fluxo `contas-claras-2026-09-20`: plano, b0.1, b1.1, b1.2, b1.3, b2.0, b2.1, b2.2, b3.1, b3.2,
  b4.1, b4.2, b5.1, b5.2, b6.x, fim.
- Analyze 0 errors; `flutter test` 569/569; anti-trapaça limpo (base HEAD).

## O que falta (por ordem)

1. **Autoteste dos três perfis e push.** Precisa de device/emulador (skill `autoteste-android`, memória
   `autoteste-android-apk-e-permissoes`). Verde → `git push origin autonomous-night-2026-04-29`
   (dispara Android + web). Antes do push: rever o que viaja junto (PADRAO §4.5).
2. **Até ao deploy web**, o botão antigo "Marcar pago" do talão no admin ainda credita a carteira.
   Talão pago por MB Way → `select public.admin_mark_receipt_paid_external('<receipt>', 'mbway', '<data>', '<ref>', '<nota>')`
   por MCP (com sessão de admin).
3. FEITO pela Claude.ai (20/09 21:44–21:53, versões 20260920204444/205140/205210/205306, espelhadas no repo):
   invólucro `_prestador_semana_em_curso`; TVDE entra no acerto semanal (colunas tvde_* em
   driver_weekly_settlements; `compute_driver_settlement` soma corridas por created_at; o fecho percorre
   entregas e corridas). `staged_contas_claras_20260920_b2` pode ser marcada como aplicada.
   Retoque do Claude Code (22:05): `extrato_prestador` e `admin_extrato_dono` deixaram de contar o TVDE a
   dobrar — semana em curso pela previsão viva; TVDE "fora do acerto" = só corridas de semanas anteriores
   sem acerto com tvde_rides_count > 0.
4. **Decisões de dinheiro do Danilo (cada uma com "vai")** — ver RELATORIO §"achados": corridas TVDE
   anteriores a esta semana que nenhum acerto contou (Valdemir 19,50; Danilo 18,30) → acerto extraordinário
   ou pagamento por fora; compensações de 1,50 no acerto; 14,20 do TVDE do Danilo (ir corrida a corrida);
   13 corridas a dinheiro sem tarifa gravada (defeito da app, todas do Danilo esta semana); payouts parados
   (Goola 2, Danilo-estafeta 1); Sabores do Brasil 10,29; linha de fecho da Isabel (−3,09, só com "vai");
   Stripe Connect da Goola desligado; a linha paga da semana em curso do Danilo (estafeta) não recebe as
   15 corridas — só se voltar a pendente.
5. **Adendo (20/09 22h–23h, blocos 7–10 feitos):** causa das corridas sem tarifa provada (pacotes/planos gravam
   só paragens; o pacote vive em tvde_roundtrip_credits.paid_cents); `tvde_rides.cash_in_hand_cents` + `fare_deduced`
   gravados por gatilho diferido (backfill 64/64); extrato lê a coluna; diálogo e badge do motorista com os três
   números. **Por aplicar pela Claude.ai (Trava):** `staged_contas_claras_20260920_b8` — o acerto semanal passa a
   ler cash_in_hand_cents em vez de deduzir ganho+corte (a regra actual dá +68,00 a mais ao Danilo em 13 corridas).
   Espelho da versão deduzida da Claude.ai em 20260920210500_*. Prova em provas/bloco7-10-prova.sql.
6. Achado lateral (não tocado): `get_driver_current_week_summary` lê `drivers WHERE id = auth.uid()`
   (identidade id≠user_id) — o `mbway_phone` vem vazio; e `v_driver_weekly_earnings` junta
   `driver_balances` por `drivers.id`. Ambos a corrigir por `user_id` (skill `identidade-estafeta`).

## Regras que esta missão fixou

- O saldo da carteira é a soma do histórico, por gatilho. Nunca mais dois números independentes.
- O histórico não se reescreve: linha nova de estorno com motivo.
- O Flutter não faz contas de dinheiro: `extrato_prestador`, `extrato_parceiro`, `admin_extrato_dono`.
- Valor que o servidor não souber aparece como "—" com a razão, nunca zero.
- O vigia só aponta; aberto cala; resolvido que volta reabre e grita. Isabel = caso conhecido.
