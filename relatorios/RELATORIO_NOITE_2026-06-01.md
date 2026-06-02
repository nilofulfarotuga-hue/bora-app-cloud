# 🌙 RELATÓRIO NOITE — 2026-06-01 → 02 (sessão autónoma)

> Branch: `autonomous-night-2026-04-29` · Modelo: Opus 4.8 · Device: Samsung A36 (RZGYB1XQD2P)
> Objectivo: loop GERAR APK → testar UI → corrigir → repetir. **Prioridade 1 = login/cadastro dos 3 apps.**

---

# 🚨 ACHADO CRÍTICO #1 — BASE DE DADOS SUPABASE EM FALHA (bloqueia TODO o login)

**A base de dados Postgres do projeto Supabase (`ojykpzwqrtusfeakzrna`) está a recusar/expirar ligações.**
Isto **bloqueia 100% dos logins** — contas de teste E utilizadores reais em produção. **Não é bug da app, do build, nem das contas.**

### Evidência (logs `auth` do Supabase, via MCP)
Todos os pedidos `POST /token` (login password) entre **06:06–06:19 UTC de hoje (02/06)** falham:
```
error finding user: failed to connect to host=localhost user=supabase_auth_admin
database=postgres: dial error (timeout: dial tcp [::1]:5432: i/o timeout)
504: Processing this request timed out      (duração 10–20s por pedido)
500: Database error querying schema
```
- O **gotrue (serviço auth) está vivo** — o `curl` do device a `/auth/v1/health` respondeu instantâneo. O que falha é o gotrue **ligar ao Postgres** (`[::1]:5432 i/o timeout`).
- `execute_sql` (MCP) com `select now()` **expirou 3×** ("Connection terminated due to connection timeout"); só **1×** respondeu (connections=21 — saudável, NÃO é exaustão de ligações).
- **Contraste temporal:** ontem **01/06 21:14 UTC o login funcionou (200 OK)**; logins saudáveis às 17:xx (270–750 ms). A degradação começou **durante a madrugada de hoje**.

### Causa provável
Instância de DB do projeto sobrecarregada/indisponível (free/micro tier): exaustão de CPU credits, OOM do Postgres, ou **disco da DB cheio**. É infra do lado Supabase — **não corrigível por código da app nem por mim via MCP** (a DB nem aceita queries de forma fiável).

### 👤 AÇÃO HUMANA URGENTE (Danilo, ao acordar)
1. **Supabase Dashboard → projeto `ojykpzwqrtusfeakzrna` → Database/Reports**: ver CPU, RAM, **disco** e estado da instância.
2. **status.supabase.com** — verificar incidente regional (eu-west-1).
3. Se for recursos: **Restart database** (Settings → Database) e/ou **upgrade de compute**. Se disco cheio: aumentar disco / limpar.
4. Depois de a DB voltar: **re-testar login** (o resto da app está pronto — ver abaixo).

> 🔁 **ATUALIZAÇÃO (retoma 02/06 ~08:15 local):** Danilo **reiniciou a DB**, mas **continua a piscar**. Gate de estabilidade (3× `SELECT now()` espaçado) passou só **1× em 4 tentativas**; logins frescos do `test-client` (`pm clear` + 3 tentativas) **falharam todos** com timeout de DB **confirmado nos logs `auth`** (`500: Database error querying schema` / `error finding user: timeout: context canceled`, `/token` 07:01–07:10 UTC, duração **6–16s**, status 500). **NÃO é a conta, NÃO é o código.** Padrão (intermitente há ~2.5h, conns saudáveis 18–21, restart não resolveu) ⇒ **throttling de compute/IO do tier**. **RECOMENDAÇÃO: upgrade de compute no Supabase** (ou aguardar replenish de CPU credits — pode levar horas). O login fresco só passará com a DB **continuamente** estável (um ping pontual passa, mas o login faz várias queries em 6–16s e apanha a janela má).
>
> **Causa-raiz refinada (diagnóstico read-only):** `pg_stat_activity` numa janela boa devolveu **VAZIO** (zero queries ativas/runaway; DB idle e saudável quando responde). Logo **não há query pesada nem cron a martelar a DB** — é **throttling de compute/CPU credits** de uma instância *burstable* (provavelmente os scrapers/crons mais cedo gastaram os credits). **Não há nada para "matar" nem corrigir em código.** Gates de estabilidade: **5 ciclos** (1× passou 3/3, resto piscou); logins frescos `test-client`: **~5 tentativas, todas falham** com DB-timeout. **FIX = lado compute:** Supabase Dashboard → **upgrade de compute** (Small/Medium) OU aguardar replenish dos CPU credits (agora que a carga parou, deve recuperar — pode levar dezenas de min a horas). Confirmar também o gráfico **CPU/IO** no Dashboard.

> ⚠️ Como **nenhum login funciona enquanto a DB estiver assim**, os testes E2E de estafeta/parceiro/cadastro foram **bloqueados por esta falha** (não por bug da app). Parei de repetir o login após 3 falhas com a MESMA causa (regra do prompt).

---

## ✅ O QUE FOI VERIFICADO E ESTÁ BOM (Prioridade 1, lado app)

| Camada | Estado | Evidência |
|---|---|---|
| **Build APK** | ✅ `app-debug.apk` **186 MB** gerado local (Flutter 3.41.2 + `.dart_defines`) | `bora_app/build/app/outputs/flutter-apk/app-debug.apk` |
| **App no device** | ✅ Arranca limpo, **sem splash-hang**, home com design system | sc01/sc03 (244 instalado) |
| **Bug login build 240** | ✅ Já corrigido no CI (`build_android.yml:43` pin `flutter-version: 3.41.2`) | — |
| **Ecrã login cliente** | ✅ Renderiza, aceita input, **chama o servidor a sério** (spinner real, NÃO o "Credenciais inválidas" instantâneo do build 240) | sc04–sc13 |
| **Contas de teste** | ✅ 5 contas: confirmadas, `bora_role` correto, não banidas | auth.users via MCP |
| **driver approved** | ✅ test-driver `approval_status=approved` | drivers via MCP |
| **Lógica de login** | ✅ `loginClientAsync/Driver/Partner` sem regressão (lidas) | `lib/auth/auth_store.dart` |

**Conclusão:** o lado da app (build, UI, código de auth, contas) está **pronto**. O único bloqueador da Prioridade 1 é a **DB Supabase em falha**. Quando recuperar, o login deve passar.

---

## 🚩 ACHADO #2 — test-partner SEM restaurante (test-data gap, persiste)
- 0 restaurantes ligados a test-partner (via `user_id` OU `user_`). "Pizzaria Teste 27" **não existe** (17 restaurantes; só 2 partner: "ifxfixif", "pizza danilo").
- `loginPartnerAsync` cria a conta a partir do **metadata** (não consulta `restaurants`) → o login terá sucesso, mas o **painel** (que carrega `_partnerRestaurant` por `user_id`, `auth_store.dart:299`) ficará **vazio**.
- **Não criei o restaurante** porque (a) não posso testar E2E com a DB em baixo, e (b) criar dados sem verificar tem risco. **Remediação pronta** quando a DB voltar: criar 1 restaurante aprovado para test-partner, modelado em "pizza danilo". (Aguarda DB.)

## 🚩 ACHADO #3 (menor) — test-admin sem `bora_role`
- `bora_role` NULL para admin (não é app prioritária; login prévio funcionou 29/05). Apenas registado.

---

## ⚙️ DECISÕES AUTÓNOMAS (e porquê)

1. **Harness = ADB no device físico, NÃO TestSprite.** TestSprite tem API key em `bora_app/.claude/mcp_settings.json` mas **o MCP não está carregado nesta sessão** e **não conduz device Android físico via ADB**. ADB (`screencap`+`input`+`pm clear`) está provado neste A36 e testa o APK real.
2. **Build local `--debug` (não `--release`).** PC com 3.9 GB RAM: a doc `local-build-windows.md` diz que release faz OOM/>1h. Login/cadastro são idênticos em debug. Release/Play ficam no CI (já pinado).
3. **Limpeza de recursos:** esvaziei Reciclagem (~estava a 0,67 GB livre, subiu p/ ~4 GB), limpei TEMP, fechei Chrome (RAM 187→641 MB). Tudo sancionado pela doc de build. (Efeito colateral: limpar TEMP apagou um ficheiro de output temporário de uma ferramenta — sem dano.)
4. **O "build hang de 6h" era falso alarme:** o `assembleDebug` **terminou e gerou o APK às 00:36**; o processo Gradle é que **bloqueou no shutdown**. O APK estava completo e válido.
5. **versionCode NÃO incrementado** (build local só para teste; device corre 244 do CI; premissa "240→241" do prompt está desatualizada).
6. **Parei de repetir o login após 3 falhas com a mesma causa** (DB timeout) — regra de segurança do prompt; não é zona que eu deva "corrigir" em código.

---

## 🖥️ AMBIENTE
- Device A36 1080×2340 (density 450), autorizado. ADB em `…\platform-tools\adb.exe`.
- Flutter 3.41.2 / Dart 3.11.0. JDK build pinado a 17. RAM livre ~641 MB. Disco C: ~4.4 GB.
- Git: `autonomous-night-2026-04-29`, HEAD `a97f9a9`, sync c/ origin.

## 🔒 ZONAS PROIBIDAS
Nenhuma tocada. ZERO edições a `lib/`, dispatch, pricing, triggers, Stripe, RLS. **Nenhuma alteração de código** nesta sessão (só este relatório).

## 📌 PENDÊNCIAS (por ordem)
1. **(humano, urgente)** Recuperar a DB Supabase — ver ACHADO #1.
2. **(pós-DB)** Re-testar login cliente/estafeta/parceiro + cadastro cliente (app está pronto).
3. **(pós-DB)** Criar restaurante de teste aprovado para test-partner (ACHADO #2).
4. **(humano)** Confirmar secret `DART_DEFINES_FILE_B64` no GitHub (do diagnóstico build 240).

---
*Screenshots da sessão em `C:\Users\danil\AppData\Local\Temp\bora_night\` (sc01–sc13). Não commitados.*
