# 📐 PLANO (SÓ ANÁLISE) — Distância de estrada real vs Haversine
> Data: 2026-05-31 · Modo: PROTECÇÃO TOTAL · **NADA foi editado** (análise read-only).
> Zona sensível tripla: pricing + create_order + Edge Function. Requer aprovação do Danilo antes de qualquer implementação.

---

## 0. CONFIRMAÇÕES DE FACTO (verificado na DB/código reais)

| Facto | Estado | Prova |
|---|---|---|
| App é autoridade da distância | ✅ confirmado | `quote_order_pricing` e `create_order`: `v_distance_km := COALESCE((p_input->>'distance_km')::NUMERIC, 1)` |
| App calcula Haversine | ✅ | `cart_store._recalculateDistance()` usa `const Distance().as(...)` (linha reta) |
| `create_order` é autoritativo do preço | ✅ | linha 188 chama `pricing_calculate(...v_distance_km...)`, grava `distance_km` na orders (259/273) |
| **Servidor JÁ recebe e grava coordenadas** | ✅ **importante** | `create_order` extrai `pickup_lat/lng`+`dropoff_lat/lng` (73-76), valida não-nulos (92-99), insere na orders (266/282) |
| `quote_order_pricing` recebe coords? | ❌ NÃO | só lê service_type/distance_km/subtotal/etc — **não** lê coords |
| Tabela orders tem colunas de coords | ✅ | `pickup_lat/lng`, `dropoff_lat/lng` (numeric), `distance_km` (numeric), `driver_lat/lng` |
| Dispatch usa `distance_km` da order? | ❌ NÃO (DB) | `bora_dispatch_maintenance`/`fn_dispatch_on_calling_driver`/`invoke_dispatch_engine` fazem HTTP mas **não referenciam distância** |
| Edge `dispatch-engine` usa que distância? | ⚠️ a confirmar | usa proximidade **driver→pickup** (batching ≤200m/800m), conceito diferente da distância pickup→dropoff do pricing |
| **Secret Google no Supabase** | ❌ **NÃO encontrado** | Nenhuma Edge Fn lê chave Maps/Directions. Secrets existentes: `GEMINI_API_KEY`, `SUPABASE_*`, `STRIPE_*`, `FIREBASE_*`, `RESEND_API_KEY`. A chave Google de Directions vive só como **dart-define do Flutter** (`googleApiKey`) |

> 🔴 **DÚVIDA #1 (bloqueante):** o prompt diz "a chave Google já está nos secrets". **Não está referenciada por nenhuma Edge Function.** Além disso, a chave do Flutter é tipicamente **restrita ao Android (SHA-1 + package)** e **falha em chamadas server-side** (o servidor não tem assinatura de app). Quase de certeza é preciso uma **chave Google separada server-side** (sem restrição de app, restrita por IP), adicionada como secret novo (ex. `GOOGLE_MAPS_SERVER_KEY`). **Confirmar com o Danilo antes de implementar.**

---

## 1. MAPEAMENTO COMPLETO DO FLUXO DE DISTÂNCIA

**Onde a app calcula:**
- `cart_store.dart:378 _recalculateDistance()` → Haversine pickup→dropoff; guarda em `_distanceKm` (default 1 km).
- Disparado por `configureSession()` (forms encomenda/compra) e `updateDeliveryAddress()`.

**Onde a app envia (call sites):**
- **Estimativa:** `cart_store.dart:194` mete `'distance_km': _distanceKm` no `cartInput` → `:207` `.rpc('quote_order_pricing', {p_input: cartInput})`.
- **Pedido real:** `order_store.dart:538` e `:801` metem `'distance_km': resolvedDistance` → `:866` `.rpc('create_order', {p_input: rpcInput})`.
- `order_model.dart:496` serializa `distance_km` no `toSupabase`.

**Quem depende de `distance_km`:**
- `pricing_calculate` (delivery fee €/km acima de 4 km + driver earnings).
- `quote_order_pricing` (estimativa UI).
- `create_order` (preço cobrado + grava na orders).
- **UI leitura:** `order_model.dart:405`, `foreground_service.dart:323`, `order_store.dart:2413` (só mostram).
- **Dispatch:** ❌ não usa `distance_km` da order (confirmado). Usa proximidade driver↔pickup na Edge `dispatch-engine`.

---

## 2. DESENHO PROPOSTO (server-authoritative, anti-fraude)

### Decisão de desenho (resposta à pergunta do prompt)
**RECOMENDADO: (a) Edge Function orquestradora** que calcula a distância de estrada server-side e chama as RPCs com o valor de confiança.
**REJEITADO: (b) cliente chama Edge Fn que devolve a distância e depois manda às RPCs** — porque o cliente continua a ser o **mensageiro** da distância; um cliente malicioso chamaria `create_order` direto com distância falsa. (b) só seria seguro com revalidação/assinatura — mais complexo e frágil.

### Arquitetura recomendada
1. **Nova Edge Function `order-pricing`** (verify_jwt=true) com `action: 'quote' | 'create'`:
   - Recebe `pickup_lat/lng`, `dropoff_lat/lng` + restante input.
   - **Calcula a distância de estrada** via Google Routes/Directions (chave server-side) — **ignora** qualquer `distance_km` vindo do cliente.
   - Consulta/escreve **cache** (ver §3).
   - Chama a RPC existente (`quote_order_pricing` ou `create_order`) **com o `distance_km` de confiança** + as coords.
2. **`quote_order_pricing`** passa a **receber coords** (hoje não recebe) — ou, mais simples, a Edge Fn injeta o `distance_km` já calculado e a RPC mantém-se quase igual.
3. **Anti-bypass (a decisão dura):** para o cliente não poder chamar as RPCs direto com distância falsa, há 2 níveis:
   - **Fase 1 (não-disruptiva):** RPCs continuam abertas mas a app nova deixa de mandar distância como autoridade; orders ganham coluna `distance_source` (`road` | `haversine_fallback` | `client_legacy`) para auditar.
   - **Fase 2 (lock):** `REVOKE EXECUTE` de `create_order`/`quote_order_pricing` a `authenticated`, `GRANT` só a `service_role` → **só a Edge Fn** (service_role) cria/estima. Fecha a fraude de vez. ⚠️ obriga TODA a app a passar pela Edge Fn.
4. **App deixa de ser autoridade:** Flutter envia **coords** (já as tem) e **mostra** o `distance_km`/preço que a Edge Fn devolve no `quote`. Para de calcular/enviar Haversine como verdade (pode manter Haversine só como hint visual offline).

---

## 3. CUSTO E CACHE (é dinheiro)

- **Custo Google:** Routes API ≈ **$5 / 1000 chamadas**. O `quote` é chamado **a cada alteração do carrinho** (reativo) → sem cache seriam **5-15 chamadas por sessão de pedido**.
- **Cache obrigatória:** tabela nova `road_distance_cache(pickup_key TEXT, dropoff_key TEXT, distance_km NUMERIC, computed_at TIMESTAMPTZ, PRIMARY KEY(pickup_key,dropoff_key))`.
  - `key` = lat/lng arredondados a **4 casas decimais** (~11 m) → `"40.5373,-7.2655"`.
  - TTL sugerido **30 dias** (estradas mudam pouco).
  - Fluxo: Edge Fn → procura cache → hit devolve; miss chama Google + grava.
- **Reuso quote→create:** a Edge Fn no `create` reusa a cache populada no `quote` final → **0 chamadas extra** no create.
- **Estimativa realista por pedido (com cache + debounce):** **~1 chamada Directions** por par de coords único. Com debounce no cliente (só calcular quando o endereço é **selecionado**, não a cada tecla), aproxima-se de 1/pedido.

### Fallback (resiliência)
- Se Directions falhar/timeout/sem rede no servidor: **cair para Haversine × fator** (`road_distance_fallback_factor`, default **1.3**, configurável em `platform_settings`) e marcar `distance_source='haversine_fallback'`.
- **Nunca bloquear** a criação do pedido por falha da Directions.

---

## 4. MIGRAÇÃO E SEGURANÇA (sem quebrar apps instaladas)

- **Apps antigas** continuam a chamar `create_order`/`quote_order_pricing` direto com Haversine. Plano em fases:
  - **Fase 1:** Edge Fn nova + cache + `distance_source` + app nova usa Edge Fn. RPCs **continuam abertas** (apps antigas funcionam com Haversine — subcobrança tolerada no interim).
  - **Fase 2 (após adoção alta da app nova):** `REVOKE` RPCs de `authenticated` → força toda a gente pela Edge Fn. Apps muito antigas deixam de criar pedidos (forçar update via store).
- **Servidor deve ignorar `distance_km` do cliente** assim que a Edge Fn estiver a injetar o valor de confiança. Recomendo: na Fase 1 a Edge Fn **sobrepõe** o `distance_km`; as RPCs mantêm o `COALESCE` só para o caminho legado.
- **Dispatch (zona proibida):** confirmado que as funções DB de dispatch **não leem `distance_km`**. ⚠️ Antes de implementar, **confirmação read-only de 5 min** do `dispatch-engine` (TS) para garantir que a distância de batching (driver→pickup) é independente — **se afetar, PARAR e reportar**. Risco avaliado **baixo**.

---

## 5. DIVISÃO DE TRABALHO PROPOSTA

| Componente | Quem | O quê |
|---|---|---|
| **DB/RPC** (via MCP, Claude.ai) | Claude.ai | (1) `quote_order_pricing`: aceitar `distance_km` já de confiança (ou coords). (2) `create_order`: idem + coluna `orders.distance_source`. (3) tabela `road_distance_cache`. (4) settings `road_distance_fallback_factor`, `road_distance_enabled`. (5) Fase 2: `REVOKE/GRANT` das RPCs. |
| **Edge Function nova** | Claude Code | `order-pricing` (action quote/create): coords→Directions→cache→chama RPC com distância de confiança + fallback Haversine×fator. Secret Google server-side. |
| **Flutter** | Claude Code | Parar de enviar `distance_km` como autoridade; enviar coords; chamar a Edge Fn em vez das RPCs direto; mostrar o `distance_km`/preço devolvido. Manter Haversine só como hint visual. |

**Ordem sugerida:** DB (cache+coluna+settings) → Edge Fn → Flutter → testar → Fase 2 (lock RPCs).

---

## LEMBRETE ADMIN
- Adicionar a `platform_settings` (já editável dinamicamente em `admin_platform_settings_screen`): `road_distance_enabled` (on/off, kill-switch), `road_distance_fallback_factor` (default 1.3).
- Útil mostrar `distance_source` no detalhe de pedido admin (auditar quantos pedidos caíram em fallback) — **registar como melhoria**, não construir agora.

---

## DÚVIDAS A RESOLVER ANTES DE IMPLEMENTAR
1. 🔴 **Chave Google server-side** — não existe secret referenciado; a chave do Flutter é provavelmente Android-restrita. Confirmar/criar `GOOGLE_MAPS_SERVER_KEY` (Routes/Directions ativo, restrita por IP). **Bloqueante.**
2. **Routes API vs Directions API** — Routes API (computeRoutes) é a recomendada/mais barata hoje; confirmar qual ativar.
3. **Fase 2 lock das RPCs** — confirmar apetite para forçar update das apps antigas (anti-fraude total) vs deixar aberto.
4. **Custo aceitável** — confirmar orçamento Google Maps (~$5/1k com cache ≈ 1 chamada/pedido).

---

## FECHO
- ✅ **NÃO editei nada.** Só leitura (Flutter, DB via MCP) + este documento de plano.
- Recomendações claras dadas em cada ponto (1-5) + 4 dúvidas para o Danilo decidir.
