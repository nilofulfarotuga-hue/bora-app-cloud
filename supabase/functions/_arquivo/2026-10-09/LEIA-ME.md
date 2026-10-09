# Arquivo de Edge Functions — 2026-10-09

- **Data:** 2026-10-09
- **Missão:** fecho-total-2026-10-09
- **Origem:** código lido do AR pelo MCP get_edge_function (o token da CLI está expirado, 401).
- **Projeto Supabase:** ojykpzwqrtusfeakzrna

Isto é só um arquivo. Nada aqui foi publicado, nada foi alterado no servidor, e estas
pastas não são para deploy.

## Como foi gravado

O conteúdo de cada ficheiro foi tirado da resposta crua do MCP e gravado byte a byte,
sem reformatar nem corrigir nada. Dois ficheiros vêm do ar com fim de linha do Windows
(CRLF): `notify-admin-urgent/index.ts` e `notify-washer/index.ts`. Ficaram assim de
propósito, iguais ao que está no ar.

Os nomes que vieram com prefixo (`user_fn_.../source/`, `notify-admin-urgent/`,
`gemini-diagnostic/`) foram reduzidos ao caminho dentro da pasta da função. O
`../_shared/cors.ts` do support-chatbot ficou em `support-chatbot/_shared/cors.ts`.

Conferido duas vezes, por dois scripts diferentes (Node e Python): os 12 ficheiros
gravados são iguais, byte a byte, à resposta do MCP.

## Tabela

| slug | versão no ar | verify_jwt | ficheiros gravados | nº de linhas do index.ts |
|---|---|---|---|---|
| client-assistant | v6 | true | index.ts | 903 |
| notify-cleaner | v9 | true | index.ts | 236 |
| support-chatbot | v27 | true | index.ts, _shared/cors.ts | 948 |
| notify-admin-urgent | v19 | true | index.ts | 480 |
| notify-washer | v6 | true | index.ts | 264 |
| aplicar-gaveta | v3 | true | index.ts | 13 |
| tmp-admin-upload-gallery | v2 | true | index.ts | 4 |
| tmp-connect-link | v3 | true | index.ts | 3 |
| tmp-importar-fotos-parceiro | v5 | true | index.ts | 1 |
| diag-env-names | v2 | true | index.ts | 5 |
| gemini-diagnostic | v7 | false | index.ts | 21 |

As linhas foram contadas com `wc -l`. As versões e o verify_jwt vêm da própria resposta do
MCP e batem com a listagem.

## Procura de segredos escritos à mão

Padrões procurados: sk_live, sk_test, rk_live, sbp_, whsec_, eyJhbGci, AIza, -----BEGIN, bot[0-9]+:.

Nenhum segredo encontrado. Houve 3 resultados, e são todos falsos alarmes: é código que
tira o cabeçalho de uma chave lida do ambiente, não uma chave escrita no código.

- `notify-admin-urgent/index.ts` linha 426: `.replace(/-----BEGIN PRIVATE KEY-----/g, '')`
- `notify-cleaner/index.ts` linha 205: o mesmo
- `notify-washer/index.ts` linha 233: o mesmo

Todas as chaves são lidas com `Deno.env.get(...)` ou pelo Vault.
