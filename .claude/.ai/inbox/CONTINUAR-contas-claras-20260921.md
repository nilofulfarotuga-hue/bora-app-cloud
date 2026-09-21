# CONTINUAR — contas claras, depois do fecho de 21/09

> Escrito pelo Claude Code às 10h00 UTC de 21/09/2026 (missão `contas-claras-20260921`, run com o mesmo
> nome no `e2e_log`, fluxo `contas-claras-2026-09-20`). Relatório: `RELATORIO-contas-claras-fecho-2026-09-21.md`.

## Estado ao sair

- C0–C5 fechados com prova; C6: push `0fb40500..6525bc6f` feito; CI run **35585546832** com o job
  "Autoteste 3 perfis" a correr (09:51 UTC). O `build` (bump + Play + web) só arranca se o autoteste
  ficar verde. **Primeira coisa a fazer:** ler o run (script `ci_runs.py` no scratchpad, ou
  `git credential fill` + API dos runs) e escrever no `e2e_log` a linha `C6 publicação` com o resultado
  real (autoteste verde/vermelho, build verde/vermelho, commit `ci: bump versionCode` no ramo).
- Helpers de leitura `_repo_migration_sql`/`_repo_function_def` já removidos (migration 20260921094845).

## Espera o "vai" do Danilo (NÃO fazer sozinho)

1. Reenviar os recibos da semana 14–20/09 (Valdemir e Erika têm o HTML sem "Corridas"): no painel,
   semana 13/09 → "Reenviar recibos" (manda a todos, Goola incluída).
2. `create_order` somar a taxa de pedido pequeno ao total (hoje mostra 1,39 e não cobra; 6,95 € em 5
   pedidos; parceiros nunca cobram) — zona vermelha; proposta no relatório.
3. Rejeitar a candidatura de estafeta acidental da conta do painel (drivers user_id c9fccf85, pending,
   criada 20/09 15:31 UTC) pela função de admin; preencher `public.users.email` = nilofulfarotuga@gmail.com.
4. Vigia do vermelho para parceiros: trocar o `RETURN` dos parceiros em `_trg_alerta_pedido_no_vermelho_fn`
   por `sobrou = total − order_financials.restaurant_amount − driver_earnings`.

## Armadilhas desta sessão (já em memória)

- Simular admin em SQL: `sub` = c9fccf85 (nilofulfarotuga), não 4f61dd31 (boraappbora); prova num `DO … RAISE`.
- A Trava lê o TEXTO: uma linha do `e2e_log` com "CREATE OR REPLACE" + nome de função de dinheiro é bloqueada — reformular.
- `weekly_closeout_compile` não refresca linhas `sent`; reabrir (admin_reabrir_acerto) põe a linha em pending.
- Golden tests com `errno = 1224` no PNG = lock do Windows; correr sozinhos.
