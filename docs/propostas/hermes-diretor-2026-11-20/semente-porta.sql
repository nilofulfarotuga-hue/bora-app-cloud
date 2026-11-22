-- Missão hermes-diretor-2026-11-20, B4 — A LISTA DO DINHEIRO da porta do Hermes (um DADO, não estrutura).
-- Para a Claude.ai rever e aplicar DEPOIS das migrações 20261122190000 e 20261122190200.
-- É por estes padrões que a porta decide o que é valor (pede o "autorizo" do Danilo), o que é segredo
-- (não abre) e o que é controlo (só o Danilo ou a Claude.ai). Sem esta linha, a porta fica toda trancada.
-- Medido no esquema a 22/11/2026: 617 tabelas e 2012 funções em public; com estes padrões ficam como valor
-- 108 tabelas pelo nome, 306 funções pelo nome e mais 284 por escreverem em tabelas de valor.
-- Depois de aplicar: select public.hermes_porta_reclassificar(); select public.hermes_porta_leitor_sincronizar();
-- e conferir no painel (/admin/autorizacoes mostra os pedidos; a classificação está em hermes_porta_classes).

insert into public.platform_settings (key, category, description, is_secret, value)
values ('hermes_porta_dinheiro', 'hermes',
        'Lista do que a porta do Hermes trata como dinheiro (pede o autorizo do Danilo), segredo (não abre) e controlo. Só o Danilo ou a Claude.ai mudam.',
        false,
$json${
  "padrao_tabelas": "(wallet|ledger|bora_token|token_transaction|payout|refund|reembols|payment|pagament|stripe|mbway|invoice|fatura|recibo|receipt|promo|coupon|cupo|voucher|(^|_)tips?(_|$)|gorjeta|balance|saldo|settlement|acerto|commission|comiss|pricing|(^|_)prices?(_|$)|preco|(^|_)fees?(_|$)|credit|debit|divida|debt|cashback|deposit|charge|cobranc|earning|ganho|financ|fiscal|check_?in|premio)",
  "padrao_funcoes": "(wallet|ledger|token|payout|refund|reembols|payment|pagament|pagar|stripe|mbway|invoice|fatura|recibo|promo|coupon|cupo|voucher|(^|_)tip(s|_|$)|gorjeta|balance|saldo|settle|acerto|commission|comiss|pric|preco|(^|_)fee(s|_|$)|taxa|credit|debit|divida|debt|cashback|deposit|charge|cobr|earning|ganho|financ|split|discount|descont|bonus|premio|finalize|checkout|purchase|compra|check_?in)",
  "padrao_colunas": "(price|preco|commission|comiss|(^|_)fee(s|_|$)|markup|discount|descont|earn|ganho|amount|_cents$|saldo|balance|payout|refund|(^|_)tip(_|$)|bonus|premio|credit|debt|deposit|(^|_)valor(_|$)|token)",
  "padrao_chaves": "(stripe|pric|commission|comiss|(^|_)fee(s|_|$)|taxa|token|wallet|markup|split|payout|refund|(^|_)tip(s|_|$)|preco|descont|discount|bonus|ganho|earn|premio|cashback|deposit|credito|saldo|min_order|delivery_|small_order|bag_)",
  "padrao_segredo_tabelas": "(push_tokens$|_secrets?$|^secrets?_|api_keys?|credentials|fiscalizacao_tokens)",
  "padrao_segredo_colunas": "^(fcm_token|push_token|access_token|refresh_token|api_key|apikey|secret|client_secret|password|senha|private_key|otp|pin|pin_code|delivery_pin|cvv|card_number|iban|nif)$|_secret$|_password$",
  "tabelas_controlo": ["claude_ai_memoria", "e2e_log", "admin_users", "user_roles"],
  "tabelas_operacao": ["orders", "drivers", "tvde_rides", "appointments"],
  "funcoes_operacao": ["ops_reassign_order", "ops_release_order_driver"],
  "tabelas_livres": [],
  "funcoes_livres": []
}$json$::jsonb)
on conflict (key) do update set value = excluded.value, description = excluded.description, category = excluded.category, updated_at = now();
