# CONTINUAR — ronda-dinheiro-despacho-2026-10-05

Relatório: `.claude/.ai/reports/2026-10-05-ronda-dinheiro-despacho.md`.
Tudo o que está pronto mas não aplicado vive em `.claude/.ai/missoes/ronda-04-10/pronto/LEIA.md`.

## 1. Motor de despacho v62 — precisa da Trava aberta (só o Danilo abre)

Proposta completa e simulada (14 de 14) em `pronto/dispatch-engine-v62/`. Aplicar =
copiar `index.v62.PROPOSTA.ts` para `supabase/functions/dispatch-engine/index.ts`,
publicar com `verify_jwt=false`, provar (403 sem token e com a chave pública; 200 por
`invoke_dispatch_engine`; registos com "N candidatos"), commit do ficheiro.
Antes de aplicar, voltar a conferir o ar contra o repo (ver memória
`verificar-edge-no-ar-antes-de-deploy`): a 05/10 o ar era a v61 = ficheiro do repo.

## 2. Fecho do "parceiro chama estafeta" — missão própria, depois ligar o interruptor

Análise e números em `pronto/LEIA.md` §4. Funções a tratar: `post_order_to_ledger`,
`apply_order_financial_split`, `order_driver_reimbursement` / `apply_driver_cash_settlement`,
extractos do parceiro e fecho semanal. Provar em transacção desfeita com um pedido de
10 € de balcão (certo: loja deve 4,00 à Bora, estafeta recebe 4,00, Bora 0).
Só depois: `dispatch_parceiro_chama_estafeta_ligado = true` (painel, Configurações → dispatch).

## 3. Missões da ronda que nunca arrancaram e não têm texto

`dinheiro-entregas` e `admin-dinheiro`: não há enunciado no repo nem na base (os
`achados/*.md` perderam-se; as missões ficaram na conversa da Claude.ai). A Claude.ai
tem de as escrever em `.claude/.ai/missoes/ronda-04-10/` para alguém as poder executar.

## 4. Restos pequenos (ver `pronto/LEIA.md` §2, §3 e §5)

- Favor: função própria para o dinheiro da paragem em casa (ficheiro trancado).
- `pricing_service.dart`: só arrumação do valor de reserva (2,50 → 0,99).
- Festas: o orçamento conta o saco (`festas_money_patch` por aplicar desde 25/08).
- "Deixar à porta" + dinheiro: guarda no servidor para pedidos forjados.
- Rascunhos de pagamento: tirar o botão de excluir ou dar-lhe função própria.
- Sinal com segredo: exigir `is_online`; mais tarde fechar o `driver_heartbeat_by_id` a quem não tem sessão.
- Carrinho abandonado: decidir se o aviso respeita "só quem aceitou promoções" antes de ligar.

## 5. Da ronda, fora de dinheiro e despacho (não tocado)

- `_notify_partner_status_change` chama o `notify-partner` com a chave pública → 403
  (os avisos de mudança de estado ao parceiro não saem; já falhavam antes com 400).
- `log_admin_action` aceita qualquer utilizador autenticado.
- Apagar os dois ecrãs mortos do parceiro (`restaurant_dashboard_screen.dart`,
  `partner_reservations_screen.dart`) e fechar as 2 linhas antigas de `cortex_red_proposals`.
- O push `carrinho_abandonado` devia abrir o carrinho ao tocar.

## 6. Só se prova no aparelho

- Estafeta com a app em segundo plano: o sinal continua a bater (com segredo; e com o
  caminho antigo se o segredo falhar) — ver `drivers.last_heartbeat_at` e
  `driver_heartbeat_segredos.usado_em`.
- Cliente: "Deixar à porta" com cartão e MB Way ponta a ponta; o estafeta vê o aviso e
  a foto fica gravada.
