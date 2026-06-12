# Sessão Fechos Semanais — M1 + M2 + M3 (2026-06-12)

> Modo: ⚠️ PROTECÇÃO TOTAL · CEO-AI · BORA_DNA + business_rules lidos
> Branch: `autonomous-night-2026-04-29` · 2 commits (M1 `eae545f`, M2 `14760d6`)
> `flutter analyze`: **0 errors** · Backend **intocado** (zero RPC/tabela/cron alterado)

## M1 — Ecrã admin "💶 Fechos Semanais" ✅

Novo [admin_weekly_settlements_screen.dart](../lib/screens/admin/admin_weekly_settlements_screen.dart) (PT-BR, didático):

- **Seletor de semana** ←/→ (segunda 00:00 Lisboa; `driver_settlement_week_bounds`
  trunca server-side; não deixa navegar para futuro; range mostrado vem do server).
- **Cartão Totais da Bora** (`admin_weekly_bora_totals`): pedidos entregues,
  receita, comissões, taxas de serviço/entrega, sacos, sinais de marcações —
  cada um com legenda simples.
- **2 abas**: ESTAFETAS / PARCEIROS (contagem + ⏳ pendentes no título).
  Cada cartão: nome, nº entregas/pedidos, ganhos/vendas, cash, **saldo em
  destaque**: 🟢 "Bora paga €X" / 🟠 "Deve €X à Bora" / cinza "Sem saldo".
  Estados: PENDENTE (laranja) / PAGO·RECEBIDO (verde) / EM DISPUTA (vermelho) /
  FECHADO (cinza, saldo zero).
- **Tap → detalhe expandido**: a "conta da semana" em linguagem simples
  (ganhos − cash em mãos = saldo → quem entrega o quê a quem) + **breakdown
  pedido a pedido** (select `orders` da semana, lazy: "#A1B2 · 10/06 14:32 ·
  ganhou €5,29 · cliente pagou €19,68 em dinheiro (ficou com o estafeta)").
- **Ações com dupla confirmação** (1º diálogo com resumo + campo
  "Referência MB Way (opcional)" + aviso irreversível; 2º digitar CONFIRMAR —
  padrão da casa): direção bora_paga → `'paid'` ("MARCAR COMO PAGO");
  deve-à-Bora → `'received'` ("MARCAR COMO RECEBIDO"), via
  `admin_set_settlement_status` / `admin_set_partner_settlement_status`.
  **Audit log é gravado dentro das próprias RPCs** (verificado no prosrc).
- **Badge no menu admin** (_NavCard "Fechos Semanais", após Wallets): nº de
  fechos pendentes da **semana atual + anterior** (as tabelas têm RLS own-read,
  por isso o count usa as RPCs admin, idempotentes). Refresca ao voltar ao
  dashboard (padrão didPopNext existente).
- **Rota `/admin/settlements`** registada no main.dart — é o deep link que o
  push de 2ª-feira já envia.

## M2 — Vista do parceiro (read-only, PT-PT) ✅

Novo [partner_weekly_closeout_card.dart](../lib/widgets/partner_weekly_closeout_card.dart), 2 variantes:

- **`PartnerWeeklyCloseoutCard`** no dashboard do parceiro restaurante (logo
  abaixo de "Ver detalhe de ganhos"): "Esta semana (08/06 → 14/06): X pedidos ·
  €Y brutos" + "€Z a receber da Bora" (ou "a entregar à Bora") + "Ver semanas
  anteriores (n)" expansível com estado (Pendente/Pago/Recebido). Fonte:
  `partner_my_weekly_closeout` (current_week calculado ao momento + 8 semanas).
- **`ProviderWeeklyPayoutCard`** no hub Serviços/Barbearias (topo, após o
  header): **não existe RPC self-service para providers** — usa SELECT direto a
  `appointment_payouts` (policy `apo_select` own-read verificada; valores em
  cents ÷100). Mostra o último fecho + histórico.
- Zero ações; falha de rede → o cartão esconde-se (não parte o dashboard).

## M3 — Notificação de 2ª-feira ao admin ✅ JÁ EXISTIA

Verificado o cron `close-weekly-settlements` (2ª 00:05) → `run_weekly_closeout()`:
**já** insere em `admin_notifications` ("📊 Fecho da semana pronto — X
estafeta(s) · Y parceiro(s)…", deep_link `/admin/settlements`) **e** envia push
via Edge Fn `notify-admin-urgent` com a mesma rota (adicionado na sessão F2 de
11/06 e provado). **Nada acrescentado** — só faltava a rota Flutter, que o M1
registou. O push de 2ª agora abre direto o ecrã novo.

## Validação com dados reais (via MCP, 2026-06-12)

- Semana atual server: 2026-06-08 00:00 Lisboa ✅ (ecrã abre nela)
- Aba ESTAFETAS vai mostrar: **Danilo Fulfaro · 2 entregas · Ganhos €10,59 ·
  Cash €19,68 · "Deve €3,38 à Bora" · PENDENTE · botão MARCAR COMO RECEBIDO** ✅
- Fechos antigos `received` (semanas 25/05 e 18/05, −€1,36 e −€133,38)
  aparecem ao navegar ← ✅
- Parceiros: 2 fechos pendentes na semana 25/05 (€5,40 e €36,90
  `bora_pays_partner`) — testar o badge (deve mostrar ≥1) e o seletor ←.
- ⚠️ `drivers.mbway_phone` do Danilo está **NULL** — a linha "MB Way:" só
  aparece quando preenchido. Preencher na DB/admin quando quiseres.

## Checklist de teste (build ≥285)

**Admin:**
- [ ] Menu admin mostra "Fechos Semanais" com badge (≥1)
- [ ] Ecrã abre na semana atual com o fecho do estafeta −€3,38 PENDENTE
- [ ] Expandir → equação simples + 2 pedidos listados
- [ ] ← 2× → semana 25/05: parceiros pendentes (€5,40 / €36,90) + estafeta recebido
- [ ] "MARCAR COMO RECEBIDO" → 2 confirmações → chip vira RECEBIDO
- [ ] `admin_audit_log` tem `settlement_set_status` com o teu admin_id
- [ ] Tap no push de 2ª-feira abre o ecrã (rota /admin/settlements)

**Parceiro:**
- [ ] Dashboard restaurante: cartão "O meu fecho semanal" carrega sem erro
- [ ] Histórico expande com semanas anteriores
- [ ] Hub barbearia: cartão "Último fecho" (se houver payouts persistidos)

## Notas / fora de âmbito (documentado)
- `admin_mark_partner_payouts_paid` / `admin_mark_appointment_payouts_paid`
  (repasses de reservas/marcações) NÃO entraram nas abas — já têm ecrã próprio
  (`admin_appointments_payouts_screen`) e o prompt só pedia as 2 ações set_status.
- Badge cobre semana atual+anterior; pendentes mais antigos (ex.: parceiros de
  25/05) são visíveis no ecrã ao navegar ←, mas não contam no badge (RLS não
  permite count global ao admin sem nova RPC — proibido criar nesta sessão).
- Estado `disputed` existe no backend; a UI mostra-o (chip vermelho) mas não há
  ação para o definir — fica para sessão futura se precisares.
