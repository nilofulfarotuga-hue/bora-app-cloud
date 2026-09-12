---
id: admin-acerto-de-caixa
tipo: relatorio
data: 2026-08-03
zona: verde (só UI, painel admin)
---

# RESULTADO — bloco "Acerto de Caixa" no detalhe do pedido (admin)

## Ficheiro alterado
- `lib/screens/admin/admin_order_detail_screen.dart` (+155 linhas, só adições)

## O que ficou visível
Na tab **Pagamento** do ecrã de detalhe de encomenda do painel admin, depois do
card "Reembolso", surge um novo card **"Acerto de Caixa"** (widget
`_CashBreakdownCard`) que:

- Chama `Supabase.instance.client.rpc('admin_order_cash_breakdown', params: {'p_order_id': orderId})`.
- Mostra em PT-BR, com o design system existente (Card + Radii.lg, sem
  componente novo): Cliente pagou, Produtos, Entrega, Taxa de serviço, Sacos,
  Ganho do entregador, Valor do talão da loja, Saldo do entregador, Direção
  ("Bora deve ao entregador" / "Entregador deve à Bora" / "Quitado"), Lucro
  da Bora (vermelho quando negativo), Diferença de preço do catálogo (só
  aparece se ≠ 0, vermelho quando positiva).
- Só é renderizado quando `payment_method == 'cash'` OU `talao_loja > 0`.
- Em erro de permissão do RPC: se o pedido é cash, mostra só uma mensagem
  discreta ("Acerto de caixa indisponível (sem permissão)."); se não é cash,
  o bloco fica oculto (não há como saber o talão sem a resposta do RPC).
- Enquanto carrega, não ocupa espaço (SizedBox.shrink) — sem spinner extra
  na tab.

## Validação
- `flutter analyze lib/screens/admin/admin_order_detail_screen.dart` → 1 issue
  (info `prefer_const_constructors`, **pré-existente**, linha do widget
  `_ActionButton` que já existia antes desta tarefa — confirmado via
  `git diff --stat` mostrando só inserções).
- Não foi tocado nenhum RPC/Edge Function/SQL/pricing/dispatch/tokens/Stripe/
  versionCode — conforme restrição da tarefa.

## Git
- Commit `824a9c9` → rebase sobre `9e04e54` (bump de versionCode concorrente
  de outro executor) → push `b99eac3` em
  `origin/autonomous-night-2026-04-29`.
- Só o ficheiro do admin foi staged/commitado; os restantes ficheiros
  modificados/untracked no working tree (de outras tarefas em curso) não
  foram tocados.
