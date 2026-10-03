# Provas do Bloco 5 — jev-decisor-2026-09-23

Tudo lido por SELECT na base de produção (`ojykpzwqrtusfeakzrna`) a 23/09/2026, entre as 14:47 e as 15:00 UTC.

## O que correu

Vinte chamadas reais à Edge Function `decidir` (v3), com estados reais tirados da base e
anonimizados (telefones e emails trocados por `[telefone]` e `[email]` antes de saírem):

- 10 sugestões do Robot B (5 aplicadas, 5 rejeitadas pelo Danilo) — pergunta sim/não
  "vale a pena abrir?". Linhas `decisoes.usado_por = 'prova-b5-robotb'`.
- 4 marcações de serviço com desfecho conhecido (2 compareceu, 2 cancelou) — nota de risco
  de falta de 0 a 4. Linhas `usado_por = 'prova-b5-noshow'`.
- 6 primeiras mensagens de conversas de suporte (4 foram a humano, 2 não) — sim/não
  "passar a humano?". Linhas `usado_por = 'prova-b5-suporte'`.

`resultado_real` de cada linha foi escrito a partir do que aconteceu de verdade.

## Resultado

- Jev: 0 chamadas — não há chave (`vault.secrets` sem `typesafe_api_key`). Todas registam
  `erro = 'jev_sem_chave | ...'`.
- Gemini: 1 resposta em 20. `gemini-3.5-flash-lite`, 19 637 ms, 1 433 tokens de entrada,
  respondeu "não" com 14% de confiança a uma sugestão que o Danilo aplicou — errou.
- As outras 19: `motor = 'nenhum'`. Erros literais do Google: `gemini-3.5-flash-lite: Signal
  timed out` (20 s), `gemini-3.1-flash-lite: gemini http 503 ... high demand` e depois `429 You
  exceeded your current quota`, `gemini-3-flash-preview: 429 You exceeded your current quota`.
- Diagnóstico por modelo (linhas `prova-b5-modelo`): `gemini-2.5-flash-lite` 404 (já não
  existe para esta chave); `gemini-3.5-flash` 429; `gemini-flash-lite-latest` sem resposta em 20 s.
- O robot-b, com a mesma chave, levou 503 em 6 das 8 execuções de 08h a 14h UTC (tabela `robot_runs`).

Comparação Jev contra Gemini lado a lado: **não foi possível** — falta a chave do Jev e a
chave Gemini do Supabase está sem quota. O SQL abaixo repete tudo quando houver chave.

## Como repetir (quando existir `typesafe_api_key` no Vault)

1. Correr `repetir_b5.sql` (nesta pasta),
   com :ronda = 'prova-b5r2',
   primeiro com `"motor":"jev"` e depois com `"motor":"gemini"`.
2. Ler lado a lado:

```sql
select j.contexto_id, j.usado_por, j.resposta as jev, g.resposta as gemini, j.resultado_real,
       j.latencia_ms as ms_jev, g.latencia_ms as ms_gemini, j.custo_usd
  from decisoes j join decisoes g on g.contexto_id = j.contexto_id and g.motor = 'gemini'
 where j.motor = 'jev' and j.usado_por like 'prova-b5r2-%';
```
