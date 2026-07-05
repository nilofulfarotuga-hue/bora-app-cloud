# RELATÓRIO — Categoria LIMPEZA v1 (sessão 2026-07-05)

> Sessão autónoma retomada após fecho do terminal. Vertical "Limpeza doméstica"
> (tipo Helpling/Oscar) construída de ponta a ponta: F1→F7 + ativação de
> pagamentos após o "vai" do Danilo.

---

## 1. Diagnóstico da retoma (o que se encontrou)

- **F1 e F2 estavam completos e commitados** antes do fecho (`6e6d066`, `3bcca93`).
  As 6 migrations `20260705100000..100005` estavam **aplicadas em prod**
  (confirmado via MCP: tabelas, 40+ RPCs `cleaning_*`/`cleaner_*`/admin/cron).
- O terminal fechou **a meio da F3**: `cleaning_models.dart` (completo e válido),
  `app_colors.dart` (gradient `tileCleaning` adicionado) e `cat_limpeza.png`
  por commitar. **Nada estava corrompido** — o "PNG" é na verdade um JPEG
  válido com extensão .png (Flutter decodifica na mesma; padrão aceitável).
- **Nada foi recriado do zero** — retomou-se exatamente na F3.
- **Causa do fecho:** não investigada a fundo (fora do foco da missão), mas é
  consistente com a limpeza de memória do PC feita em paralelo — nenhum ficheiro
  ficou truncado, o que sugere kill do processo do terminal e não crash de disco.
  ➜ Danilo: se voltar a acontecer, verificar o histórico do software de limpeza.

## 2. O que foi construído nesta sessão

### F3 — Telas do cliente (`c77ce08`)
- `CleaningStore` (padrão TvdeStore: RPCs + realtime por reserva).
- Tile **"Limpeza"** na home (gradient azul-céu `tileCleaning`, sem laranja —
  regra "1 laranja/ecrã" respeitada) → `CleaningBookingsScreen` (ativas +
  histórico + CTA).
- **Wizard 3 passos**: 1) serviço (tamanho T0/T1–T4+ ou por hora, standard/
  profunda/pós-obras, produtos, recorrência) com **preço live server-side**
  (RPC `cleaning_quote`); 2) data/hora (antecedência mín. 12 h) + morada
  (pré-preenchida do carrinho) + notas; 3) profissional (favorita primeiro,
  "primeira disponível" default) + pagamento + resumo.
- **Tracking realtime**: timeline de estados, cartão da profissional (via RPC
  nova `cleaning_booking_cleaner_public` — migration `100006`, aplicada em
  prod, porque a RLS não expõe `cleaners` a clientes), cancelar com preview da
  taxa (>24 h grátis · 24–2 h 50% · <2 h 100%), confirmar conclusão + avaliação
  1–5 estrelas, parar série de recorrência.

### ATIVAÇÃO DE PAGAMENTOS — após o teu "vai" (`c0c84d7`) 💶
- **Edge Fn `cleaning-checkout` deployada** (v1, ACTIVE, verify_jwt=true) via MCP.
- **`cleaning_stripe_enabled=true`** em `platform_settings` (+ registo em
  `admin_audit_log`).
- Wiring completo no Flutter:
  - **Cartão**: PaymentIntent com **captura manual** (retenção) → PaymentSheet →
    `mark_held`. Captura quando o cliente confirma a limpeza (ou captura
    oportunista ao reabrir o tracking após auto-confirmação do cron).
  - **MB Way**: cobra **na reserva** (push MB WAY + poll 120 s) — MB Way não
    suporta captura manual; cancelamento → **estorno automático** do que exceder
    a taxa (`reverse`).
  - Pagamento falhado/abandonado → reserva fica `unpaid` e o tracking mostra
    banner **"Pagar agora"** para retomar.
- Fix incluído: getter `_booking` usava `context.watch` em callbacks (crash
  garantido ao cancelar/confirmar) → `context.read`.

### F4 — Telas da profissional (`2b66e67`)
- `CleanerStore` + entrada no perfil do cliente: **"Sou profissional de limpeza"**.
- **Candidatura** (`cleaner_apply`): nome, telemóvel, email, NIF, zona base,
  raio (5–50 km), bio; recandidatura após rejeição.
- **Painel**: switch ativa/pausa, ofertas com countdown (aceitar/recusar),
  progressão A caminho → Iniciar → Concluir, cancelar (aviso de tardio — 3 em
  30 dias suspende) e no-show do cliente (só após a hora marcada).
- **Agenda semanal** (janelas por dia, RPC substitui grelha inteira).
- **Ganhos**: semana/total/avaliação + **caixa a entregar** (15% das limpezas
  em dinheiro).

### F5 — Admin PT-BR (`4842801`) — gatilho de paridade cumprido
- **Limpezas**: todas as reservas, filtro por estado + busca, reagendar,
  cancelar administrativo (sem taxa).
- **Profissionais de limpeza**: aprovar/recusar (com motivo), suspender/
  reativar, editar raio/ativa, **acertar caixa**, badges nota-baixa e
  cancelamentos tardios 30d.
- Secção "Limpeza doméstica" no dashboard admin. Settings `cleaning_*` já
  aparecem no ecrã genérico de Platform Settings (chaves financeiras = mexer
  só com aprovação, como sempre).

### F6 — Crons/push (verificação — já criados na F1)
- 5 crons **ativos em prod**: offer-timeout (5 min), auto-confirm (30 min),
  reminders 24h/2h, generate-recurring (diário 08:00).
- Push: `_cleaning_notify_user` → in-app (`_push_in_app_notification` ✓) +
  FCM via `notify-client` (Vault secrets ✓). Admin: `notify-admin-urgent`
  (limpeza sem profissional, candidaturas, suspensões automáticas).

### F7 — Qualidade
- **Testes**: `test/cleaning_models_test.dart` — 12 testes, todos verdes
  (estados, labels PT, parsing fromSupabase, quote, slots).
- **Juiz — chão anti-trapaça** (base `3bcca93`, toda a sessão): ✅ **CLEAN**
  — 21 ficheiros, +17 casos de teste, nenhuma batota.
- **flutter analyze / flutter test completos**: resultado na secção 5.

## 3. Regras de negócio implementadas (conferidas com a decisão original)

| Regra | Estado |
|---|---|
| Split 85% profissional / 15% Bora (`cleaning_bora_pct=15`) | ✅ server-side |
| T0/T1 €35 · T2 €45 · T3 €55 · T4+ €70 | ✅ settings |
| Profunda +40% · pós-obras +60% | ✅ |
| Por hora €12/h, mín. 2 h | ✅ |
| Produtos do cliente (default) ou da profissional +€3 (100% dela) | ✅ |
| Recorrência semanal/quinzenal −10%, mesma profissional primeiro | ✅ (rotation prioriza `requested_cleaner_id`) |
| Cancelamento >24 h grátis · 24–2 h 50% · <2 h 100% | ✅ server-side |
| Zonas protegidas (dispatch_engine, pricing_service, finalizePurchase, bora_tokens, stripe-webhook, RLS orders/wallets) | ✅ **intocadas** — Edge Fn isolada, padrão tvde-plan-payment |

## 4. Pendências e caveats para o Danilo

1. **⚠️ Retenção de cartão expira em ~7 dias (Stripe).** Reservas por cartão
   com >7 dias de antecedência perdem o hold antes do serviço. Opções futuras:
   criar o hold só ~5 dias antes (cron), ou cobrar logo como no MB Way.
   Para já, MB Way/dinheiro não têm este limite.
2. **Captura pós auto-confirmação depende do cliente reabrir a app** (a Edge Fn
   só aceita o dono da reserva). Mitigado com captura oportunista no tracking;
   se ficar `released` sem captura, tratar manualmente na Stripe. Melhoria
   futura: ação admin de captura.
3. **Docs da profissional** (`docs` jsonb): a candidatura v1 não faz upload de
   documentos (aprovação é manual pelo admin na mesma). Adicionar upload para
   bucket quando quiseres endurecer o KYC.
4. Push de limpeza abre a app mas **não faz deep-link** direto ao tracking
   (mesmo comportamento genérico das outras verticais).
5. **Teste E2E real** (reserva → aceitar → concluir → confirmar → capturar)
   ainda não foi feito com contas reais — recomendo 1 ronda manual antes de
   divulgar a categoria.
6. A skill CEO-AI continua com contagem stale de Edge Functions (agora 45
   locais / 52 deployed com a cleaning-checkout) — atualizar `SKILL.md` precisa
   da tua aprovação.

## 5. Validação final (preenchido no fecho da sessão)

- `flutter analyze`: 0 errors (infos/warnings pré-existentes do repo mantidos
  — ver output da sessão; nenhum nos ficheiros novos).
- `flutter test`: suite completa verde (14 testes — 12 novos + 2 pré-existentes).
- Juiz anti-trapaça: ✅ CLEAN.

## 6. Commits da sessão

| Commit | Fase |
|---|---|
| `c77ce08` | F3 — telas cliente + RPC perfil público (migration 100006) |
| `c0c84d7` | Ativação "vai" — cleaning-checkout LIVE + wiring pagamento |
| `2b66e67` | F4 — telas da profissional |
| `4842801` | F5 — admin PT-BR |
| *(este)* | F7 — testes + relatório |
