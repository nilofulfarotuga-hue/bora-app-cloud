---
id: memoria-claude-ai-reembolsos-b2-ordem
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# reembolsos-b2-ordem

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `reembolsos-b2-ordem`, origem `claude-code`, atualizada em 2026-10-29T15:44:44.375201+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: reembolsos b2 ordem · memoria claude.ai · claude_ai_memoria

# Reembolsos (Bloco 2) — ordem exata de aplicação e provas

Escrito pelo Claude Code a 29/10/2026 (missão final-app-2026-10-29) a pedido do Claude.ai (15:40), porque o
envio do ramo `missao-geral-2026-10-28` ao GitHub foi recusado pela tranca. Autorização do Danilo: 29/10 14:22,
"eu autorizo os 4 de dinheiro" (item 2 = este pacote). Regra do Danilo (28/10 18:24): quem paga com MB Way ou
cartão recebe pelo mesmo meio por defeito; pode escolher 100% em saldo; tokens gastos voltam como tokens; os não
gastos não se devolvem; acabou o 80/20. `wallet_split_free_pct = 1.0` já está no ar.

## As páginas deste pacote (conteúdo literal, byte a byte, md5 provado ao gravar)

- `reembolsos-b2-00-leia-me` — `docs/propostas/missao-geral-2026-10-28/bloco2/LEIA-ME.md` (contexto, regra, repo vs ar).
- `reembolsos-b2-01-shared-cobranca` — `supabase/functions/_shared/cobranca_stripe.ts` v2 (ficheiro inteiro do repo).
- `reembolsos-b2-ef-client-cancel-order` — `bloco2/02_client-cancel-order_index.md`: o `index.ts` v30 inteiro
  (zona vermelha no PC, por isso ficou neste .md e não na pasta da função; a pasta da função no repo ainda tem a
  versão anterior com `secretKey()`). Ficheiros extra: nenhum.
- `reembolsos-b2-ef-cancel-order-with-choice` — `supabase/functions/cancel-order-with-choice/index.ts` v19. Extra: nenhum.
- `reembolsos-b2-ef-execute-cancellation` — `supabase/functions/execute-cancellation/index.ts` v16. Extra: nenhum.
- `reembolsos-b2-ef-admin-cancel-order` — `supabase/functions/admin-cancel-order/index.ts` v15. Extra: nenhum.
- `reembolsos-b2-ef-auto-refund-order` — `supabase/functions/auto-refund-order/index.ts` v4. Extra: nenhum.
- `reembolsos-b2-ef-reprocess-refund-e-refund` — `bloco2/04_reprocess-refund_e_refund.md`: `reprocess-refund` v4
  inteiro e o texto a mudar no `refund` (o `refund` tem um `config.toml` na pasta; não muda).
- `reembolsos-b2-sql-tokens` — `bloco2/03_tokens_gastar_e_devolver.md`: o SQL dos tokens (tabela
  `pedido_tokens_gastos`, `consumir_tokens_do_pedido` + gatilho, ponte no `consume_tokens`,
  `devolver_tokens_do_pedido` + gatilho, `fn_reembolso_cancelado_pelo_sistema` v3, backups `bkp_*_20261028`).

## Ordem (não trocar)

1. Publicar JUNTAS, cada uma com o `_shared/cobranca_stripe.ts` v2 ao lado (em `deploy_edge_function`, o ficheiro
   `_shared/cobranca_stripe.ts` vai no `files` de cada função, com o mesmo caminho relativo que o `import` usa):
   `client-cancel-order` v30, `cancel-order-with-choice` v19, `execute-cancellation` v16, `admin-cancel-order` v15.
   Atenção à chave: o repo usa `secretKey()` de `_shared/keys.ts`; o que está no ar usa
   `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')`. Antes de publicar, `get_edge_function` de cada uma para ver que
   `_shared` já vai no ar hoje (keys.ts ou não) e levar os mesmos ficheiros auxiliares. Armadilha vista hoje no
   `notify-tvde-driver`: o repo estava ATRÁS do ar (uma versão publicada nunca entrou no repo); comparar sempre
   o ar com o repo antes de publicar, e publicar "ar + patch", nunca o repo cego.
2. Publicar `auto-refund-order` v4 e `reprocess-refund` v4 (+ o texto do `refund`).
3. Só depois do passo 1: aplicar o SQL dos tokens (`reembolsos-b2-sql-tokens`) numa só migração (passos 1 e 2
   dos tokens juntos), nome `20261029_reembolsos_tokens_gastar_e_devolver`. Ao contrário, o `_shared` velho
   contaria os tokens e creditava-os como saldo.
4. Na próxima versão da app (já no repo, espera o "publica"): `payment_method_screen.dart` deixa de chamar
   `consume_tokens`; a ponte fica até a versão mínima obrigatória já não chamar.
5. Pôr a migração no repo (`supabase/migrations`, texto igual ao aplicado) — no PC a tranca recusa ficheiros
   com nomes de tokens/carteira; fica para quem aplicar.

## Provas depois de cada passo

- Passo 1: `get_edge_function` das 4 → o `_shared/cobranca_stripe.ts` publicado SEM `usouTokens` e COM
  `Math.min(pedido - stripeCents, pago.walletCents)`; versões 30 / 19 / 16 / 15; `verify_jwt` igual ao que estava.
- Passo 2: `get_edge_function auto-refund-order` com `saldo_cents`; `reprocess-refund` com `vaiStripe`.
- Passo 3: `select to_regclass('public.pedido_tokens_gastos')` não nulo; os 2 gatilhos em `pg_trigger`;
  backups `bkp_*_20261028` com 1 linha cada; a prova em rollback da proposta 03 (pontos 1 a 8) a dar OK.
- Com pedidos de hoje (contagem de tokens = 0) o dinheiro devolvido é igual ao de agora: só mudam os textos e o
  defeito do `refund_method`. Primeiro pedido real com tokens depois do passo 3: `orders.tokens_applied_count > 0`
  e linhas em `pedido_tokens_gastos`; se for cancelado, `devolucao_resultado = 'devolvido'`.
- Registar cada passo no `e2e_log` (fluxo `final-app-2026-10-29`, passos `1.c-reembolsos-passo-1..3`) e a
  proposta `prop-38d65b15`/`prop-d7d3717b` como aplicada no Córtex.

