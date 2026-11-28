# Planos de limpeza — Bloco B (servidor) · PROPOSTA

⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO.** Está tudo pronto e provado num Postgres local; **nada foi aplicado
em produção** por esta sessão (missão `limpeza-planos-fecho-2026-11-28`). Quem aplica e publica é a
Claude.ai, por MCP, com o autorizo do Danilo de 28/11/2026 (09:25, 10:28, 11:43).

Segue à letra a página do livro `limpeza-planos-b-especificacao-2026-11-28`.

## Estado (28/11/2026, fim da tarde)

- **APLICADO pela Claude.ai:** `20261128161413_limpeza_planos_b_2026_11_28` (= `migracao.sql` do commit 7417c463,
  md5 b4862924) e `20261128161521_limpeza_planos_b_fechar_permissoes` (as funções internas e do robô ficavam com
  EXECUTE para `authenticated` por causa dos privilégios por defeito do Supabase). As duas estão em `supabase/migrations/`.
  Provas 13/13 no servidor. Edge publicadas a partir de 7417c463.
- `migracao.sql` desta pasta já tira também `authenticated` no ciclo das permissões (provado num Postgres com os
  privilégios por defeito do Supabase: antes da correção a P12 falhava, depois 13/13).
- `provas.sql` dá telemóvel aos clientes da prova (desde 28/11 10:19 não há reserva sem telemóvel, SEM_TELEFONE).
- App: o assistente do plano pede o telemóvel (`garantirContactoDoCliente`) antes de `cleaning_plan_create`.
- Falta: os 2 eventos novos no webhook da Stripe da empresa (sem permissão de escrita no conector; são só a rede).

## O que há aqui

| ficheiro | o quê |
|---|---|
| `migracao.sql` | 4 tabelas (`cleaning_plans`, `cleaning_plan_charges`, `cleaning_plan_charge_items`, `cleaning_plan_refunds`), `plan_id`/`plan_visit_date` em `cleaning_bookings`, RLS, funções do cliente/profissional/painel/robô, gerador, exceção da oferta, devoluções, 2 agendamentos |
| `provas.sql` | 13 provas dentro de `BEGIN … ROLLBACK` (nada fica gravado) |
| `../../../supabase/functions/cleaning-plan/` | Edge da app: guardar/trocar cartão (SetupIntent) e 3D Secure |
| `../../../supabase/functions/cleaning-plan-charge/` | Edge do robô: cobra 24 h antes, novas tentativas, devoluções ao cartão |
| `../../../supabase/functions/stripe-webhook-empresa/` | v2: trata os eventos dos planos antes do tratamento de sempre (`planos.ts`) |
| `../../../supabase/functions/cleaning-checkout/` | v5: visita de plano → `reverse` recusa (e criar/marcar à parte também) |

## Como aplicar (por esta ordem)

1. `migracao.sql` (MCP `apply_migration`, nome `limpeza_planos_b_2026_11_28`). Idempotente; sem DROP de nada que exista.
   Depois copiar para `supabase/migrations/<versão>_limpeza_planos_b_2026_11_28.sql` com a versão que o servidor deu.
2. `provas.sql` (MCP `execute_sql`): tem de mostrar `PROVA_OK` de P1 a P12 (13 linhas) e acabar em ROLLBACK.
3. Publicar as Edge (skill `deploy-edge-function`): `cleaning-plan` (verify_jwt **true**),
   `cleaning-plan-charge` (verify_jwt **true**; só o servidor), `stripe-webhook-empresa` (manter verify_jwt **false**),
   `cleaning-checkout` (manter verify_jwt **true**).
4. Stripe da EMPRESA → Webhooks → o destino `stripe-webhook-empresa`: **juntar** `setup_intent.succeeded` e
   `payment_intent.requires_action`.
5. Ligar os robôs (support_skills `edac8adc-…` e assistant_learned `27f44606-…`: `active = true`) só depois de publicado.

Definições usadas com valor por defeito (não se cria nada em `platform_settings`): `cleaning_plans_enabled` (true),
`cleaning_plan_min_lead_hours` (36), `cleaning_plan_horizon_days` (14), `cleaning_plan_charge_hours_before` (24).
Também `cleaning_enabled` e `cleaning_stripe_enabled` (já existem).

## O que se provou (28/11/2026, Postgres 16 local com as 1013 migrações do repo)

- `migracao.sql` aplica sem erros e uma segunda vez também (idempotente).
- `provas.sql`: **13/13 PROVA_OK** — criar (e 6 erros com as palavras que a app traduz), ativar e gerar visitas
  (30,00 € cliente / 27,54 € profissional / 2,46 € Bora no semanal de 3 h), preço por vaga numa equipa de 2
  (63,00 €: vaga 1 33,00 €/30,54 €, vaga 2 30,00 €/27,54 €), oferta antes de cobrar só nos planos, saltar,
  cobrança com e sem profissional, Bora Empresas (14 €/h, recibo para o email de faturação com NIF, acesso
  só no dia), nova tentativa (-a1 recusado → -a2; rede repete -a2), 3D Secure e webhook, devolução à
  carteira (cliente desmarca) e ao cartão (pausa no painel, auditada), chamadas repetidas contadas uma vez,
  cancelar o plano, painel e permissões (fechadas a anon; as do robô só para o servidor).
- Edge: `deno check` OK nas 3 novas/alteradas; 22 testes Deno verdes (15 novos + os 7 do casa-checkout).
- **Não provado**: nada com a Stripe a sério (precisa da migração aplicada e das Edge publicadas; testar com
  cartão de teste `4242…` e `4000 0025 0000 3155` para o 3D Secure, em modo teste).
- O ensaio local tem 3 peças simuladas (não existem nas migrações do repo): `public.users`,
  `_alerta_quem`, `tem_aparelho`; e `wallet_split_free_pct = 1` como está no ar desde 28/10.

## Decisões tomadas (dizer ao Danilo)

1. **A CONFIRMAR (da especificação):** ao cancelar o plano, a limpeza das próximas 24 h que já tem
   profissional confirmada mantém-se (e cobra-se). O ecrã já diz isso.
2. Visitas desmarcadas pelo sistema (pagamento falhado, mudança de horário/horas, pausa do admin) ficam
   `cancelled_client` com `cancelled_by = 'admin'` (a tabela só aceita client/cleaner/admin) e motivo `plano_*`.
3. Se a devolução à carteira falhar, o cancelamento dessa visita desfaz-se (nunca há visita desmarcada sem o dinheiro).
4. `cleaning-checkout` também recusa **criar** um pagamento à parte para uma visita de plano (não só o `reverse`):
   evita cobrar duas vezes se alguém tocar em "Pagar" na lista de limpezas.

## Linhas para o e2e_log (fluxo `limpeza-planos-2026-11-28`; a Claude.ai grava)

- `A-app` · ok · patch p1..p4 conferido (md5 e0438da1…), `git am` limpo; +111 traduções EN que faltavam; analyze 0 erros; 4112 testes verdes.
- `B-servidor` · precisa-claude-ai · proposta escrita (`migracao.sql`, 4 Edge); motor Opus 5.5.
- `C-provas` · ok · 13/13 PROVA_OK local; deno check + 22 testes Deno; Stripe real por provar.
- `fora-de-scope` · `cleaning-checkout/index.ts` (reverse, TRAVA 1, `jaFeitos.data.find((x) => …)`) dá TS7006 no `deno check` com os tipos npm do Stripe — já acontecia antes desta mudança; não mexido.
