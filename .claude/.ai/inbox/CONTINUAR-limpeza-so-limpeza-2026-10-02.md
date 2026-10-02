# CONTINUAR — limpeza-so-limpeza-2026-10-02

Relatório: `.claude/.ai/reports/OPUS-limpeza-so-limpeza-2026-10-02.md`.
O código está feito, publicado na web e provado. Ficou por fechar o que depende da base de dados,
que caiu às 14:05 UTC de 02/10 (causa: a app Android a ler o catálogo inteiro ao arrancar).

## Condição para começar

`GET https://ojykpzwqrtusfeakzrna.supabase.co/rest/v1/restaurants?select=id&limit=1` devolve 200 em
menos de 3 s, quatro vezes seguidas (guião: `.claude/.ai/provas/limpeza-so-limpeza-2026-10-02/`).

## Passos, por ordem

1. **Repetir o build Android** do commit `0338e887`: `POST /repos/nilofulfarotuga-hue/bora-app-cloud/actions/runs/37014873730/rerun-failed-jobs`
   (token pelo `git credential fill`). Feito = job "Autoteste 3 perfis" success e commit
   `ci: bump versionCode to N` no ramo.
2. **Digest** em `public.claude_ai_memoria`, página `digest-2026-10-02-limpeza-so-limpeza`,
   `origem='claude-code'` (texto: resumo do relatório, 10–20 linhas).
3. **`e2e_log`**: linha `bF-ci-android-2` (falhou, 504 do Supabase), `bF-incidente-api` e `fim`,
   fluxo `limpeza-so-limpeza-2026-10-02`.
4. Confirmar por SELECT que as contas de prova continuam neutralizadas:
   `746b98a0-554c-4e86-a63a-b93acde6b186` (limpeza suspended, estafeta rejected) e
   `5a5d2b38-9411-4f08-9b53-02ee0cdc8596` (limpeza rejected), e que as reservas `984c85fc…` e
   `ea3c8e18…` estão `cancelled_client`.

## Não fazer

- Não recusar a ficha de estafeta da Mayra (`9a8a5657…`) antes de ela ter a app nova: a versão
  antiga volta a bloqueá-la.
- Não usar `demo@bora.app` em provas manuais enquanto o autoteste do CI corre.
