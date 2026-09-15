# Relatório — Bug "Ecrã Serviços vazio" (CLIENTE)

**Data:** 2026-06-09 · **Modo:** PROTECÇÃO TOTAL (CEO-AI + prompt-blindado-validator ✅)
**Projeto Supabase:** `ojykpzwqrtusfeakzrna` · **Branch:** autonomous-night-2026-04-29
**Build:** versionCode +267 → **+268**

---

## 1. Prova empírica (anon REST, query EXACTA da app)

`GET /rest/v1/service_providers?select=*&is_online=eq.true&approval_status=eq.approved&order=avg_rating.desc.nullslast&limit=100`
com a **anon key** do `.dart_defines`:

```
HTTP 200  rows=1   name='Barbearia Nobre'
  avg_rating  = null   (NoneType)   → toD(null) = null, NÃO rebenta
  ratings_count = 0    (int)
  lat = 40.537 (float) · lng = -7.268 (float)
```

→ **A API devolve a barbearia** e o `ServiceProviderModel.fromSupabase` **parse-ia
esta linha sem erro**. Com o código actual do repo, o ecrã mostraria a barbearia.
Logo o empty-state observado vem de **(a)** APK a correr código mais antigo, ou
**(b)** a sessão do device a receber 0 linhas. Só logs on-device distinguem.

## 2. Bugs latentes REAIS corrigidos (classe "lista esvazia toda")

A hipótese do Danilo ("providers chega à store mas é filtrado para 0") está certa
na sua essência: o parse era **all-or-nothing**.

| # | Ficheiro | Antes | Depois |
|---|---|---|---|
| 1 | `models/service_provider_model.dart:45` | `toD(v) => (v as num).toDouble()` | aceita **num OU String** (`double.tryParse`). PostgREST serializa `numeric` **não-nulo** como **String** → no dia em que uma barbearia tiver 1ª avaliação, `avg_rating="4.5"` rebentava `as num` e esvaziava a lista TODA |
| 2 | `stores/services_store.dart` `fetchProviders` | `.map(fromSupabase).toList()` (se 1 linha rebenta, perde-se a lista inteira) | parse **linha-a-linha** com try/catch — 1 linha malformada nunca esvazia a lista |
| 3 | idem + `services_category_screen.dart` build | — | `debugPrint('[SERVICOS] …')` com `raw=`/`parsed=`/`providers=` |

> `lat`/`lng` são `float8` (JSON number) e `ratings_count` é `int4` → OK. Só
> `avg_rating` (`numeric`) é a armadilha — hoje inofensiva por estar `null`,
> perigosa assim que houver ratings.

## 3. Passo de diagnóstico on-device (resolve em 1 run)

Após rebuild, abrir **Serviços** e ler o logcat por `[SERVICOS]`:
- `raw=1 parsed=1` + ecrã vazio → problema de **render/estado** (não fetch).
- `raw=0` → a **sessão do device** recebe 0 linhas (RLS/JWT/env) — investigar a
  sessão Supabase activa no cliente.
- `parsed=0` com `linha ignorada (parse)` → a linha rebenta no device (build
  antigo / dados diferentes) — o fix #1/#2 já a torna resiliente.

## 4. Verificação & âmbito
- `flutter analyze` (3 ficheiros) → **No issues found**.
- Mudança **100% client-side Dart** (parse + logs). **Zero** DB/RLS/Stripe/pricing/
  dispatch/tokens. Validation Gate **não aplica**.
- Ecrã não filtra por `isOpenNow`/distância/`photoUrl`/categoria — confirmado por
  leitura integral de `services_category_screen.dart` (sem `.where`, sem condicional
  de render que esconda linhas).

## 5. SEPARADO (aceite, a aguardar OK) — `permission denied for table users`
RLS de `ledger_entries`/`user_balance_snapshots`/`storage.objects` admin referenciam
`auth.users` directamente → falham para não-admin (parceiro/storage). Migration
`auth.users → is_admin()` pronta a aplicar via MCP quando aprovares. **Não** afecta
o ecrã Serviços.
