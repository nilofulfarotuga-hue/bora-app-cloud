# 🔒 SEGURANÇA — 24 Edge Functions sem `verify_jwt` declarado
Aberto: 2026-08-01 · Estado: **AUDITADO (read-only)** · Zona: 🟡 sensível (autenticação)

> **RECONFIRMADO — 8ª vez (motor Opus, nova execução da mesma tarefa aprovada, mesma data
> 2026-08-01):** verificação leve (não reauditoria completa) — `grep -rq verify_jwt` por pasta
> em `supabase/functions/*/` (excluindo `_shared`) devolve outra vez **53 pastas totais / 24 sem
> `verify_jwt`**, e a lista de 24 nomes bate 1:1 com Balde A (12) + Balde B (10) + Balde C (2) já
> classificados abaixo — zero adição, zero remoção, zero renomeação pela 8ª vez seguida. Zero
> escrita a Edge Function/config.toml/deploy nesta sessão. **O achado é estável; a única
> pendência continua a ser a decisão do Danilo sobre Balde B/C, não mais auditoria.**

> **RECONFIRMADO — 7ª vez (motor Opus, tarefa aprovada substitui prop-85cf635b — falso-positivo
> de palavras-chave, mesma data 2026-08-01):** verificação leve (não reauditoria completa, por
> instrução da própria lição gravada nesta memória): recontagem de pastas em `supabase/functions/`
> (excluindo `_shared`) = **53**; loop `grep -rq verify_jwt` por pasta devolve outra vez
> **exatamente os mesmos 24 nomes** (conferidos um a um: `admin-ai-assistant`,
> `admin-cancel-order`, `admin-force-driver-logout`, `cancel-order-with-choice`,
> `client-cancel-order`, `delete-account`, `execute-cancellation`, `import-guarda-businesses`,
> `notify-admin-reimbursement`, `notify-chat-message`, `notify-cleaner`, `notify-client`,
> `notify-purchase-finalized`, `notify-tvde-client`, `notify-tvde-driver`, `ocr-receipt`,
> `pay-debt-standalone`, `register-partner`, `reprocess-refund`, `robot-b`, `tvde-payment`,
> `update-products`, `upload-receipt`, `upload-restaurant-asset`) — bate 1:1 com Balde A
> (12) + Balde B (10) + Balde C (2) já classificados abaixo. Zero adição/remoção/renomeação pela
> 7ª vez seguida. Zero escrita a Edge Function/config.toml/deploy nesta sessão — só leitura.
> **O achado é estável; o único trabalho pendente é a decisão do Danilo sobre Balde B/C — não
> mais auditoria.**

> **RECONFIRMADO — 6ª vez (motor Opus, tarefa aprovada substitui prop-85cf635b, mesma data
> 2026-08-01):** recontagem em `supabase/functions/*/` (excluindo `_shared`, 53 pastas): **53
> Edge Functions locais, 24 sem `verify_jwt` declarado em nenhum ficheiro da pasta** — mesmos 24
> nomes, conferidos um a um contra a tabela abaixo: Balde A (12) + Balde B (10) + Balde C (2) =
> 24, zero adição/remoção/renomeação. Zero alteração a qualquer Edge Function, `config.toml` ou
> deploy nesta sessão — só leitura. **Achado estável pela 6ª vez seguida; o que falta continua a
> ser a decisão do Danilo sobre Balde B/C, não mais auditoria.**

> **RECONFIRMADO — 5ª vez (motor Opus, sessão seguinte, mesma data 2026-08-01):** recontagem
> shell (`grep -rq verify_jwt` por pasta, 53 pastas) devolve outra vez **53 total / 24 sem
> verify_jwt**, mesma lista de 24 nomes, batendo um a um com Balde A(12)+B(10)+C(2). Spot-check
> nos dois achados do Balde C direto no código vivo: `register-partner/index.ts` (linhas 63-89)
> continua a decodificar o JWT à mão via `atob`/`JSON.parse` e a usar `payload.sub` sem
> `auth.getUser()` — confirmado; chamador único `lib/auth/auth_store.dart:1333` confirmado por
> grep. `upload-restaurant-asset`: 4 chamadores confirmados por grep
> (`register_partner_screen.dart`, `admin_partner_detail_screen.dart`,
> `admin_service_provider_detail_screen.dart`, `partner_manage_staff_screen.dart`) — um 5º match
> em `private_bucket_image.dart` é só um comentário de código, não uma chamada, não altera a
> contagem. Zero escrita em Edge Functions/config/deploy. **Isto já foi verificado 5 vezes sem
> drift — o achado é estável; o que falta é decisão do Danilo sobre Balde B/C, não mais auditoria.**

> **RECONFIRMADO — 4ª vez (motor Opus, esta sessão, 2026-08-01, prop-85cf635b substituída):**
> a proposta anterior caiu em vermelha por falso-positivo de palavras-chave no texto da TAREFA,
> não por erro no relatório — recontei do zero com `grep -rq verify_jwt` na pasta inteira de
> cada uma das 53 pastas de `supabase/functions/*/` (excluindo `_shared`): **53 total, 24 sem
> `verify_jwt` em nenhum ficheiro da pasta**, e a lista de 24 nomes bate exatamente, um a um,
> com Balde A (12) + Balde B (10) + Balde C (2) já listados abaixo — zero adição, zero remoção.
> Reli ao vivo os dois `index.ts` do Balde C: `register-partner` (linhas 72-89 do ficheiro atual)
> continua a decodificar o JWT à mão via `atob`/`JSON.parse` e a usar `payload.sub` sem chamar
> `auth.getUser()`; `upload-restaurant-asset` (linhas 15-53) continua sem extrair `Authorization`
> de todo, aceitando `restaurantId`/`kind`/`fileBase64` diretos do body. Confirmei por `grep` os
> chamadores: `register-partner` só em `lib/auth/auth_store.dart:1333`; `upload-restaurant-asset`
> em `register_partner_screen.dart`, `admin_partner_detail_screen.dart`,
> `admin_service_provider_detail_screen.dart` e `partner_manage_staff_screen.dart` — igual ao
> já registado. Zero escrita em Edge Functions/config/deploy nesta sessão.

> **RECONFIRMADO pela 3ª vez (motor Opus, sessão autónoma, mesma data 2026-08-01):** recontagem
> read-only agora, com método mais rigoroso que as vezes anteriores — em vez de olhar só para
> `config.toml`, corri `grep -rq verify_jwt` na pasta INTEIRA de cada uma das 53 (qualquer
> ficheiro, não só `config.toml`). Resultado: continuam **53 locais**, continuam **14** com
> `config.toml` próprio (a mesma lista de nomes), continuam **24 sem `verify_jwt` em lado
> nenhum da sua pasta** — e a lista de nomes bate **exatamente** com a tabela abaixo, uma a uma:
> Balde A (12) + Balde B (10) + Balde C (2) = 24, zero adições, zero remoções, zero renomeações.
> `supabase/config.toml` (central) não tem nenhuma menção a `verify_jwt` — não há override
> central a considerar. Nada foi alterado; zero escrita em Edge Functions/config/deploy.

> **RECONFIRMADO numa sessão seguinte (motor Opus, mesma data):** recontei as pastas
> (`supabase/functions/*/index.ts` = 53, excluindo `_shared`) e a metodologia (só 14 pastas têm
> `config.toml` explícito — `admin-payments`, `charge-extra`, `confirm-mbway-payment`,
> `create-mbway-payment-intent`, `create-payment-intent`, `dispatch-engine`, `list-saved-cards`,
> `manage-saved-cards`, `notify-driver`, `notify-partner`, `refund`, `stripe-webhook`,
> `support-chatbot`, `support-submit-ticket` — nenhuma delas está nas 24, o que bate). Verifiquei
> linha a linha os dois achados do Balde C direto no `index.ts` vivo: `register-partner`
> (linhas 72-89) decodifica o JWT à mão via `atob`/`JSON.parse` e usa `payload.sub` sem chamar
> `getUser()` nem validar assinatura — confirmado; `upload-restaurant-asset` (linhas 15-53) não
> lê `Authorization` de todo, aceita `restaurantId`/`kind`/`fileBase64` diretos do body —
> confirmado. Também confirmei por `grep` que `auth_store.dart:1333` chama `register-partner`,
> como o relatório afirma. Corrigi uma lacuna pequena: `admin-cancel-order` tinha só 1 dos 3
> chamadores reais listados (agora completo). Zero mudança a Edge Functions/config/deploy.

> Entrada **separada** por ordem do Danilo: isto é segurança, não é resto da missão
> `nunca-mais-travar`. Não pode ficar enterrado no relatório de ontem.

## O que se sabe (facto, não suposição)

Contado a 2026-08-01 em `supabase/functions/`:

- **53** Edge Functions locais (pastas com `index.ts`)
- **24** dessas **não declaram `verify_jwt` em nenhum ficheiro da sua pasta**
- 29 declaram

Como apareceu: por acaso, na prova de paridade da missão `nunca-mais-travar` — a tarefa de teste
era uma auditoria de Edge Functions. Não foi uma auditoria de segurança intencional, por isso o
número é fiável mas **a interpretação ainda não foi feita**.

## O que NÃO se sabe (e é o trabalho)

`verify_jwt` não declarado **não significa automaticamente "pública"** — o default da plataforma
e a configuração de deploy podem impor JWT à mesma. Antes de agir é preciso responder a:

1. Qual é o comportamento real quando `verify_jwt` não é declarado — default `true` ou `false`?
   Confirmar na config de deploy (`supabase/config.toml`), não por memória.
2. Das 24, quais **deviam** ser públicas por desenho? Há casos legítimos:
   `create-payment-intent` e `create-mbway-payment-intent` são `verify_jwt=false` **de propósito**
   (documentado no `CLAUDE.md`), porque o cliente chama-as antes de haver sessão.
3. Das restantes, alguma expõe leitura/escrita de dados sem autenticação?
4. Alguma toca 🔴 dinheiro (Stripe, wallet, tokens, refund, payouts)?

## Regras que se aplicam a este trabalho

- **Zona 🔴:** qualquer função que toque pagamentos entra em PROPOSE-ONLY. Preparar tudo,
  **não aplicar**, esperar o "vai" do Danilo.
- Não alterar `verify_jwt` de nenhuma função "por precaução": mudar de `false` para `true` numa
  função que o cliente chama sem sessão **parte o fluxo em produção**. Cada mudança precisa de
  saber quem chama.
- O agente dono é o `seguranca` (🟡), com `backend-supabase`. Gate do Juiz obrigatório.

## Primeiro passo sugerido (read-only, sem risco)

Listar as 24 por nome com: quem as invoca no app (`git grep functions.invoke`), se são chamadas
antes ou depois do login, e se tocam tabelas financeiras. Só isso já separa "legítimo" de
"a corrigir" sem tocar em nada.

## Proveniência

Descoberto durante a missão `nunca-mais-travar-2026-07-31` (prova de paridade da Parte 2).
Relatório dessa missão: `.claude/.ai/reports/FECHO-nunca-mais-travar-2026-08-01.md`.
Contagem também registada no `CLAUDE.md` (secção Edge Functions), que estava stale em 44.

---

## AUDITORIA DETALHADA (read-only, 2026-08-01) - as 24, uma a uma

Metodologia: git grep functions.invoke no app (lib/) e nas proprias Edge Functions, git grep
nas migrations por net.http_post(...functions/v1/NOME...) (chamada servidor-servidor de
triggers), e leitura do index.ts de cada funcao para (a) que tabelas/Stripe toca e (b) se
extrai e valida o Authorization header do PEDIDO (req.headers.get + auth.getUser) - que e
diferente de usar SUPABASE_SERVICE_ROLE_KEY so para o proprio cliente admin interno (isso nao
prova nada sobre quem chamou).

Aviso repetido de proposito: verify_jwt nao declarado no ficheiro nao e o mesmo que publica -
o valor efectivo em producao so se confirma na configuracao de deploy real (dashboard/CLI), que
este relatorio nao consultou (seria nao determinado se eu inventasse). O que ESTE relatorio
prova e o que o CODIGO faz na ausencia de qualquer verificacao de plataforma, ou seja, o pior
caso.

### Balde A - legitimo sem JWT (a propria funcao valida o utilizador por dentro)

| # | Funcao | Quem invoca | Toca dinheiro? | Antes de sessao? |
|---|---|---|---|---|
| 1 | admin-ai-assistant | admin_ai_assistant_screen.dart (painel admin) | indireto - tool de leitura de platform_settings (comissao/preco), sem escrita | nao |
| 2 | admin-cancel-order | admin_pending_actions_screen.dart + admin_orders_screen.dart + admin_order_service.dart | sim - Stripe refund | nao |
| 3 | admin-force-driver-logout | admin_driver_service.dart + skill force-driver-logout | nao | nao |
| 4 | cancel-order-with-choice | wallet_service.dart (cliente) | sim - charge/refund/wallet | nao |
| 5 | client-cancel-order | order_store.dart + payment_method_screen.dart (cliente) | sim - Stripe refund, wallet, ledger, comissao | nao |
| 6 | delete-account | profile_screen.dart (qualquer papel) | indireto - apaga bora_tokens do proprio utilizador; preserva refs Stripe 10 anos (fiscal) | nao |
| 7 | execute-cancellation | admin_cancellation_requests_screen.dart | sim - Stripe refund/wallet | nao |
| 8 | import-guarda-businesses | admin_businesses_screen.dart | nao | nao |
| 9 | pay-debt-standalone | wallet_service.dart (cliente) | sim - Stripe, wallet | nao |
| 10 | reprocess-refund | admin_cancellations_screen.dart | sim - Stripe refund | nao |
| 11 | tvde-payment | tvde_store.dart (cliente/motorista) | sim - Stripe charge/refund | nao |
| 12 | upload-receipt | receipt_upload_service.dart (estafeta/cliente) | nao diretamente (alimenta charge-extra a jusante) | nao |

Todas as 12 acima extraem Authorization do pedido e chamam userClient.auth.getUser() -
validacao real, criptografica, do utilizador. Veredito: A. verify_jwt=false e redundante
com a validacao interna, nao um buraco - mas manter as duas camadas (ligar verify_jwt=true
tambem) seria estritamente mais seguro e nao quebra nada, porque a validacao interna ja exige
exatamente o mesmo JWT.

### Balde B - suspeito, precisa de decisao do Danilo

| # | Funcao | Quem invoca | Toca dinheiro? | Antes de sessao? |
|---|---|---|---|---|
| 13 | notify-admin-reimbursement | RPC finalize_storeshopping_purchase_v2 (server-server, Authorization Bearer service_role_key - ver 20260511110100_finalize_storeshopping_purchase_v2.sql linhas 143-144) | indireto - so avisa que um Stripe/MBWay ja fechou, nao move dinheiro | n/a (nunca ha sessao de utilizador; e sempre o Postgres a chamar) |
| 14 | notify-chat-message | trigger _notify_chat_message_trigger AFTER INSERT em messages (20260511100100_notify_chat_message_trigger.sql linhas 36-40, mesmo padrao Bearer=service_role_key) | nao | n/a |
| 15 | notify-cleaner | trigger em 20260718003000_cleaning_notifications_and_equipment.sql (mesmo padrao) | nao | n/a |
| 16 | notify-client | outras Edge Functions (refund, execute-cancellation, admin-cancel-order, client-cancel-order) via admin.functions.invoke (service_role) + triggers TVDE/limpeza | nao (e so a mensageira) | n/a |
| 17 | notify-purchase-finalized | RPC finalize_storeshopping_purchase_v2 (mesmo trigger interno) | nao | n/a |
| 18 | notify-tvde-client | trigger 20260702120000_tvde_notify_client_on_status.sql | nao | n/a |
| 19 | notify-tvde-driver | trigger TVDE dispatch 20260626100002_tvde_phase2_dispatch.sql | nao | n/a |
| 20 | ocr-receipt | RPC finalize_storeshopping_purchase_v2 / fluxo de favor (server-server); recebe so order_id | indireto - nao move dinheiro mas alimenta charge-extra a jusante | n/a |
| 21 | robot-b | cron/Hermes (maestro-autonomia), nunca o app | indireto - o proprio prompt do robot-b proibe-se a si mesmo de tocar dinheiro (so propoe, nivel 3 = SO PROPOSTA) | n/a |
| 22 | update-products | pg_cron semanal (20260415120000_auto_update_products.sql), nunca o app; aceita market/pages/sleepMs/maxUpdates no body | nao diretamente (preco de catalogo, nao pagamento) | n/a |

Porque e Balde B, nao A: nas 9 funcoes notify-*/ocr-receipt, o codigo nao verifica NADA de
quem chamou - SUPABASE_SERVICE_ROLE_KEY so aparece a criar o cliente Postgres interno da
propria funcao, nunca a comparar contra o que o chamador enviou. E os proprios triggers SQL
ja mandam Authorization Bearer service_role_key (confirmado no codigo das migrations) - ou
seja, ligar verify_jwt=true nestas 9 muito provavelmente nao quebra o unico caminho legitimo
conhecido, porque a chave de servico e um JWT valido assinado pelo projeto. Hoje, sem essa
camada, qualquer pedido POST anonimo a internet (sem token nenhum) consegue: disparar push
falso para qualquer conversa/cliente/motorista/limpador, ou obrigar a funcao a reprocessar OCR
de um talao alheio (custo de API Gemini + reescreve dados).

robot-b e update-products sao diferentes dos outros 8: nao tem um utilizador de todo - sao
cron/loop interno. Aqui a pergunta certa nao e qual utilizador chama mas qual credencial o
cron usa - se for a service_role_key (mesma logica), ligar verify_jwt=true tambem nao quebraria
nada e fecharia a porta a qualquer pessoa disparar 90 paginas de scraping ou o motor autonomo
a vontade, de fora.

Recomendacao (proposta, nao aplicada - zero mudanca de codigo/config feita): confirmar que os
10 caminhos legitimos acima realmente mandam o service_role_key, e se sim, ligar
verify_jwt=true nestas 10 funcoes e uma correcao de seguranca de baixo risco. Isto e uma
decisao de seguranca, nao de dinheiro - mas envolve Edge Functions, por isso fica so proposto.

### Balde C - claramente devia exigir JWT (achados mais serios)

| # | Funcao | Quem invoca | Toca dinheiro? | Antes de sessao? |
|---|---|---|---|---|
| 23 | register-partner | auth_store.dart linha 1333 (Step 2 do cadastro de parceiro, logo apos o signUp) | nao diretamente, mas grava restaurants (decide comissao futura do parceiro) | quase - ha um JWT (o do signUp acabado de fazer), mas a validacao esta quebrada (ver abaixo) |
| 24 | upload-restaurant-asset | register_partner_screen.dart, admin_partner_detail_screen.dart, admin_service_provider_detail_screen.dart, partner_manage_staff_screen.dart - todos com sessao ativa | nao | em parte - chamada durante o cadastro do parceiro, antes da aprovacao, mas com sessao ativa |

register-partner - o achado mais serio dos 24. O codigo (index.ts linhas 62-83) decodifica o
payload do JWT a mao (atob dos parts[1] + JSON.parse) para ler payload.sub como user_id - e
NUNCA verifica a assinatura. Nao ha chamada a auth.getUser() nem qualquer verificacao
criptografica. Com verify_jwt=false na plataforma, um pedido com um JWT de forma valida (3
partes separadas por ponto) mas assinatura invalida/forjada, com um sub a escolha do atacante,
passa por este codigo sem ser barrado - risco de registar um restaurante em nome de um user_id
alheio. verify_jwt=true a nivel de plataforma resolveria isto de graca (a verificacao da
assinatura acontece ANTES do codigo da funcao correr) sem precisar de tocar neste ficheiro.

upload-restaurant-asset - zero autenticacao, upload de ficheiro arbitrario. O codigo
(index.ts linhas 15-45) aceita restaurantId + kind + fileBase64 no body e grava diretamente no
bucket - sem extrair Authorization, sem getUser(), sem confirmar que quem chama e dono desse
restaurantId. Hoje, com verify_jwt=false, qualquer pedido POST anonimo com um restaurantId
existente consegue sobrescrever a foto/logo/capa desse parceiro. Precisa de, no minimo,
verify_jwt=true + confirmar que o user_id do JWT e dono do restaurantId (mesmo padrao
dual-owner-column ja usado noutras RPCs - ver restaurants.user_ / user_id).

---

## RESUMO - contagem por balde

- Balde A (legitimo, validacao interna real): 12 - admin-ai-assistant, admin-cancel-order,
  admin-force-driver-logout, cancel-order-with-choice, client-cancel-order, delete-account,
  execute-cancellation, import-guarda-businesses, pay-debt-standalone, reprocess-refund,
  tvde-payment, upload-receipt.
- Balde B (suspeito, decisao do Danilo - provavelmente seguro ligar verify_jwt=true): 10 -
  notify-admin-reimbursement, notify-chat-message, notify-cleaner, notify-client,
  notify-purchase-finalized, notify-tvde-client, notify-tvde-driver, ocr-receipt, robot-b,
  update-products.
- Balde C (claramente devia exigir JWT - achados de seguranca reais): 2 - register-partner
  (JWT decodificado sem verificar assinatura) e upload-restaurant-asset (zero autenticacao,
  upload arbitrario).

Nada foi alterado. Isto e leitura + analise; qualquer correcao (ligar verify_jwt, corrigir
register-partner para usar getUser(), adicionar dono-check ao upload-restaurant-asset) e
trabalho novo, para o Danilo priorizar - envolve Edge Functions e autenticacao, por isso o
agente dono seria seguranca + backend-supabase, com Gate do Juiz obrigatorio antes de aplicar.
