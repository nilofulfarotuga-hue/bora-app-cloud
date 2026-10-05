# Bloco C — segurança (Claude Code no PC, 05/10/2026)

## C.1 — lista branca e fecho a quem não tem sessão (no ar, migração 20261005092316)
- Levantamento (só leitura) de todas as chamadas em `lib/`, `web/`, sites, robôs do PC e cópias da VPS:
  213 funções SECURITY DEFINER abertas a anon.
- **Ficam abertas (44):** 28 da lista branca (is_admin das políticas RLS; 20 robôs com `p_chave`/segredo;
  4 páginas públicas: viagem, fiscalização, verificar, /baixar; 3 da app antes do login: get_setting,
  log_client_crash, driver_heartbeat_by_id) + 16 em dúvida (catálogo/orçamentos que a app pode pedir antes da
  sessão de convidado; 3 estatísticas que provavelmente são da VPS).
- **Fechadas a anon: 169** (40 são de gatilho). Quem tem sessão e o service_role mantêm o acesso.
  Lista guardada em `bkp_anon_execute_20261005` (para voltar atrás: GRANT a anon linha a linha).
- Só o servidor: `notify_admin_urgent_push` (qualquer pessoa mandava push/Telegram ao Danilo),
  `tvde_reservation_push` (qualquer pessoa mandava push a qualquer motorista) e `aceita_papel` — fechadas
  também a quem tem sessão.
- `admin_estado_imagens_catalogo` e `admin_fontes_de_preco` não verificavam quem chama — agora `is_admin()`.

## C.2 — funções novas nascem fechadas (20261005092316 + 20261005092401)
- Privilégio por defeito tirado (o "in schema public" não chegava: o Postgres dá EXECUTE a PUBLIC globalmente).
- Prova (transacção desfeita): função nova → anon=f, authenticated=t, service_role=t.
- Regra curta no `CLAUDE.md` (Key conventions).

## C.3 — provas
- **Sem sessão, pela internet, com a chave pública da app (antes e depois):** is_admin, get_setting,
  tvde_ver_partilha, tvde_fiscal_consulta, verificar_ficha_publica, tvde_calculate_fare, tvde_plan_price_cents,
  carwash_quote, search_businesses, tvde_conformidade_config, tvde_operador_plataforma, prospects_ler e leitura de
  `restaurants` e `provider_services` (políticas com is_admin) — **todas iguais antes e depois (200/400 de
  validação, nenhum erro de permissão).** Fechadas: aceita_papel, admin_fontes_de_preco, my_roles → 401/42501.
  Saídas: scratchpad `prova_anon_antes.txt` / `prova_anon_depois.txt`.
- **Com sessão:** as 20 RPC mais usadas pela app continuam com EXECUTE para authenticated (lido no banco);
  chamada real como cliente demo (transacção desfeita): my_roles, get_setting e is_partner_open respondem;
  aceita_papel recusa.

## Fica por fazer
- Fechar as 16 em dúvida depois de um arranque a frio sem sessão (Android + web) e de ver a VPS.
- `driver_heartbeat_by_id` continua aberto (qualquer pessoa pode dar "sinal" por um estafeta ligado — risco do caso
  Ney) até todas as apps de estafeta terem o segredo; `cancel_orphan_reservation` só se defende pelo código do pagamento.
- O privilégio por defeito de `supabase_admin` no schema public ainda dá EXECUTE a anon (não é nosso; só afecta
  funções criadas por esse papel).
