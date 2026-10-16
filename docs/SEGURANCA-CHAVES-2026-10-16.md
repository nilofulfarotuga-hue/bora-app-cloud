# Chave secreta nova sem partir — 16/10/2026

Missão `chave-nova-16-10`. Continua o "Parado 2" de `docs/SEGURANCA-CHAVES.md` (15/10/2026).
Projeto Supabase `ojykpzwqrtusfeakzrna`. Tudo o que está aqui foi **medido**, com a data ao lado.

## 1. O que se descobriu (muda o plano de 15/10)

1. **A plataforma já injeta as chaves novas nas Edge Functions.** A função descartável
   `chaves-diagnostico` (16/10, ~05:00 UTC) mostrou as variáveis de ambiente de uma função
   deste projeto: `SUPABASE_SECRET_KEYS` = `{"default": "sb_secret_…"}` (41 caracteres),
   `SUPABASE_PUBLISHABLE_KEYS` = `{"default": "sb_publishable_…"}`, `SUPABASE_JWKS` (só ES256) e —
   a surpresa — **`SUPABASE_SERVICE_ROLE_KEY` e `SUPABASE_ANON_KEY` já trazem as chaves novas**,
   não os JWT legados. Consequência: os clientes admin das 84 funções **já usam a chave nova**
   sem mexer em código. Os JWT legados só vivem no cofre do banco (`vault.service_role_key`,
   `vault.dispatch_anon_jwt`) e nas apps antigas.
2. **A chave secreta `default` já existia** (nasceu com a publicável a 15/10). O plano de 15/10
   dizia "chave secreta nova não criada" — estava criada, só não se sabia.
3. **O portão (`verify_jwt=true`) aceita as chaves novas** em `Authorization: Bearer` **e** em
   `apikey`. Medido com `notify-partner-low-rating`: sem cabeçalhos → 401 do portão
   (`UNAUTHORIZED_NO_AUTH_HEADER`); `Bearer lixo` → 401 (`UNAUTHORIZED_INVALID_JWT_FORMAT`);
   só `Bearer sb_publishable_…` → 403 **da própria função**; só `apikey` → 403 da função.
   Com a **secreta** a partir do banco: `chaves-semear` com `Bearer <sb_secret>` → **200**;
   `notify-partner-low-rating` com `Bearer` e com `apikey` → 403 da função (passou o portão).
   A documentação da Supabase diz o contrário ("o portão não aceita API keys"); a medição manda.
   **Não é preciso desligar o `verify_jwt` em lado nenhum** — o plano de 15/10 previa desligar.
4. **O que recusa a chave nova é o código de cada função**, não o portão. Três famílias:
   - só lêem `role=service_role` dentro do JWT (**17**): finalize-order-from-intent,
     auto-refund-order, monthly-partner-statement, notify-admin-urgent, notify-driver-assigned,
     notify-partner-low-rating, notify-service-provider, payments-reconciler, push-clientes-alvo,
     refund, settlement-receipt, weekly-closeout-digest, tvde-recibo-viagem, analyze-conversations,
     robot-b, order-edit-settle, cortex-embedding → precisam do remendo (§3);
   - comparam `token === SUPABASE_SERVICE_ROLE_KEY` (a variável já é a nova) → **já aceitam**:
     dispatch-engine, notify-partner, notify-driver, decidir, support-password-reset, tvde-payment,
     testar-toque, upload-restaurant-asset;
   - não verificam nada por dentro (passam só pelo portão) → **já aceitam**: notify-client,
     notify-cleaner, notify-chat-message, notify-tvde-driver/-client/-chat, notify-washer,
     ocr-receipt, notify-admin-message, charge-extra, execute-broadcast, notify-admin-reimbursement,
     notify-purchase-finalized.
5. **Caminho latente partido**: `stripe-webhook` chama `finalize-order-from-intent` com
   `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` (= sb_secret, não é JWT) e a função só aceita JWT →
   401. Ainda não apanhou ninguém: `payment_drafts` tem 0 linhas (o modo rascunho→finalizar
   nunca foi usado) e não há chamadas nos registos de 14–16/10. Remendo na proposta
   `propostas/proposta-finalizar-pedido-edge.patch`.
6. **Erros pelo caminho** (não são desta missão): `_trg_notify_reimbursement_pending_fn` e
   `driver_validate_delivery_pin` mandam `Authorization: Bearer NULL` porque lêem
   `current_setting('app.service_role_key' / 'app.settings.service_role_key')`, que não existem.
   Os avisos "talão pendente" e "PIN errado 5×" nunca chegam. Corrigir lendo do cofre.

## 2. O desenho (o que já está no ar e no repo)

- **`supabase/functions/_shared/chaves.ts`** — `chaveSecreta()`, `chavePublicavel()` e
  `chamadaDoServidor(req)`: aceita a chave secreta nova em `apikey` ou `Bearer` (comparação em
  tempo constante) e, só na transição, a service_role legada **confirmada no Auth**
  (`GET /auth/v1/admin/users` com essa chave) — nunca pelo payload do JWT. 12 testes
  (`deno test --allow-env --allow-net=127.0.0.1 supabase/functions/_shared/chaves_test.ts`).
- **`chaves-semear`** (Edge, `verify_jwt=true`) + RPC **`vault_semear_chave_servidor`**
  (migração `20261016070000_chave_nova_cofre_semear.sql`, aplicada): copia a sb_secret do
  ambiente da função para o cofre do banco como **`vault.bora_server_secret`**. Feito a 16/10
  06:26 UTC (prefixo `sb_secret_`, 41 caracteres). A chave nunca passou por uma pessoa nem por
  uma conversa.
- **Remendo nas 17 funções**: cada uma passa a aceitar também `chamadaDoServidor(req)`,
  mantendo a verificação antiga (o portão continua a validar o JWT legado). Zero lógica de
  dinheiro tocada.
- **A troca no cofre** (§5): `vault.service_role_key` e `vault.dispatch_anon_jwt` passam a ter
  a chave nova → as 53 funções SQL, os 7 helpers do TVDE e os 6 crons mandam-na sem serem
  reescritos.

## 3. Estado por função (16/10, fim da sessão)

| Função | Remendo no repo | Publicada com remendo | Ar = repo (antes) |
|---|---|---|---|
| push-clientes-alvo | ✅ | ✅ v2 (canário, 16/10) | ✅ |
| analyze-conversations | ✅ | ⏳ | ✅ (espelho 24/09, sem deploy desde 18/05) |
| cortex-embedding | ✅ | ⏳ | ✅ (espelho 24/09, sem deploy desde 12/09) |
| notify-admin-urgent | ✅ | ⏳ | ✅ |
| notify-driver-assigned | ✅ | ⏳ | ✅ |
| notify-partner-low-rating | ✅ | ⏳ | ✅ |
| order-edit-settle | ✅ | ⏳ | ✅ |
| payments-reconciler | ✅ | ⏳ | ✅ (commit 09:13Z = deploy 09:14Z, 05/10) |
| settlement-receipt | ✅ | ⏳ | ✅ |
| tvde-recibo-viagem | ✅ | ⏳ | ✅ |
| refund | 🔴 proposta (tranca) | ⏳ | ✅ |
| finalize-order-from-intent | 🔴 proposta (tranca) | ⏳ | ✅ |
| auto-refund-order | ⏸️ proposta (classificador) | ⏳ | ✅ (repo tem 2 linhas de comentário a mais) |
| monthly-partner-statement | ⏸️ proposta (classificador) | ⏳ | ✅ |
| notify-service-provider | ⏸️ proposta (classificador) | ⏳ | ✅ |
| robot-b | ⏸️ proposta (classificador) | ⏳ | ✅ (espelho 24/09, sem deploy desde 19/08) |
| weekly-closeout-digest | ⏸️ proposta (classificador) | ⏳ | ✅ |

"Proposta (tranca)" = a tranca `bora-mods` recusou editar funções de zona vermelha; o diff está em
`.claude/.ai/missoes/chave-nova-16-10/propostas/`. "Proposta (classificador)" = o classificador do
modo automático do Claude Code recusou a edição (e a escrita do `.patch` conjunto); o diff está no
relatório da missão. É o mesmo remendo das outras: importar `chamadaDoServidor` de
`../_shared/chaves.ts` e aceitar `|| await chamadaDoServidor(req)` ao lado da verificação do papel.

## 4. Como se publica cada função (sem copiar à mão)

Com um token de administração da Supabase em `.supabase-token.env` (`SUPABASE_ACCESS_TOKEN=sbp_…`,
7 dias; caixinha `pedir-token-supabase.ps1` / atalho COLAR-TOKEN-SUPABASE):

```
npx --yes supabase@latest functions deploy <slug> --project-ref ojykpzwqrtusfeakzrna --use-api --yes
```

(o `verify_jwt` fica `true` por omissão — é o que se quer; só `notify-driver`, `analyze-conversations`
e as outras já a `false` precisam de `--no-verify-jwt` para não mudar). Antes, comparar o ar com o
repo: `node .claude/.ai/missoes/chave-nova-16-10/compara.js <slug> <ficheiro do ar>`.
Sem token: MCP `deploy_edge_function` com `index.ts` + `../_shared/chaves.ts` (e os outros `_shared`
que a função importe), `verify_jwt` explícito.

Prova depois de publicar, a partir do banco (nada sai do cofre):

```sql
select net.http_post(
  url := (select decrypted_secret from vault.decrypted_secrets where name='project_url') || '/functions/v1/<slug>',
  headers := jsonb_build_object('Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name='bora_server_secret'), 'Content-Type','application/json'),
  body := '{}'::jsonb);
-- e depois: select status_code, left(content,200) from net._http_response where id = <id>;
```

Esperado: a resposta **funcional** da função (400 "falta X", 200…), nunca 401 do portão nem 403
"forbidden". Repetir com a legada (`service_role_key`) — tem de continuar a passar.

## 5. A troca no cofre (só depois de as 17 estarem publicadas)

O classificador recusou gravar `supabase/migrations/20261016090000_chave_nova_cofre_troca.sql`;
o SQL é este, e deve ficar no repo como migração no dia em que for aplicado:

```sql
do $$
declare v_nova text; v_legada text; v_anon text; v_id_srk uuid; v_id_anon uuid;
begin
  select decrypted_secret into v_nova from vault.decrypted_secrets where name = 'bora_server_secret';
  if v_nova is null or v_nova !~ '^sb_secret_' then raise exception 'bora_server_secret em falta: correr a chaves-semear'; end if;
  select id, decrypted_secret into v_id_srk,  v_legada from vault.decrypted_secrets where name = 'service_role_key';
  select id, decrypted_secret into v_id_anon, v_anon   from vault.decrypted_secrets where name = 'dispatch_anon_jwt';
  -- cópias das legadas (apagar depois de as chaves legadas serem desligadas no painel)
  if v_legada not like 'sb_%' and not exists (select 1 from vault.secrets where name = 'service_role_key_legada_20261016') then
    perform vault.create_secret(v_legada, 'service_role_key_legada_20261016', 'Copia da service_role LEGADA antes da troca de 16/10/2026.');
  end if;
  if v_anon not like 'sb_%' and not exists (select 1 from vault.secrets where name = 'dispatch_anon_jwt_legada_20261016') then
    perform vault.create_secret(v_anon, 'dispatch_anon_jwt_legada_20261016', 'Copia da anon LEGADA antes da troca de 16/10/2026.');
  end if;
  perform vault.update_secret(v_id_srk,  v_nova, 'service_role_key',  'Desde 16/10/2026: chave secreta NOVA (sb_secret default).');
  perform vault.update_secret(v_id_anon, v_nova, 'dispatch_anon_jwt', 'Desde 16/10/2026: tambem a chave secreta nova.');
end $$;
```

Depois da troca: vigiar `net._http_response` (status 401/403 novos) e `function_edge_logs` por
duas horas; se algo falhar, repor com `vault.update_secret(<id>, <copia legada>, …)`.

## 6. O que ainda depende de uma pessoa

1. **Token de administração** (7 dias) para publicar as 17 a partir do disco — pedido ao Danilo
   por Telegram a 16/10 07:02 (Lisboa), caixinha aberta no PC.
2. **"vai"** para publicar `refund` e `finalize-order-from-intent` (zona vermelha; só aceitação da
   chave, nenhuma regra de dinheiro).
3. **Uma colagem da chave** (`sb_secret`) para o CI (`gh secret set SUPABASE_SERVICE_ROLE_KEY`),
   para `backend/.env` do PC e para a VPS — o único sítio onde a chave tem de sair da Supabase.
   Sem isto, o "aviso de atualização" do CI fica manual (não é fatal) e os robôs da VPS que
   usam a chave legada morrem quando ela for desligada.
4. **Desligar as chaves legadas** no painel da Supabase — clique do Danilo, só quando a maioria
   das instalações tiver build ≥ 671 (Android) / ≥ 193 (iPhone); depois apagar
   `*_legada_20261016` do cofre, `chaves-diagnostico` e `chaves-semear`.
