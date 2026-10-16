# Segurança das chaves da Supabase — 15/10/2026

Missão `sistema-sem-travas-2026-10-15`, bloco 0. Projeto Supabase `ojykpzwqrtusfeakzrna`.

## O problema, em simples

O repositório `nilofulfarotuga-hue/bora-app-cloud` está **público** (confirmado pela API do GitHub a
15/10, `visibility: public`). Três scripts antigos tinham escrita a **chave secreta do servidor**
(`service_role`), a que passa por cima de todas as regras de segurança do banco:
`docs/e2e-web-2026-07-21/create-demo.sh`, `docs/e2e-web-2026-07-21/setup-accounts.sh` e
`scripts/insert_mercadona.ps1`. Como o repositório é público, essa chave tem de ser tratada como
**já roubada**. O `temp_schema_dump.sql` já não está no repositório desde o commit `f8534550`, mas
continua no histórico.

## O que já ficou feito (15/10)

| Passo | Estado | Prova |
|---|---|---|
| Tirar as chaves do código | ✅ feito | commit `40d690c4` "chore: segredos fora do código"; `git grep` + descodificação dos JWT: 0 ficheiros com `service_role` |
| App com a chave publicável | ✅ pronto, sai no próximo build | `.github/scripts/chave_publica_supabase.py` corre logo a seguir a cada `base64 --decode > .dart_defines` (Android ×2, Web ×1, iPhone ×2) |
| Histórico do git | ⏸️ não reescrito (regra) | o histórico continua a ter a chave antiga até as chaves legadas serem desligadas |
| Fechar o repositório | 🔴 parado — decisão de dinheiro | ver abaixo |
| Chave secreta nova | 🔴 parado — partiria produção | ver abaixo |

### Porque é que a troca para a chave publicável é segura (testado ao vivo a 15/10)

- A biblioteca da app (`supabase_flutter`, o CI resolve a 2.18.x) aceita a chave nova desde a 2.13.0.
- Testes feitos contra o projeto, só leituras: REST, Storage, Auth e Realtime respondem 200/ok com a chave
  nova. Funções com `verify_jwt=true` aceitam-na no `apikey` e também com `Authorization: Bearer` igual ao
  `apikey` (é o que `notification_service.dart` faz) — 200.
- Zero linhas de Dart mudadas: a app continua a ler `SUPABASE_ANON_KEY`; só o valor muda no build.
- Limite conhecido: uma ligação Realtime **sem utilizador** dura no máximo 24 h e depois a app volta a ligar
  (o `OrderStore` já se volta a ligar sozinho).
- Para voltar atrás: reverter o commit que chama `chave_publica_supabase.py`.

## 🔴 Parado 1 — fechar o repositório (decisão de dinheiro, só o Danilo)

Nos últimos 30 dias o CI gastou **~4 977 minutos de Mac** (62 compilações do iPhone) e **~4 400 minutos
de Linux** (Android, Web, testes). Num repositório **público** isto é grátis. Num **privado** o plano
gratuito dá 2 000 minutos por mês e cada minuto de Mac conta como 10 — seriam ~55 000 minutos.
Ou seja: fechado, o CI **pára ao fim de ~1 dia**, ou passa a custar **~300 dólares por mês**.

Opções para o Danilo escolher:
1. **Fechar e pagar** os minutos (pôr limite de gasto no GitHub).
2. **Fechar e mudar o CI**: Android e Web passam a compilar na VPS (grátis), o iPhone só quando ele pedir.
   Dá trabalho (1 missão) e a VPS só aguenta uma coisa pesada de cada vez.
3. **Deixar público** até as chaves legadas estarem desligadas (aí já não há segredo nenhum no histórico
   que sirva a alguém).

Clique, depois da escolha: <https://github.com/nilofulfarotuga-hue/bora-app-cloud/settings> → Danger Zone →
Change visibility.

## 🔴 Parado 2 — chave secreta nova "bora-server-2026-10-15"

A ordem dizia: criar a chave nova e pô-la no segredo `service_role_key` do cofre do banco. **Isso partiria
produção**:

- 58 funções do banco leem `service_role_key` do cofre e usam-na como `Authorization: Bearer` para chamar
  25 Edge Functions: `auto-refund-order`, `refund`, `tvde-payment`, `payments-reconciler`, `notify-driver`,
  `notify-client`, `notify-partner`, `notify-cleaner`, `settlement-receipt`, `weekly-closeout-digest`, etc.
- A chave nova (`sb_secret_...`) **não é um JWT**. As funções com `verify_jwt=true` recusam-na, e o `refund`
  confirma `role=service_role` dentro do JWT — recusaria também. Partia reembolsos, pagamentos TVDE e avisos.
- Criar a chave nova **sem desligar a antiga não fecha a fuga** — a roubada continua a funcionar.
- Além disso, copiar uma chave secreta é um passo que as nossas regras deixam ao Danilo.

## O plano certo para fechar a fuga (por ordem)

1. ✅ Código limpo (feito).
2. ⏳ App com a chave publicável nas 3 lojas (sai neste envio; Android e Web em minutos, iPhone pela Apple).
3. ⏳ Esperar que a maioria das instalações tenha a versão nova. Medir: `drivers.last_platform` / versões
   no painel. Quando for a maioria, subir `app_min_supported_version_code` e
   `app_min_supported_version_code_ios` em `platform_settings` para o primeiro build com a chave nova — o
   `app_update_service.dart` já obriga a atualizar.
4. ⏳ **Migrar os servidores** para a chave secreta nova — é trabalho de zona vermelha (mexe em
   `refund`, `stripe-webhook`, `dispatch-engine`), por isso só proposta:
   - Edge Functions chamadas pelo banco passam a `verify_jwt=false` e verificam elas próprias o cabeçalho
     `apikey` contra a chave secreta nova (é o caminho que a Supabase documenta).
   - O cofre ganha um segredo novo (ex.: `bora_server_secret`) e as 58 funções passam a enviá-lo no `apikey`.
   - `dispatch_anon_jwt` (cofre) e as 8 funções que usam `_dispatch_jwt()` passam para a chave publicável.
   - VPS (carteiro, Hermes), GitHub Secrets e `.env` do PC recebem a chave nova.
5. ⏳ **Só então** desligar as chaves legadas (Supabase → Project Settings → API Keys → Legacy API keys →
   Disable). É este clique que mata a chave roubada. **Fica para o Danilo/Claude.ai, com data.**
6. Depois de 5, o histórico do git deixa de ter segredos vivos — e o repositório pode ficar público ou privado
   sem pressa.

## Quem depende hoje da chave antiga (não desligar antes do passo 4)

- Base de dados: `vault.service_role_key` (58 funções), `vault.dispatch_anon_jwt` (= chave anon antiga,
  lida por `_dispatch_jwt()`, 8–9 funções, incluindo os gatilhos de `tvde_rides`).
- VPS: scripts do carteiro e da caça de clientes leem a sua própria cópia.
- Todas as apps instaladas antes deste envio.
- Os 5 ficheiros de migrations antigas com a chave anon escrita (registo histórico, já aplicados).

## Continuação — 16/10/2026

O "Parado 2" foi desmontado na missão `chave-nova-16-10`: a chave secreta nova já existia, a
plataforma já a injeta nas Edge Functions (mesmo nas variáveis com nome antigo), o portão aceita-a
em `Bearer` e em `apikey`, e por isso **não é preciso desligar o `verify_jwt`** como este plano
previa. O que se mediu, o desenho novo (`_shared/chaves.ts`, `chaves-semear`, `vault.bora_server_secret`),
o estado função a função e o runbook da troca estão em **`docs/CHAVES-2026-10-16.md`**.
Os passos 3, 5 e 6 acima continuam válidos (esperar pela maioria das instalações, desligar as
legadas, repositório público/privado).
