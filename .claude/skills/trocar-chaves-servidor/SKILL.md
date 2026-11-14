---
name: trocar-chaves-servidor
description: "Usar antes de trocar, criar, desligar ou rodar qualquer chave ou segredo do servidor do Bora (Supabase, cofre, Stripe): protocolo para não partir nada calado."
---

# trocar-chaves-servidor — trocar uma chave sem partir nada calado

> Missão `chaves-varredura-2026-10-31` (autorização do Danilo de 31/10 12:19: "dá uma varredura em
> tudo, para não dar nunca mais esses problemas"). Regra da casa: `docs/SEGURANCA-CHAVES.md` e
> `supabase/functions/_shared/chaves.ts`.

## A cicatriz (porque é que isto existe)

- 16/10: as Edge Functions passaram a receber a chave nova (`sb_secret`, que NÃO é um JWT) na variável
  `SUPABASE_SERVICE_ROLE_KEY`. Funções que liam o `role` de dentro do JWT, ou comparavam
  `token === Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')`, passaram a recusar o próprio servidor.
- 31/10 11:41: `stripe-webhook → finalize-order-from-intent` deu 401 → pagamento sem pedido.
  `notify-tvde-client` deu 401 em 10/10 chamadas (passageiro sem "motorista a caminho"); a app do
  estafeta mandava a chave pública como `Bearer` → 401 no aviso ao cliente; `refund` recusava o painel.
- Nada disto apareceu em lado nenhum durante 15 dias: os erros eram engolidos em `try/catch`.

## A regra única (não inventar outra)

| Quem chama | Como a função confirma |
|---|---|
| Servidor (banco/pg_net, cron, outra Edge, CI, VPS) | `await chamadaDoServidor(req)` — chave secreta nova em `apikey` OU `Bearer` (qualquer nome), ou a legada **confirmada no Auth** |
| Servidor ou admin | `exigirServidorOuAdmin(req, cors)` |
| Servidor ou utilizador com sessão | `exigirServidorOuUtilizador(req, cors)` e depois verificar que o utilizador é dono do que pede |
| Utilizador | `await utilizadorDoPedido(req)` (confirma no Auth; nunca ler `sub`/`role` do JWT à mão) |

- Cliente admin dentro da função: `createClient(url, secretKey())`.
- Edge → Edge: chave em `apikey` **e** em `Authorization: Bearer`; usar `chamarFuncao(...)` de
  `_shared/chamadas.ts`, que escreve a falha em `e2e_log` (fluxo `edge-chamada-falhou`). Nunca
  `try { invoke } catch {}` calado.
- App (Flutter): nunca a chave pública como `Bearer`; o token da SESSÃO de quem está ligado
  (`currentSession.accessToken`) e a pública só no `apikey`.
- Proibido (o varredor falha): `token === Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')`, `=== serviceKey`,
  `jwtRole(`, `.split('.')[1]`, `atob(` sobre partes do token — fora de `_shared/chaves.ts`.
- Cada função que o servidor chama responde a `{"ping":true}` com 200 `{"pong":true}` logo depois de
  confirmar quem chama (`respostaAoPing(req, cors)`) — é o que o vigia diário usa.

## Antes de trocar a chave — o levantamento

1. **Quem tem a chave**: cofre do banco (`vault.service_role_key`, `vault.sb_secret_backend`,
   `vault.dispatch_anon_jwt`), variáveis das Edge Functions (`SUPABASE_SECRET_KEYS`), GitHub Secrets,
   VPS (`/opt/*/.env`), `.env` do PC (fora do repo), apps instaladas (chave pública).
   Ver as chaves que existem: `supabase projects api-keys --project-ref ojykpzwqrtusfeakzrna -o json`
   (sem `--reveal` vêm **mascaradas** — não servem para testar; com `--reveal`, só dentro de um
   processo que nunca as imprime).
2. **Quem chama quem e com que chave** (banco → Edge):
   ```sql
   select p.proname, (p.prosrc ~ '_dispatch_jwt\(\)') dj, (p.prosrc ~ '_service_role_key\(\)') srk,
          (p.prosrc ~ 'service_role_key''') cofre, (p.prosrc ~ '''apikey''') manda_apikey
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosrc like '%functions/v1/%';
   ```
   Edge → Edge: `grep -rn "functions/v1/\|functions.invoke(" supabase/functions`.
   App → Edge: `grep -rn "functions/v1\|functions.invoke(" lib/`.
3. **O código**: `deno run --allow-read tools/varrer_chaves_funcoes.ts` tem de dizer "Tudo verde".

## Depois de trocar — as provas (todas, antes de dizer "fechado")

1. `--vivo` do varredor (a chave nova só por variável de ambiente):
   `deno run --allow-read --allow-env --allow-net tools/varrer_chaves_funcoes.ts --vivo` → 0 falhas.
2. Do banco, para cada função do servidor: legada em `Bearer`, nova em `Bearer`, nova só em `apikey`
   → 200 `{"pong":true}` (`net.http_post` + `net._http_response`); de fora, JWT forjado → 401/403;
   sem nada → 401/403. Correr o vigia: `select public._cron_saude_chaves_funcoes();` e, 2 min depois,
   `select public._cron_saude_chaves_verificar();` — 0 com problema. Ecrã do painel: Saúde das chaves
   (`/admin/system-health`).
3. Caminhos de dinheiro de ponta a ponta (cartão e MB Way): pedido, corrida TVDE, marcação, limpeza,
   lavagem, reserva, gorjeta. Testes de pagamento SEMPRE em dinheiro ou em conta de teste; o caminho do
   rascunho (`payment_drafts` → `finalize-order-from-intent`) prova-se com o vigia
   `_cron_vigia_pago_sem_pedido` e um PI fictício (a finalize confirma na Stripe e recusa: 502, sem
   pedido), e apagam-se os dados de teste no fim.
4. Avisos: `notify-client` (gatilho `trg_push_cliente_fase_pedido`), `notify-tvde-client`,
   `notify-driver`, `notify-partner` — logs com 200 e nenhum 401 vindo da app.
5. Registar em `docs/SEGURANCA-CHAVES.md` o que a porta (`verify_jwt`) aceita e o que o banco manda.

## Armadilhas já pagas

- A porta `verify_jwt=true` aceita a `sb_secret` em `Bearer` **e** só em `apikey` (medido 31/10); recusa
  JWT forjado (`UNAUTHORIZED_LEGACY_JWT`) e pedido sem cabeçalho (`UNAUTHORIZED_NO_AUTH_HEADER`).
  Mas também deixa passar a chave PÚBLICA: uma função sem verificação própria fica aberta a qualquer um
  (era o caso do `notify-tvde-driver` até 31/10).
- A tranca do PC nega editar/publicar `refund`, `finalize-order-from-intent`, `dispatch-engine`,
  `stripe-webhook`, `client-cancel-order`: a mudança vai como proposta em `docs/propostas/` e quem a
  publica é a Claude.ai pelo MCP. Não contornar.
- Ficheiros de migração com palavras de pagamento são recusados pela tranca: o SQL fica só em
  `supabase_migrations.schema_migrations` e no relatório.
- `apply_migration`/`execute_sql` com `delete`, `revoke` ou `unschedule` pedem confirmação no MCP; sem
  ninguém ao PC, expira e a sessão fica parada horas. Ver o que mudou no ar antes de reescrever
  (outra sessão pode ter aplicado o teu SQL entretanto).
- `supabase functions download` de várias funções para a mesma pasta mistura o `_shared` de cada uma;
  para comparar o `_shared`, descarregar a função sozinha.
- Funções do repo podem estar à frente do ar (ex.: gorjetas por publicar): para publicar só a correção
  da chave, remendar a versão DO AR (descarregada) e manter o `_shared` dela.
