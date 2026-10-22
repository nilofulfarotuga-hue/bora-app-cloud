# Relatório — chave-nova-sem-partir-2026-10-16

Missão `chave-nova-sem-partir-2026-10-16` (fluxo `chave-nova-16-10` no `e2e_log`, run `chave-nova-2026-10-16`).
Motor: Claude Fable 5.1 (a ordem pedia Opus), sessão remota no PC do Danilo. Porta: Claude Code.
Ramo `chave-nova-16-10` (worktree `C:\BoraLocal\wt-chave-nova-16-10`) → `autonomous-night-2026-04-29`.
Autorização literal do Danilo (16/10 05:09): "Pronto, fecha essa primeiro, mas eu não quero que parta nada, entendeu? Fecha essa daí primeiro."

**Acessos usados:** projeto Supabase `ojykpzwqrtusfeakzrna` (MCP: SQL, migrações, Edge Functions, registos); GitHub `nilofulfarotuga-hue/bora-app-cloud` (`gh` com sessão no PC); VPS `srv1786862.hstgr.cloud` por SSH (só leitura); Telegram do Danilo pela VPS; Chrome perfil Danilo (página de tokens aberta às 07:02).
**Criado nesta sessão:** Edge `chaves-semear` (ativa) e `chaves-diagnostico` (já só responde 410); RPC `vault_semear_chave_servidor`; segredo `sb_secret_backend` no cofre; `_shared/chaves.ts` + `_shared/keys.ts`; `supabase/config.toml`; migrações `20261016070000`, `20261016071500` (aplicadas) e `20261016100000` (escrita, por aplicar); scripts `pedir-token-supabase.ps1`, `distribuir-chave.ps1`, `secretkey.js`, `compara.js`; atalho `COLAR-TOKEN-SUPABASE` no ambiente de trabalho; `docs/CHAVES-2026-10-16.md`; nota do prompt no Obsidian.

## 1. O que NÃO ficou feito (primeiro)

1. **As Edge Functions não foram publicadas** (só a `push-clientes-alvo`, como canário). Publicar pela CLI, como a ordem manda, precisa do token de administração da Supabase, que só o Danilo pode gerar; a caixinha para o colar está aberta no PC desde as 07:02. Por isso os Blocos 3 e 4 ficaram preparados e provados, mas **não aplicados**.
2. **A tranca da casa recusou** editar `refund`, `finalize-order-from-intent`, `charge-extra` e os ficheiros de `.github/workflows` (zona vermelha por código). A ordem autoriza, mas a tranca não lê a ordem. Ficam como proposta (secção 6).
3. **O classificador do modo automático do Claude Code recusou** o mesmo remendo em `auto-refund-order`, `monthly-partner-statement`, `notify-service-provider`, `robot-b`, `weekly-closeout-digest` e `notify-cleaner` (duas tentativas cada). Nada ficou a meio: o que não tem o remendo continua a funcionar com `verify_jwt=true`.
4. **Chave com nome próprio `backend-2026-10` não criada** (sem navegador nem token nesta sessão). Usada a `default`, como a ordem permite.
5. **Chaves legadas continuam ligadas** (Bloco 6 manda não desligar).

## 2. Para o Danilo

Fiz isto: a chave nova do servidor já está dentro do cofre do banco sem nunca ter passado por mim nem por ti. Descobri, medindo ao vivo, que a Supabase já põe as chaves novas dentro de todas as funções do servidor e que a porta de entrada as aceita; isso significa que metade do perigo que o plano de 15/10 temia não existe. Escrevi a peça comum que ensina as funções a aceitar a chave antiga e a nova ao mesmo tempo, apliquei-a em 77 funções, pus portão de entrada em 11 que estavam sem nenhum (três delas estavam abertas a qualquer pessoa), publiquei uma como teste e provei-a com as duas chaves e com um token falso recusado. A troca no lado do banco está escrita e provada em ensaio: 70 funções e 6 tarefas agendadas passam a mandar a chave nova, com cópia de segurança de tudo. A app na web já usa a chave publicável e não a antiga (li o ficheiro publicado). Nada partiu: tudo o que está no ar continua a aceitar a chave antiga.

Falta isto: publicar as outras funções (preciso do token da Supabase na caixinha), aplicar a troca no banco, trocar a chave nos dois robôs da VPS, nos ficheiros do PC e no GitHub (o script já faz tudo isso sozinho quando tiver o token), e aplicar os remendos que a tranca e o classificador recusaram.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico: os remendos em `refund`, `finalize-order-from-intent` e `charge-extra` só ensinam a função a aceitar a chave nova; não mudam um cêntimo. A tranca só os deixa aplicar com o modo seguro ou pela tua mão.

Erros que encontrei pelo caminho: três avisos ao admin nunca saíam porque as funções do banco mandavam uma chave vazia ou liam um cofre que não existe (PIN errado cinco vezes, talão pendente, avaliação baixa de parceiro) — a migração do Bloco 3 corrige-os de caminho. Três funções estavam abertas a qualquer chamada e outra aceitava um token forjado — fechadas no código, por publicar. O webhook da Stripe chama a função de finalizar pedido com a chave nova e ela recusa; esse caminho nunca foi usado (tabela de rascunhos vazia), remendo na proposta.

Próximo passo: o token na caixinha. Com ele publico as funções, provo cada uma, aplico a troca no banco, distribuo a chave aos robôs e ao CI, e só te chamo para o "vai" das três de zona vermelha. Desligar as chaves antigas fica para quando a Claude.ai disser.

## 3. Bloco a bloco, com prova

**Bloco 1 — cofre.** `vault.sb_secret_backend` (prefixo `sb_secret_`, 41 caracteres) posto pela `chaves-semear` chamada do banco com a legada (`net._http_response` id 39963: 200 `{ok:true, prefixo:"sb_secret_", tamanho:41}`); renomeado de `bora_server_secret` às 07:04 UTC. Prova: `select name from vault.secrets where name='sb_secret_backend'` → 1 linha.

**Bloco 2 — código.** `keys.ts`: `secretKey()`, `isSecretApikey()`, `callerOk()` (3 testes) sobre `chaves.ts` (12 testes; 22 verdes em `_shared/`). `secretkey.js`: 77 funções passam a `secretKey()`; `deno check`: 0 erros novos (31 ficheiros com erro de tipos `npm:@types/node` que já falhavam antes). Portão `exigirCallerOk` em 11 funções; `analyze-conversations` deixa de aceitar `role=service_role` sem assinatura; `apikey` acrescentado nos 3 reencaminhadores. `config.toml` com as 17 funções que já estavam a `verify_jwt=false` (sem ele a CLI partia o `stripe-webhook`). Medições do portão: publicável em Bearer e em apikey → 403 da função (passou); secreta do banco em Bearer → `chaves-semear` 200, `notify-partner-low-rating` 403 da função (ids 39972–39974). Canário `push-clientes-alvo` v2: legada → 400 funcional; nova em Bearer → 400; nova só em apikey → 400; JWT forjado → 401 do portão (ids 39991–39995). Comparação ar vs repositório antes de tocar: 13 iguais byte a byte, 4 iguais por construção (espelho de 24/09 sem publicação desde), `tvde-payment` estava à frente no ar e foi espelhada (commit a11d8b36).

**Bloco 3 — banco manda apikey.** Migração `20261016100000_chave_nova_banco_manda_apikey.sql` (determinística, sem copiar corpos de funções). Prova em rollback (DO … RAISE): 70 funções + 6 crons sem erro, 70 cópias em `bkp_fn_chave_legada_20261016`. Manda `apikey` e também `Authorization: Bearer` porque `dispatch-engine` e `refund` só olham para o Bearer e a tranca não as deixa alterar. **Por aplicar** (depende do Bloco 2 publicado). O pedido de teste em dinheiro faz-se depois de aplicar.

**Bloco 4 — robôs e CI.** Inventário por marca da chave (nunca pelo valor): VPS `/opt/whatsapp-bora/.env` e `/opt/assistente-negocio/.env` (três serviços), contentor Hermes sem a chave; PC quatro `.env`; GitHub o segredo do CI. Os robôs mandam `apikey` + `Bearer` com a mesma chave e a REST aceita isso com a chave nova (200; só Bearer dá 401), por isso basta trocar o valor. `distribuir-chave.ps1` pronto (token ou colagem; prova na REST; GitHub por stdin, `.env` do PC, `.env` da VPS + reinício). **Não corrido** (sem token).

**Bloco 5 — app e painel.** Web publicada: `main.dart.js` com `sb_publishable_` e sem a anon legada. Android/iPhone: o CI mete a publicável desde 15/10 (builds 671–673; o de hoje, 674, verde: Android 41 min, web 3 min). `.dart_defines` do PC passou a publicável. Faltam (tranca): `testlab_robo.yml` e `e2e-web.yml` chamarem o mesmo script.

**Bloco 6 — documento.** `docs/CHAVES-2026-10-16.md`: o que se mediu, feito por bloco, como se desliga, como se reverte, quem ainda usava a legada. Nada desligado.

## 4. Erros encontrados pelo caminho (registados, não corrigidos à parte)

- `driver_validate_delivery_pin` e `_trg_notify_reimbursement_pending_fn` mandam `Bearer NULL` (lêem `current_setting` inexistente); `_notify_partner_low_rating_trigger` lê `vault.read_secret` com segredos que não existem. Os três avisos nunca chegaram. A migração do Bloco 3 corrige-os.
- `execute-broadcast`, `notify-admin-reimbursement`, `notify-purchase-finalized` estavam com `verify_jwt=false` e sem verificação (abertas); `analyze-conversations` (também a false) aceitava JWT forjado. Fechadas no código; por publicar.
- `stripe-webhook → finalize-order-from-intent` recebe `Bearer sb_secret` e dá 401 (`payment_drafts` vazio, nunca usado).
- `update-products` corre com `verify_jwt=false` e sem autenticação (os crons chamam-na sem cabeçalhos). Fora desta missão.
- Tranca: falsos positivos em linhas que declaram constantes `*_KEY` a partir do ambiente, em `NOME=` dentro de expressões regulares sem valor, e em tokens de brincar nos testes. Classificador: recusas sem padrão.

## 5. Como continuar (ordem)

1. Token na caixinha → `npx --yes supabase@latest functions deploy <slug> --project-ref ojykpzwqrtusfeakzrna --use-api --yes` para as funções alteradas (lista em `git diff --name-only HEAD~2 -- supabase/functions`); antes de cada uma, `compara.js` contra o ar; depois, prova (i)(ii)(iii) a partir do banco e linha no `e2e_log`.
2. Aplicar `20261016100000_chave_nova_banco_manda_apikey.sql` (MCP `apply_migration`); vigiar `net._http_response` por duas horas; pedido de teste em dinheiro numa loja de teste.
3. `distribuir-chave.ps1` (GitHub, PC, VPS); confirmar `systemctl is-active` e uma escrita nova dos robôs.
4. "vai" + modo seguro da tranca → aplicar as propostas (secção 6); publicar; passar `verify_jwt` a false, uma a uma, nas funções com portão.
5. Quando a Claude.ai decidir: desligar as legadas no painel (reversível); depois apagar `service_role_key` e `dispatch_anon_jwt` do cofre, `chaves-diagnostico`, as cópias paradas da VPS.

## 6. Propostas recusadas (o que falta em cada ficheiro)

Em todas: `import { chamadaDoServidor } from '../_shared/chaves.ts'` ao lado dos imports (ou `exigirCallerOk`/`secretKey` de `../_shared/keys.ts`).

- **refund** e **finalize-order-from-intent** (tranca): diffs prontos em `.claude/.ai/missoes/chave-nova-16-10/propostas/*.patch` — a condição `role !== 'service_role'` passa a `&& !(await chamadaDoServidor(req))`.
- **charge-extra** (tranca): logo a seguir ao `OPTIONS`, `const bloqueio = await exigirCallerOk(req, corsHeaders); if (bloqueio) return bloqueio;`.
- **auto-refund-order**: linha 25, `if (roleFromJwt(token) !== 'service_role' && !(await chamadaDoServidor(req))) …`.
- **monthly-partner-statement** (84–91) e **weekly-closeout-digest** (96–104): `const chaveNovaOk = await chamadaDoServidor(req)` antes do `try`; `if (!chaveNovaOk && !authHeader.startsWith('Bearer ')) throw …`; descodificar o JWT só quando `!chaveNovaOk` (modelo: `settlement-receipt`).
- **notify-service-provider** (32–45): igual, com `const payload = chaveNovaOk ? { role: 'service_role' } : JSON.parse(…)` (modelo: `notify-admin-urgent`).
- **robot-b** (666): `const chaveNovaOk = await chamadaDoServidor(req); if (jwtRole === 'service_role' || chaveNovaOk) {`.
- **notify-cleaner**: portão `exigirCallerOk` a seguir ao `OPTIONS` (modelo: `notify-washer`).
- **.github/workflows**: `build_android.yml`/`build_ios.yml` curl só com `apikey`; `testlab_robo.yml` e `e2e-web.yml` chamam `python3 .github/scripts/chave_publica_supabase.py .dart_defines` a seguir ao decode.
