---
name: painel-admin-limpo
description: >
  Regras do painel admin (PT-BR, só o Danilo) que já foram corrigidas mais de uma vez e
  não podem voltar a partir: hora de Lisboa em todos os contadores, dados de demonstração
  fora de contas e de dinheiro, um hub por assunto em vez de ecrãs duplicados, cada feature
  nova com correspondência no painel, e nunca somar verticais diferentes no mesmo número.
  Usar sempre que se cria ou altera um ecrã, um cartão, um RPC ou um relatório do painel
  admin, e sempre que uma feature nova pede o gatilho de paridade (agente `admin`).
metadata:
  versao: 1.0
  execucoes: 1
  sucessos: 1
  falhas: 0
  ultima_execucao: 2026-09-14
  criada_por: missão painel-admin-limpo (2026-09-14, Opus)
---

# PAINEL ADMIN LIMPO — as cinco regras que já custaram dinheiro ou confusão

> Escrito a 14/09/2026 depois de uma noite em que o painel dizia "Pedidos hoje 1" (era um
> pedido de demonstração, e ainda era "ontem" em UTC), "12,15 € a pagar a estafetas" (era o
> livro inteiro desde sempre; o acerto da semana eram 7,04 €), tinha sete ecrãs de dinheiro a
> dizer quase o mesmo, e um robô tinha tirado 12 € a um barbeiro por ele se ter esquecido de
> um botão. Cada regra tem a cicatriz. Entra pelo CEO-AI; não substitui o `PADRAO_BORA.md`.

## 1. Hora de Lisboa em tudo o que diz "hoje", "esta semana", "este mês"

**Regra.** Nunca `date_trunc('day', now())`, nunca `CURRENT_DATE`, nunca `::date` solto num
`timestamptz`. O servidor está em UTC; a Guarda está em `Europe/Lisbon`. Entre a meia-noite
e a uma da manhã (verão) o "hoje" em UTC ainda é ontem.

**Como se faz.**
```sql
v_day_start := (date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
-- semana: public.driver_settlement_week_bounds(now())  (segunda 00:00 → domingo 23:59:59 de Lisboa)
```
Rótulos (`14/09`, `14/09 a 20/09`) saem do servidor com `to_char(x AT TIME ZONE 'Europe/Lisbon', ...)`
— o Flutter não formata datas de "hoje" com `DateTime.now()`, porque o painel web pode estar
noutro fuso. **A `week_start_at` guardada é `2026-09-06 23:00+00` para a semana de 07/09: é
consistente, não se "corrige".**

**Cicatriz (14/09 00:18):** `admin_dashboard_metrics.orders_today` contava com `date_trunc('day', now())`
e `admin_reservations_today` com `CURRENT_DATE`. Ambos mostravam o dia anterior até à 01:00.

## 2. Dados de demonstração fora de contas e de dinheiro

**Regra.** Um número que o Danilo vê nunca inclui contas nem pedidos de demonstração, salvo se
`platform_settings.admin_show_demo_data = true` (interruptor no fim do painel, para ele testar).
E o dinheiro é ainda mais estrito: **demo nunca entra em acerto, digest nem recibo**, com ou sem
interruptor.

**Uma só definição de demo, no servidor**, nunca listas soltas no Flutter ou nas Edge Functions:
`public.is_demo_email(text)` (padrões em `platform_settings.admin_demo_email_patterns`),
`is_demo_user(uuid)`, `is_demo_driver(text)` (aceita `drivers.id` ou `user_id`),
`is_demo_restaurant(text)`, `is_demo_provider(text)`, `is_demo_order(orders)`,
`is_demo_subject(tipo, id)`, e o interruptor `admin_demo_visible()`.

**Padrões que SÃO demo:** `demo%@bora.app`, `teste%@bora.app`, `prova.%@bora.app`,
`%@boraapp.test`, `%@test.com`, `e2e_%`, `test_%`, mais `orders.is_test_order`, a loja
`demo-parceiro-loja` e o estafeta `dede0000-…-0002` (user `…-0001`).

**Padrões que NÃO são demo (armadilhas provadas por SQL a 14/09):**
- `%@bora.app` — `ouro.prata@bora.app` (a Barbearia Ouro e Prata), `mr.kebab@`, `saboresde.casa@`,
  `sabores.brasil@`, `beunique@`, `lava.leva@` são **parceiros reais** com email sintético.
  Aplicar `%@bora.app` tirava o acerto do barbeiro.
- `%demo%` solto — `alefernandesdemoura03@gmail.com` é cliente real ("demo" no meio de "de moura").

**Onde o filtro vive:** trigger `trg_acerto_ignora_demo` (BEFORE INSERT nas 5 tabelas de acerto)
e `trg_digest_ignora_demo` (em `weekly_digest_log`) — o sujeito demo nunca ganha linha, venha
do cron, do recálculo manual ou do painel; RPCs do painel filtram com
`(public.admin_demo_visible() OR NOT public.is_demo_order(o))`. As três funções canónicas de
cálculo (`compute_driver_settlement`, `compute_partner_weekly_settlement`,
`compute_provider_weekly_payout`) estão na lista da Trava: o filtro por pedido/marcação fica em
`supabase/migrations/PROPOSTA_20260914_acertos_compute_sem_demo.sql` até o Danilo dizer "vai".

## 3. Um hub por assunto, nunca sete ecrãs a dizer quase o mesmo

**Regra.** O menu do painel vive **num registo único** (`lib/screens/admin/admin_menu_registry.dart`):
um ecrã, uma entrada, uma secção, uma linha em PT-BR simples a dizer o que faz. Quem duplicar
outro vai para "Arquivado" com o motivo escrito, e **continua a abrir** (nada se apaga; os
ecrãs antigos de dinheiro abrem o hub `AdminAcertosSemanaScreen(filtroInicial: ...)`).
O dashboard só desenha (`admin_menu_accordion.dart`: secções fechadas, busca, favoritos,
arquivado escondido). Nunca voltar a pôr `_NavCard` à mão no dashboard.

**Critério de arquivo:** sem uso em 30 dias (medir no `admin_audit_log` e nas tabelas), sem
dados, ou duplica outro. Escrever o motivo no item (`archivedReason`).

**Dinheiro = um hub:** "Dinheiro e acertos" (`admin_acertos_semana_screen.dart`) com separadores
por tipo (estafetas, parceiros, barbearias, limpeza, lavagem), um só botão de marcar
pago/recebido, recibo, CSV, configuração, e a fila "Mais ferramentas de dinheiro" para os ecrãs
de detalhe. Rota `/admin/acertos-semana` (o aviso do fecho abre aqui, na semana certa);
`/admin/settlements` reencaminha.

**Cicatriz:** "Pagamentos", "Acerto semanal por pessoa", "Acertos da semana", "Fechamento
Semanal — Estafetas", "Repasses a Parceiros", "Acerto reservas parceiros", "Fechamento Semanal —
Barbearias", "Pagamentos Connect", "Fechamento Semanal — Limpeza" — nove entradas, e o Danilo
não sabia em qual estava o número certo.

## 4. Cada feature nova tem correspondência no painel (autoridade total)

**Regra.** Tudo o que se cria ou altera tem, no painel, **ver, editar/decidir, criar (quando faz
sentido), banir/suspender, configurar, exportar CSV e auditar**. Toda a acção nova escreve em
`admin_audit_log` — e atenção: `log_admin_action(text,text,TEXT,jsonb)` escreve numa tabela
`admin_logs` que **não existe** e engole o erro; a sobrecarga certa é a que recebe
`entity_id uuid` (passa-se o uuid sem `::text`). Prova em rollback antes: `audit=0`; depois: `audit=1`.

Um RPC novo do painel chama `_admin_op_guard()` no início, `REVOKE ... FROM PUBLIC, anon` e
`GRANT EXECUTE ... TO authenticated, service_role` no fim. Chaves novas de configuração entram
em `platform_settings` com `category` para aparecerem no ecrã "Configurações".

**Exemplo desta missão:** a falta das marcações deixou de ser automática → ecrã "Marcações por
confirmar e faltas" (`admin_marcacoes_confirmacao_screen.dart`): listas, "Foi feita"/"Faltou"/
"Perguntar de novo"/"Reverter" a 1 toque, CSV, e cada decisão no histórico; rotas
`/admin/marcacoes-por-confirmar` e `/admin/dinheiro-retido-falta` para os avisos abrirem lá.

## 5. Nunca somar verticais diferentes no mesmo número

**Regra.** Entregas, Bora Motorista (TVDE), Serviços/Barbearias, Limpeza, Lavagem e Reservas
são linhas separadas, com o nome à frente; **zero é zero e aparece**, não desaparece. Só o
dinheiro tem um total, e mesmo esse leva a decomposição por vertical em letra pequena
(`_admin_receita_bora_cents` devolve `total_cents` + `<vertical>_cents`).

O "a pagar / a receber" da semana fechada lê-se **das tabelas de acerto** (as mesmas do hub),
nunca do `ledger_entries` inteiro. Prova obrigatória: um SQL que junta o RPC e as tabelas na
mesma consulta e mostra os dois lados iguais (ver relatório de 14/09, 14 linhas RPC = base).

**Cicatriz:** o cartão "A pagar — drivers 12,15 €" somava `ledger_entries.user_type='driver'`
desde sempre; as linhas de `driver_weekly_settlements` da semana davam 7,04 €.

## Como se prova um cartão do painel (checklist)

1. `set_config('request.jwt.claims', ...)` com `app_metadata.role=admin` e chamar o RPC por SQL.
2. Na mesma consulta, recalcular o número directamente da tabela, em Lisboa e sem demo.
3. Os dois lados iguais → prova. Um `200` do RPC não prova nada.
4. Foto do ecrã via teste golden (`test/golden/painel_admin_limpo_test.dart`) com o JSON real —
   o `AdminDashboardContent` é widget puro, fotografa-se sem Supabase.

## Ficheiros

`lib/screens/admin/admin_dashboard_screen.dart` (carrega e navega) ·
`admin_dashboard_content.dart` (desenho, puro) · `admin_menu_registry.dart` (menu) ·
`admin_menu_accordion.dart` · `admin_acertos_semana_screen.dart` (hub de dinheiro) ·
`admin_marcacoes_confirmacao_screen.dart` · RPCs `admin_dashboard_metrics_v2`,
`_admin_receita_bora_cents`, `admin_list_appointments_awaiting_confirmation`,
`admin_list_appointments_retained`, `admin_appointment_confirm_done|mark_no_show|revert_no_show|ask_partner_again`,
`weekly_closeout_excluidos` · testes `test/painel_admin_limpo_test.dart` e
`test/golden/painel_admin_limpo_test.dart`.

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
