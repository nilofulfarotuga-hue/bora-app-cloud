# Prova local (PGlite) das propostas 01 e 02 — 10/11/2026

Postgres real em WASM (PGlite 0.2.17) com as COLUNAS reais e as LINHAS reais de out/nov 2026 exportadas só por leitura (`exportar_para_prova.mjs`), as funções de apoio reais (`_fecho_pedidos`, `_fecho_limites`, …) e as versões EM VIGOR de `admin_monthly_closeout`, `fecho_mensal_prestadores` e `driver_monthly_invoice_summary` (lidas com `pg_get_functiondef`). Primeiro prova-se que a base local reproduz o ar (outubro 159,17; novembro 109,00); depois aplica-se a proposta 01 inteira, verifica-se, e testa-se a 02 numa cópia das duas funções da Stripe.

Correr: `bun prova_pglite.mjs <pasta com node_modules/@electric-sql/pglite, dump.json e fn/*.sql>`

Resultado (saída literal, 10/11/2026):

```
OK    base local = ar no mês 10 (versão em vigor): total 159.17 / ar 159.17
OK    base local = ar no mês 11 (versão em vigor): total 109 / ar 109
OK    proposta 01 aplicada sem erro de sintaxe
OK    backup das 3 funções antigas guardado (3)
OK    outubro: soma das rubricas 129.56 = receita própria 129.56
OK    outubro: entregas e mercados 129,56 (129.56)
OK    outubro: tokens descontados -3,29 (-3.29)
OK    outubro: margem nos produtos 31,42 + 3,59 = 35,01 (31.42 + 3.59)
OK    outubro: ajustes 0 (0)
OK    outubro: total da Bora 159,17 (159.17)
OK    outubro: UMA linha Consumidor final de 159,17 (1 linha(s), 159.17)
OK    outubro: texto sem TVDE, sem "uma por loja parceira com a comissão", com "nunca às lojas"
OK    outubro: entidade Danilo em nome individual (322151171)
OK    novembro: entidade a sociedade 519686233 (519686233)
OK    novembro: soma das rubricas 109.00 = receita própria 109
OK    prestadores: IVA e retenção "confirmados pelo contabilista"
OK    lojas parceiras: "faturada aos clientes, nunca à loja"
OK    extras outubro: tokens descontados 3,29 (3.29)
OK    extras outubro: BEMVINDO 7 usos, 35 €, 0 com pedido ({"u":7,"v":35,"p":0,"usados":1})
OK    extras outubro: taxas Stripe da parte Bora 5,95 (5.95, extrato_stripe)
OK    BEMVINDO: todos os usos sem pedido ligam aos tokens creditados (38/38)
OK    DAC7: há loja parceira ativa sem NIF (["nome legal","NIF","IBAN"])
OK    DAC7: há estafeta aprovado sem IBAN e sem comprovativo (["data de nascimento","IBAN","comprovativo de atividade"])
OK    DAC7: nenhum IBAN em claro na resposta
OK    texto ao contabilista: total 159,17 €
OK    texto ao contabilista: leva a nota do Danilo
OK    texto ao contabilista: TVDE fora (só "sem TVDE" no título da Stripe)
OK    texto de novembro: entidade é a sociedade
OK    reenviar: chama a Edge (net.http_post simulado)
OK    conferência 10: rubricas batem e pago−mercadoria−estafetas = sobra
OK    conferência 11: rubricas batem e pago−mercadoria−estafetas = sobra
OK    proposta 02: guarda trocada por session_user
OK    proposta 02: correr outra vez pára sem mudar nada (âncora já não existe)
OK    guarda: utilizador comum NÃO lê admin_prestadores_dados_fiscais()
OK    guarda: utilizador comum NÃO lê fecho_mensal_prestadores(2026,10)
OK    guarda: utilizador comum NÃO lê admin_monthly_closeout(2026,10)
OK    guarda: utilizador comum NÃO lê fecho_contabilista_extras(2026,10)
OK    guarda: utilizador comum NÃO lê admin_fecho_contabilista(2026,10)
OK    guarda: utilizador comum NÃO lê admin_fecho_conferencia(2026,10)
OK    guarda: _dados_fiscais_linhas() fechada a utilizadores
OK    app: esse estafeta vê só o que lhe falta ([{"falta":["data de nascimento","IBAN","comprovativo de atividade"],"papel":"estafeta"}])
OK    proposta 02: utilizador comum já NÃO lê o resumo da Stripe
TUDO CERTO
```

Teste D3 (`supabase/tests/fecho_mensal_consistencia_test.sql`) corrido na produção a 10/11: `fecho_mensal_consistencia_test: OK` (setembro a novembro). Num mês estragado de propósito (PGlite) falha com `FECHO INCONSISTENTE | 2026-10: soma das rubricas 9 ≠ receita própria 9.5`.

Email do contabilista desenhado com as funções da Edge v2 e os dados de outubro desta prova: 12/12 verificações (sem TVDE, sem "fatura esta comissão à loja", sem "recibo verde ao adquirente", frase do IVA/retenção, tokens -3,29, total 159,17, Consumidor final, BEMVINDO, taxas Stripe 5,95, prejuízo, dados em falta).
