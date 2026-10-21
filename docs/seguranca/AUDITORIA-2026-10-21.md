# Auditoria de segurança do app Bora — 21/10/2026

> Missão `geral-noite-21-10`, agente N4 (bloco E). Alvos: o nosso app (pacote `pt.boraapp.bora`,
> código no worktree), o bundle web público `app.boraguarda.com` e o que é público em
> `emdia.boraguarda.com`. Projeto Supabase `ojykpzwqrtusfeakzrna`. Nunca se tocou em apps ou sites
> de terceiros. Trabalho no worktree `C:\BoraLocal\wt-seguranca-21-10` (ramo `seguranca-21-10`),
> sem `git push`.

## Como se testou (e o que NÃO se fez)

- **Não se instalou** `npx rea-agents` nem nenhum pacote/binário de terceiros (regra da sessão: não
  se corre código de fonte não confiável). Foi-se direto ao caminho de reserva: ler o nosso código
  e usar o MCP do Supabase.
- Código-fonte nosso: `lib/`, `web/`, `android/`, `ios/`, `supabase/functions/` (90 pastas de Edge).
- Bundles públicos: descarregados com `python urllib` para a pasta de rascunho e varridos à procura
  de segredos.
- Supabase: `get_advisors` (security + performance); `has_function_privilege` para `anon` e
  `authenticated` em TODAS as ~1340 funções `public.*`; políticas RLS; buckets e políticas do
  Storage; `verify_jwt` e código de cada Edge; crons.
- Provas com **defeito plantado / ataque real**, em rollback (`set_config('request.jwt.claims',…)` +
  `RAISE` que reverte tudo), ou chamada HTTP real com a chave pública da app contra o alvo a testar.

## Achados por gravidade

### ALTO — corrigidos e provados

1. **3 Edge de push aceitavam qualquer conta com sessão e mandavam aviso com texto livre a qualquer
   pessoa** — `notify-admin-message`, `notify-cleaner`, `notify-washer`. Usavam `exigirCallerOk`, que
   deixa passar servidor **ou** qualquer utilizador com sessão. Um cliente comum podia disparar um
   push (título + corpo à escolha) a um `user_id` qualquer (estafeta, lavador, parceiro, outro
   cliente), imitando um aviso do painel. **(achado (a) da ordem — confirmado)**
   - **Corrigido:** novo portão `exigirServidorOuAdmin` em `_shared/chaves.ts` (servidor com chave de
     serviço / legada confirmada no Auth, **ou** admin `app_metadata.role='admin'`); as 3 funções
     passaram a usá-lo. Deploy pelo MCP com os ficheiros inteiros, `verify_jwt=true` (o que estava).
   - **Prova:** ANTES, chamada com a chave publicável da app → push aceite (chegava a `no_fcm_token`,
     ou seja o portão deixava entrar). DEPOIS → `403 {"ok":false,"error":"forbidden"}` nas três.
     O servidor (chave de serviço via `pg_net`) continua a passar: `200 {"ok":false,"reason":
     "no_fcm_token"}` (alvo de teste inexistente). 20 testes Deno verdes (incl. defeito plantado:
     o portão antigo deixa a conta normal passar, o novo recusa-a).

2. **Balde público `avatars` deixava qualquer um (até sem conta) escrever/apagar a foto de outra
   pessoa.** 4 políticas para `anon`+`authenticated` só com `bucket_id='avatars'`, sem amarrar à
   pasta do dono.
   - **Prova ANTES (HTTP real, só com a chave pública da app):** upload anónimo `200` e delete
     anónimo `200`; em rollback, um `anon` conseguia `UPDATE` em **10** fotos de utilizadores reais.
   - **Corrigido** (migração `...avatars_so_a_propria_pasta`): políticas novas só para `authenticated`
     e só na própria pasta `(<uid>/...)`.
   - **Prova DEPOIS:** upload anónimo → `403 new row violates row-level security policy`; o dono
     altera a própria (`1`) e não as dos outros (`0`). Ver as fotos pelo URL público do balde
     continua a funcionar (`200`), que é o que a app precisa.

### MÉDIO — corrigidos e provados

3. **12 funções `SECURITY DEFINER` que escrevem dados sem olhar para quem chama, abertas a
   `authenticated` pela API.** Nenhuma é usada pela app com a sessão do utilizador (chamadores: Edge
   com chave de serviço, cron como `postgres`, MCP, ou outras funções definer). As piores:
   `agent_propose_action` (um cliente punha uma "ação" tipo `ACCOUNT_UPDATE` na fila do admin para
   outra pessoa), `cortex_proposal_sync_upsert` / `cortex_mark_ordem_criada` (forjar propostas da
   fila vermelha do Córtex), os 5 `maestro_*` (marcar itens do loop como aprovados / gravar notas do
   Juiz), `encomenda_telefone_resumo` (ler nome do cliente, notas e itens de qualquer pedido),
   `_reservas_pro_autosetup` (criar sala e mesas na loja de outra pessoa),
   `_appointment_cron_expire_pending_payment` e `assinaturas_avisar_renovacoes` (só cron).
   - **Corrigido** (migração `...funcoes_internas_so_servidor`): REVOKE de PUBLIC, `anon` e
     `authenticated` (os dois caminhos de permissão) e fica só `service_role`.
   - **Prova:** ANTES, como conta normal, `agent_propose_action`/`cortex_*`/`encomenda_telefone_resumo`
     corriam (a 1.ª só parava na FK do `user_id`, o que confirma que chegou lá dentro).
     DEPOIS → `42501 permission denied for function ...` nas 12; `has_function_privilege` confirma
     `anon=false auth=false srv=true` em todas.

4. **3 funções mandavam `severity='warning'`, que a tabela `admin_notifications` recusa (CHECK só
   aceita low/medium/high/critical).** `fn_alerta_corrida_convidado` e `tvde_queixa_criar` engoliam o
   erro em silêncio (o admin nunca era avisado de corrida em modo convidado nem de queixa TVDE);
   `tvde_conformidade_diaria` (cron diário 07:15) rebentava inteira no dia em que houvesse avisos.
   **(achado (b) da ordem — confirmado: eram 3, não tocam dinheiro)**
   - **Corrigido** (migração `...notify_admin_event_severidade`): `notify_admin_event` traduz, num
     sítio só, os nomes comuns (`warning→medium`, `info→low`, `error→high`) para a escala da tabela.
   - **Prova:** ANTES o insert de `'warning'` dava `23514 check constraint`; DEPOIS passa e fica
     gravado como `medium`. Os privilégios da função mantiveram-se (`CREATE OR REPLACE`, continua só
     `postgres`/`service_role`).

### Sem problema (verificado)

- **Segredos nos bundles públicos e no repo:** `app.boraguarda.com` só traz a chave **publicável** do
  Supabase (`sb_publishable_…`), a chave do Maps e a config pública do Firebase — tudo o que é normal
  um cliente ter. **Nenhuma** chave de serviço, `sk_live`, `whsec_`, `sb_secret`, JWT `service_role`,
  `re_`/`ghp_`/token do Telegram no `main.dart.js` nem nos outros ficheiros. `emdia.boraguarda.com` só
  expõe a sua própria chave `anon` (projeto `tgdmgtmknbwhcqoxtjbs`, outro app do Danilo). No repo, os
  `sk_live`/`sb_secret`/JWT encontrados são todos **de brincar**, em ficheiros de teste
  (`_shared/*_test.ts`, `bora-mods/*test*`) ou em notas `.claude/`; nada de produção. (A chave do
  Maps sem restrição e o repo terem estado públicos já estão registados em memória — não é novo.)
- **131 tabelas com RLS ligada e sem política** = fechadas a `anon`/`authenticated` (negam por
  omissão). Correto.
- **Trava do banco:** corre e morde nesta pasta (ver proposta) — enviei-lhe um `truncate
  ledger_entries` e respondeu `exit 2`.

## Só reportado (proposta pronta, não aplicada) — em `docs/seguranca/propostas/`

- **`platform-settings-leitura-aberta.md`** — qualquer conta com sessão faz `select * from
  platform_settings` e vê as 47 chaves `is_secret` (markup oculto 0.05, comissões, config Stripe).
  Pior que o buraco já conhecido do `get_setting`. **Toca dinheiro → espera "vai".**
- **`register-partner-confirma-sessao.md`** — a Edge `register-partner` (verify_jwt=false) tira o
  `user_id` do JWT **sem validar a assinatura**; dá para criar candidatura de parceiro em nome de
  outro `user_id`. A prova ao vivo foi **bloqueada pelo classificador**; correção proposta usa
  `utilizadorDoPedido()` (confirma no Auth). Não é dinheiro mas mexe em `service_role` e onboarding.
- **`trava-aponta-para-pc-antigo.md`** — a Trava guarda, mas os hooks apontam por uma **junção** do
  Desktop para `C:\BoraLocal`; se a junção sumir, a Trava deixa de correr em silêncio. Proposta:
  `$CLAUDE_PROJECT_DIR` nos `command`. **Não se tocou no `.claude/settings.json` (zona protegida).**
- **Regra de dinheiro decidida no cliente (ponto 5 da ordem) — só observação, não se mexeu:** o
  `create-payment-intent` já valida o montante contra `orders.payment_buffer_total` (±5%); um varrimento
  a fundo de quanto do preço/total o servidor recalcula vs. aceita do Flutter fica para o bloco de
  pagamentos (G/Stripe), que não é desta auditoria.

## Não se tocou (por ordem da missão)

`notify-tvde-driver` e as funções de recibo/aviso de reserva TVDE (agente N2), `refund`,
`finalize-order-from-intent`, `charge-extra`, `stripe-webhook`, `create-payment-intent` (bloco
G/Stripe), o filme (BoraStudio), e o `.claude/settings.json`.

## Ficheiros alterados neste worktree

- `supabase/functions/_shared/chaves.ts` — novo `exigirServidorOuAdmin`.
- `supabase/functions/_shared/servidor_ou_admin_test.ts` — teste novo (defeito plantado + servidor/admin).
- `supabase/functions/notify-admin-message/index.ts`, `notify-cleaner/index.ts`, `notify-washer/index.ts`
  — portão trocado (código igual ao que estava no ar + o novo portão).
- `supabase/migrations/20261021200421_...`, `..200437_...`, `..200446_...` — cópias exatas das 3
  migrações aplicadas no banco (mesmo md5).
- `docs/seguranca/AUDITORIA-2026-10-21.md` (este) e `docs/seguranca/propostas/*`.
