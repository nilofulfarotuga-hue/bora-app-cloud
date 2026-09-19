---
data: 2026-07-15
agente: executor autónomo (Sonnet)
tema: cadastro de parceiro — mensagem de erro específica do backend
---

## Problema

No cadastro de parceiro, quando `register-partner` (Edge Function) devolvia
`400` com uma mensagem específica no corpo (`{ "error": "NIF formato
inválido (9 dígitos)" }`, `"IBAN formato inválido..."`, `"email
obrigatório"`, etc.), a app Flutter ignorava esse texto e mostrava sempre o
mesmo erro genérico "erro de ligação ao registar o estabelecimento, contacta
o suporte" — mesmo não sendo um problema de rede.

## Causa

`AuthStore._submitRestaurantEdgeFunction`
(`lib/auth/auth_store.dart:1272-1332`) tratava qualquer `response.status !=
201` com a mesma frase fixa, sem ler `response.data['error']`.

## Correção

`lib/auth/auth_store.dart:1305-1322` — quando `status != 201`, extrai
`response.data['error']` (o backend já devolve sempre esse campo, confirmado
em `supabase/functions/register-partner/index.ts`) e usa essa mensagem
específica. Só cai no texto genérico se o campo vier vazio/ausente.

O `catch` (falha de rede/timeout, sem resposta do servidor) continua a
mostrar o texto genérico — não foi alterado, é o comportamento correto para
esse caso.

## Ficheiros tocados

- `lib/auth/auth_store.dart`

## Validação

`flutter analyze` não disponível neste sandbox (binário `flutter` ausente).
Revisão manual do diff confirma sintaxe Dart válida e uso seguro de
`?.toString()` (evita `TypeError` se `error` não vier como String).

---

Erro específico do backend agora aparece na app.
