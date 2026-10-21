# PROPOSTA (não aplicada) — `register-partner` confia no JWT sem o verificar

> Auditoria de segurança 21/10/2026 (missão geral-noite-21-10, agente N4). Só relatório — não toca
> dinheiro mas mexe num fluxo de onboarding com `service_role`; fica para o Danilo decidir.
> A prova ao vivo foi **bloqueada pelo classificador** ao tentar correr o ataque; a análise é estática.

## O que é

A Edge `register-partner` (verify_jwt=false) tira o `user_id` assim:

```ts
const token = authHeader.substring(7);
const parts = token.split(".");
if (parts.length !== 3) { ...401... }
const payload = JSON.parse(atob(parts[1]...));   // só descodifica
const userId = payload.sub;                       // NÃO valida a assinatura
```

Com `verify_jwt=false`, o portão da plataforma não valida nada, e a função também não: aceita o
`sub` de **qualquer** JWT com 3 partes, mesmo um forjado à mão. Depois escreve em `restaurants` /
`service_providers` com a chave de serviço, pondo `user_id`/`user_` = esse `sub`.

## O que um atacante consegue

- Criar uma candidatura de parceiro (`approval_status='pending'`) **em nome de outro `user_id`** à
  escolha, ou de um `sub` inventado. Não aprova a loja (continua a precisar do admin), mas suja a
  tabela e pode sequestrar o estado de onboarding de uma conta real (a app assume "no máximo 1
  candidatura por user_id").
- É o mesmo padrão da cicatriz `motorista_ficha` / Ney: nunca confiar no payload do JWT sem o Auth
  confirmar a assinatura.

A app legítima (`auth_store.dart` → `_supabase.functions.invoke('register-partner')`) manda o JWT
real da sessão, por isso a correção não a parte.

## Correção proposta (não aplicada)

Trocar a descodificação crua pela confirmação no Auth, com o helper que já existe
(`_shared/chaves.ts` → `utilizadorDoPedido(req)`), e usar o `id` que o Auth devolve:

```ts
import { utilizadorDoPedido } from "../_shared/chaves.ts";
const u = await utilizadorDoPedido(req);           // confirma a assinatura no /auth/v1/user
if (!u) return new Response(JSON.stringify({ error: "sessão inválida" }), { status: 401, ... });
const userId = u.id;
```

Mantém `verify_jwt=false` (o portão aceitaria a chave nova mas não valida sessão de utilizador; a
validação passa a ser a confirmação no Auth) e o resto do corpo da função fica igual.

Deploy: `deploy_edge_function` com os ficheiros inteiros (`index.ts` + `_shared/keys.ts` +
`_shared/chaves.ts`), `verify_jwt=false` (o atual).

## Porque fica como proposta

É um fluxo de onboarding de parceiro, não é dinheiro, mas toca `service_role` e um caminho de
registo em produção; e a prova com defeito plantado foi recusada pelo classificador antes de eu a
poder correr. Entrega-se pronta para o Danilo mandar aplicar.
