# Revisão N9 — 6 Edge Functions: o ramo é igual ao que está no ar? (22/10/2026)

Revisor de contexto limpo. Só li. Nada publicado, nada commitado, nada empurrado.
Ramo `chave-n9-22-10` = `origin/autonomous-night-2026-04-29` (4e6030c1) + 13f0da34 + 6043b4d0.

**Método:** `get_edge_function` (MCP Supabase, projeto ojykpzwqrtusfeakzrna) → copiei o `index.ts` do ar
para ficheiro local → md5 depois de normalizar CRLF→LF, contra o ficheiro do ramo
(o blob no git é LF, a árvore de trabalho é CRLF). As 6 funções têm `verify_jwt: true` no ar.

## 1 e 2. Função a função

| Função | Versão no ar (UTC) | md5 ar | md5 ramo | Resultado |
|---|---|---|---|---|
| auto-refund-order | v3, 16/10 10:44 | 7a460892d4c2b869a5137edc830ea953 | igual | **IGUAL** |
| notify-service-provider | v7, 16/10 10:44 | 0398472353bf4fae96d406b03ffaa048 | igual | **IGUAL** |
| weekly-closeout-digest | v8, 16/10 11:12 | 21c59d6583e9e9a4699cf6dfd7388884 | igual | **IGUAL** |
| notify-cleaner (confirmação) | v11, 21/10 20:00 | 34e37618e6a52abc90d531cbeb13bf36 | igual | **IGUAL** |
| order-edit-settle | v2, 16/10 11:15 | 31d63ac89f23ea8fd26a7785cf9f1e21 | b65ed6a0b81dd2325257188ce0df3317 | **DIFERENTE só em 2 comentários** |
| monthly-partner-statement | v3, 16/10 10:51 | 5cb4894771a8112b397961918442c9d8 | d9c87e69dfac14d2296fc5aaffc8a878 | **DIFERENTE só em 1 comentário** |
| robot-b | v16, 16/10 13:59 | — | ecaac2e777a9b09b0924616440992217 | **NÃO VERIFICADO por md5** (ver abaixo) |

**order-edit-settle e monthly-partner-statement:** o código é o mesmo. Diferem 3 linhas de comentário
decorativo (`// ── título ───…`): order-edit-settle linhas 133 e 250, monthly-partner-statement linha 190.
No ar a fila de traços `─` é mais curta (32/31/… contra 37/36/… no ramo). Se eu apagar o número de traços
dos dois lados, os md5 coincidem. Aviso honesto: copiei a fila de traços à mão, por isso o encurtamento
pode ser erro meu; seja como for é só comentário, sem efeito. O que o commit 6043b4d0 acrescenta
(`whoCalls` → `chamadaDoServidor`) está no ar tal e qual.

**robot-b — não consegui o md5.** A cópia local completa foi recusada pela `bora-tranca` com
"segredo no conteúdo novo: chave anónima com valor em texto claro". É falso positivo: a linha 33 do
ficheiro só lê a variável de ambiente (`Deno.env.get`), não tem segredo, e o ramo tem a mesma linha.
Não contornei a tranca (cortar a linha ou reescrevê-la seria contorná-la). O que tenho em vez de md5:
- os 3 trechos novos (import, comentário + `chaveNovaOk`, condição `jwtRole === 'service_role' || chaveNovaOk`) estão no ar;
- li o ficheiro do ramo (752 linhas) contra o texto do ar: não encontrei nenhuma diferença;
- no git, o blob do ramo (e500d987) = a versão do commit 14fb9994 + exatamente esses 3 trechos (4 linhas novas, 1 apagada);
- o ar tem fins de linha CRLF, ou seja, foi publicado a partir do ficheiro da árvore de trabalho;
- **mas** a versão do ar é de 16/10 13:59 UTC, 2h43 depois do último commit (11:16 UTC). Não há no git
  nenhuma versão posterior de robot-b, mas isto não exclui uma alteração não commitada na altura.
  É por isso que não dou robot-b como verificado.
- Para fechar: Danilo corrigir o falso positivo da tranca (ou autorizar) e repetir; ou baixar o robot-b
  do ar com a CLI da Supabase e comparar o md5.

**Ficheiros partilhados** (`_shared/chaves.ts`, `_shared/keys.ts`): o código sem comentários é idêntico ao do
ar. O repo tem comentários de documentação que as cópias no ar não têm. O ramo já tem
`exigirServidorOuAdmin` (auditoria N4), que o notify-cleaner de hoje usa.

## 3. O que viaja no push

```
6043b4d0 fix(order-edit-settle): whoCalls aceita a chave secreta nova ...
13f0da34 feat(seguranca): seis Edge Functions aceitam a chave secreta nova ...
 6 files changed, 30 insertions(+), 10 deletions(-)
 auto-refund-order, monthly-partner-statement, notify-service-provider,
 order-edit-settle, robot-b, weekly-closeout-digest  (só supabase/functions/*/index.ts)
```
- Só estes 6 ficheiros. Árvore limpa antes deste relatório. Nenhum padrão de segredo nas linhas
  adicionadas (procurei sb_secret_, sb_publishable_, eyJ…, sk_live/sk_test, whsec_, AIza…, chave privada).
- O CI **não** publica Edge Functions: nenhum workflow chama `supabase functions deploy`, a CLI ou a API de gestão.

**ATENÇÃO — o push NÃO é inofensivo.** `build_android.yml` e `build_web_deploy.yml` disparam em push para
`autonomous-night-2026-04-29` e o `paths-ignore` só cobre `**.md`, `.claude/**`, `docs/**` e dois ficheiros do
Em Dia. `supabase/functions/**` não está lá. Resultado provável: autoteste → build → **sobe o versionCode e
publica no Google Play (alpha)** + deploy do site web, tudo sem a app ter mudado. O iOS não dispara (só
`lib/`, `ios/`, `pubspec`). Para evitar: pôr a marca de saltar o CI no commit de cima (a memória
"skip-ci-no-commit-de-cima" confirma que salta o push inteiro; aqui os dois commits só têm Edge
Functions, por isso não se perde nenhum build de app) ou acrescentar `supabase/functions/**` ao
`paths-ignore`. Decisão do Danilo.
Nota menor: a mensagem do 13f0da34 ainda fala de notify-cleaner com `exigirCallerOk`, que já não está neste
diff (ficou a versão N4 de hoje). Convém emendar a mensagem antes do push.

## 4. Dinheiro

Nenhuma lógica de dinheiro mudou. As 30 linhas novas/alteradas são só o portão de quem chama:
`chamadaDoServidor(req)` ao lado da verificação antiga (JWT com `role=service_role`). Stripe, reembolsos,
valores, comissões e RPC ficam iguais. O ramo mais perto de dinheiro é auto-refund-order e order-edit-settle,
e em ambos a única linha tocada é a condição de entrada.

## Veredicto

VEREDICTO: SIM SÓ PARA auto-refund-order, notify-service-provider, weekly-closeout-digest, order-edit-settle e monthly-partner-statement (código igual ao ar; 3 comentários com número de traços diferente). robot-b NÃO VERIFICADO por md5 (tranca recusou a cópia) — lido igual, mas sem prova de máquina. E o push dispara Android + Play + web: decidir a marca de saltar o CI antes de empurrar.
