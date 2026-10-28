# Bloco 2 (dinheiro) — parte do servidor — LEIA-ME

Missão `missao-geral-2026-10-28`. Agente `pagamentos-wallet` (só lê e prepara). 28/10/2026.
Nada foi publicado, nenhuma migração aplicada, nenhum commit. Só SELECT no banco.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## A regra (Danilo, 28/10 18:24)

Quem paga com MB Way ou cartão recebe pelo mesmo meio, e é o que vem por defeito (MB Way na hora,
cartão 5 a 10 dias úteis). Em vez disso o cliente pode escolher 100% em saldo Bora, já. Os tokens
gastos voltam como TOKENS, com a validade que tinham; os não gastos não se devolvem. Acabou o 80/20.
Já no ar: `wallet_split_free_pct = 1.0` (SELECT 28/10 confirma) e o gatilho do sistema chama o
`auto-refund-order`.

## O que está pronto

No repo da cópia de trabalho (`C:\BoraLocal\wt-missao-geral-28-10`, ramo `missao-geral-2026-10-28`,
sem commit), funções que não são zona vermelha:

- `supabase/functions/cancel-order-with-choice/index.ts` → v19: sem `refund_method` = volta ao meio
  original; textos (MB Way na hora, cartão 5 a 10 dias úteis, saldo 100% sem "saldo livre + tokens",
  "os teus N tokens voltaram"); taxa sai do dinheiro quando os tokens voltam (`tokens_applied_count > 0`);
  resposta com `tokens_devolvidos`.
- `supabase/functions/execute-cancellation/index.ts` → v16: mesmos textos e mesma conta da taxa.
- `supabase/functions/admin-cancel-order/index.ts` → v15: texto ao cliente diz o meio (deixa os
  "3-5 dias úteis") e os tokens; comentário 80/20 corrigido.
- `supabase/functions/auto-refund-order/index.ts` → v4: quando o sistema cancela um pedido pago a
  MB Way/cartão que também usou saldo, a parte do saldo volta ao saldo (hoje perde-se).

Nesta pasta (zona vermelha, para o Claude.ai aplicar):

- `01_shared_cobranca_stripe.md` — `_shared/cobranca_stripe.ts` v2 inteiro: tokens fora do "pago" e
  da carteira; 100% ao meio escolhido. Provado localmente (6/6).
- `02_client-cancel-order_index.md` — `client-cancel-order` v30 inteiro.
- `03_tokens_gastar_e_devolver.md` — SQL: tabela `pedido_tokens_gastos` (RLS), `consumir_tokens_do_pedido`
  + gatilho no INSERT do pedido (passo 1), ponte no `consume_tokens` para apps antigas,
  `devolver_tokens_do_pedido` + gatilho no cancelamento (passo 2), `fn_reembolso_cancelado_pelo_sistema`
  v3 (sem a janela de tempo; saldo de pedidos a dinheiro volta). Backups `bkp_*_20261028`.
  Provado localmente em PGlite: 6 blocos aplicados, 21 verificações OK, 0 falhas.
- `04_reprocess-refund_e_refund.md` — `reprocess-refund` v4 (MB Way falhado deixa de ir para o
  saldo) e o texto do `refund`.

## Ordem de aplicação (não trocar)

1. Publicar JUNTAS, com o `_shared/cobranca_stripe.ts` v2: `client-cancel-order` (02),
   `cancel-order-with-choice` v19, `execute-cancellation` v16, `admin-cancel-order` v15 (estes três
   do repo da cópia de trabalho). Com os pedidos de hoje (contagem de tokens = 0) o dinheiro
   devolvido é igual ao de agora; só mudam os textos e o defeito do `refund_method`.
   Atenção: o repo usa `secretKey()` (`_shared/keys.ts`); o que está no ar usa
   `SUPABASE_SERVICE_ROLE_KEY`. Confirmar a chave com `chaves-diagnostico` antes.
2. Publicar `auto-refund-order` v4 e `reprocess-refund` v4 (+ texto do `refund`).
3. Só depois do passo 1: aplicar o SQL da proposta 03, numa só migração (passos 1 e 2 dos tokens
   juntos). Se fosse ao contrário, o `_shared` velho contaria os tokens e creditava-os como saldo.
4. Na próxima versão da app: `payment_method_screen.dart` deixa de chamar `consume_tokens`
   (descrito na proposta 03). A ponte fica até a versão mínima obrigatória já não chamar.
5. Pôr as migrações no repo (`supabase/migrations`, `[skip ci]`), como no ficheiro
   `../MIGRACOES-POR-POR-NO-REPO.md`.

## Provas esperadas

- Passo 1: `get_edge_function` das 4 → `_shared/cobranca_stripe.ts` sem `usouTokens` e com
  `Math.min(pedido - stripeCents, pago.walletCents)`; versões 30 / 19 / 16 / 15.
- Passo 2: `get_edge_function auto-refund-order` com `saldo_cents`; `reprocess-refund` com `vaiStripe`.
- Passo 3: `select to_regclass('public.pedido_tokens_gastos')` não nulo; os 2 gatilhos em
  `pg_trigger`; backups com 1 linha cada; a prova em rollback da proposta 03 (pontos 1 a 8).
- Primeiro pedido real com tokens depois do passo 3: `orders.tokens_applied_count > 0` e linhas em
  `pedido_tokens_gastos`; se for cancelado, `devolucao_resultado = 'devolvido'`.

## Repo vs o que está no ar (get_edge_function, 28/10)

- `client-cancel-order` v29, `cancel-order-with-choice` v18, `execute-cancellation` v15,
  `admin-cancel-order` v14, `reprocess-refund` v3: lógica igual ao repo; a única diferença é a chave
  (`SUPABASE_SERVICE_ROLE_KEY` no ar, `secretKey()` no repo, commit 14fb9994). O
  `_shared/cobranca_stripe.ts` empacotado nas 4 primeiras é igual ao do repo.
- `auto-refund-order` v3 e `refund` v25: iguais ao repo.

## Textos do servidor que ainda falam de 80/20, tokens ou "cartão" para MB Way

Já corrigidos no repo (por publicar): `cancel-order-with-choice` (antes linhas 297 e 299),
`execute-cancellation` (230 e 232), `admin-cancel-order` (36 e comentário 228).
Na proposta 02: comentário 194-196 do `client-cancel-order`. Na proposta 04: `refund/index.ts:81`.
Fora do meu âmbito, por corrigir (agente `chat-suporte`):
- `supabase/functions/support-chatbot/index.ts:425-428` — o robô de suporte diz aos clientes
  "80% saldo livre / 20% convertido em TOKENS" e "cartão 5-10 dias OU carteira"; também a linha 399.
  (Li o repo; não comparei com o v28 do ar.)
- Base de conhecimento do robô (`support_knowledge_chunks`): `.claude/.ai/business_rules.md` §28
  ("80% saldo livre + 20% tokens") e `mapa-de-fluxos-cliente` ("Na carteira, imediato (80% saldo +
  20% pontos)"). E a skill `WALLET_INFO` (`support_skills`) com "[VERIFICAR] wallet promocional 80/20".
- Funções do banco: nenhuma notificação com 80/20 (SELECT ao `pg_proc`).

## Outros erros encontrados pelo caminho (reportados, não corrigidos)

1. Painel admin: `lib/screens/admin/admin_cancellation_requests_screen.dart:44` aprova cancelamentos
   com `wallet` por defeito → o `execute-cancellation` manda para o saldo dinheiro pago por
   cartão/MB Way se o admin não mudar. Deve vir `stripe` por defeito (agente `admin`).
2. `consume_tokens` não filtra o papel: no checkout de cliente gasta também tokens de estafeta.
3. A app gasta o número de tokens que pediu, mesmo quando o `create_order` cortou o desconto
   (perde tokens). Resolve-se com o passo 1 da proposta 03.
4. `auto-refund-order` grava `refund_amount`; se `stripe_charge_cents` estiver a 0 o gatilho
   `_enforce_refund_cap` recusa e o pedido fica em `processing` (8 de 9 pedidos pagos dos últimos
   30 dias já têm o valor; o risco é pequeno, mas existe).
5. `client-cancel-order` v29: se a Stripe devolve e só a carteira falha, fica `failed` com o valor
   todo → o Reprocessar podia mexer na Stripe outra vez. Corrigido na proposta 02 (`needs_review`).

## PARA O DANILO

1. Depois da recolha (taxa = 100%), os tokens gastos também voltam? Proposto: sim (é o que a regra diz).
2. Tokens de estafeta gastos no checkout de cliente: manter como hoje (proposto) ou passar a só
   gastar tokens de cliente?

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
