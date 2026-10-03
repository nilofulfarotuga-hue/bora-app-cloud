---
id: licao-rpc-composite-null-row
tipo: licao
origem: [tvde_active_roundtrip_credit · tvde_store.activeRoundtripCredit · mega-fix 2026-07-18 Parte 9]
ultima_confirmacao: 2026-07-18
zona: verde
confianca: verificado
---

# Lição — RPC `RETURNS <tabela>` (tipo composto) devolve uma row de NULLs quando vazia, não NULL

**Problema.** O app TVDE mostrava o banner fantasma "Tens uma volta garantida" mesmo quando o
utilizador não tinha nenhum vale de volta ativo — a tabela do vale aparecia vazia por baixo do
banner.

**Causa real.** A RPC `tvde_active_roundtrip_credit()` estava declarada `RETURNS
tvde_roundtrip_credits` (um tipo composto = uma linha da tabela). Em PL/pgSQL, quando o `SELECT
... INTO` interno não encontra nada, a função **não** devolve `NULL` — devolve uma **linha
inteira preenchida com NULLs** (id NULL, valid_until NULL, …). No lado Dart,
`res == null` é `false` (veio um Map, não null), então o código concluía "existe vale" e
desenhava o banner, apesar de todos os campos serem NULL.

**Regra generalizável.**
- No servidor: para "0 ou 1 resultado", preferir `RETURNS SETOF <tabela>` (devolve 0 linhas
  quando vazio, que o cliente vê como lista vazia) OU `RETURN NULL` explícito quando o `SELECT
  INTO` não encontra (`IF NOT FOUND THEN RETURN NULL; END IF;`).
- No cliente (defesa dupla): nunca confiar só em `res != null`. Validar sempre um campo-chave
  não-nulável: `if (res == null || res['id'] == null) return null;`.

Uma função que "RETURNS uma tabela" nunca devolve nada mais vazio que uma linha de NULLs —
o vazio verdadeiro tem de ser `SETOF` (0 linhas) ou `NULL` explícito. Ver [[licao-dual-owner-column]].
