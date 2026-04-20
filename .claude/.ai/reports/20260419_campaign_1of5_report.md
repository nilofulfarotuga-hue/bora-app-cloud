# Campanha 1/5 — Relatório Final

Data: 2026-04-19
Modo: PROTECÇÃO TOTAL
Orquestrador: CEO-AI
Zonas protegidas: ✅ INTACTAS

---

## ⚠️ DESCOBERTA CRÍTICA — BOMBA-RELÓGIO PRÉ-LANÇAMENTO ⚠️

**Durante o diagnóstico C1 descobrimos um problema SISTÉMICO que afecta toda a app, não apenas a foto de perfil.**

### Evidência SQL (run directo em Supabase)

| Métrica                         | Guest (`guest@bora.com`) | User real  |
|---------------------------------|--------------------------|------------|
| Orders criadas                  | **39**                   | 3          |
| Tokens atribuídos               | **51**                   | — (amostra)|
| % orders no guest               | **~93%**                 | ~7%        |

### Interpretação

Quando o cliente abre a app, `AuthStore._initFromPrefs` por vezes cai em `_ensureGuestSession`, assinando como `guest@bora.com`. O cliente em memória continua "logado" (`AuthStore._currentClient` não é null) mas a sessão Supabase é guest. Resultado:

- `orders.user_id` escreve o UUID do guest
- `bora_tokens` atribui ao guest
- `avatars/` upload dá 403 (RLS) ou grava no path do guest
- Na próxima abertura, o cliente "perde" tudo

### Classificação

- Impacto em RECEITA: **crítico** (orders fantasma, tokens perdidos, histórico partido)
- Impacto em UX: **crítico** (utilizador real não vê os próprios pedidos)
- Impacto em ESTABILIDADE: **crítico**
- Probabilidade em produção: **100%** se for lançado assim

### Decisão

→ **Campanha dedicada pré-lançamento — Opção A (refactor auth layer) — OBRIGATÓRIA.**
→ Não lançar até resolver.
→ Ficheiros envolvidos: `lib/auth/auth_store.dart` (`loginClientAsync`, `registerClientAsync`, `_initFromPrefs`, `_ensureGuestSession`).
→ Meta: `AuthStore._currentClient != null ⇒ supabase.auth.currentUser.id == client.id` sempre.

---

## C1 — Foto de perfil não persiste (FIX CIRÚRGICO aplicado)

### Diagnóstico

**Causa raiz imediata (que bloqueia o upload):** guard em `_pickAndUploadAvatar` tratava sessão guest como "demo account" e abortava com snackbar genérico. Mesmo em conta real com `client.email` válido o upload não arrancava quando a sessão Supabase estava em guest.

**Evidências do backend:**
- Bucket `avatars` existe, RLS correcta (`auth.uid()::text = (storage.foldername(name))[1]`)
- **0 ficheiros no bucket** (nenhum upload jamais chegou lá)
- `auth.users.raw_user_meta_data['bora_photo_url']` = null para todos os utilizadores
- Tabela `public.users.photo_url` existe mas vazia (não é usada pelo código actual)

### Fix aplicado (Opção B — cirúrgica, sem tocar AuthStore)

Ficheiro: `lib/screens/profile_screen.dart` — método `_pickAndUploadAvatar()`

- Se `supabase.auth.currentUser` é null ou é guest E existe `authStore.currentClient` com `email` + `password` (conta real, não demo), faz `signInWithPassword` silencioso antes de chamar o upload.
- Se falhar ou for demo, snackbar distingue as duas situações:
  - Demo: "Demo accounts não podem fazer upload de foto. Cria uma conta real."
  - Real: "Sessão expirada. Faz logout e login novamente."

**Zonas protegidas intactas.** Pricing, DispatchEngine, Stripe, bora_tokens triggers, DriverCapacityService, finalizePurchase, fotos de produtos: nenhuma alteração.

### Como testar

1. Cria conta real (não `cliente@bora.app`)
2. Fecha app, reabre
3. Vai a Perfil → toca foto → escolhe imagem
4. Esperado: upload arranca e foto aparece persistente após hot restart
5. Se sessão Supabase estiver em guest (bug sistémico actual), o fix re-autentica silenciosamente antes do upload

---

## C2 — Padronização de headers (6 ecrãs cliente)

### Widget criado

`lib/widgets/bora/bora_screen_app_bar.dart` — `BoraScreenAppBar`
- `PreferredSizeWidget` → encaixa directo em `Scaffold.appBar:`
- Fundo: `AppColors.headerGradient` (verde Bora)
- Seta voltar + título: `AppColors.accent` (laranja #E65100)
- Título `FontWeight.w800`
- Suporta `actions` opcionais

Adicionado ao barrel: `lib/widgets/bora/bora.dart`

### Aplicação em 6 rubricas / 6 ficheiros físicos

| Rubrica              | Ficheiro                                | Título               |
|----------------------|-----------------------------------------|----------------------|
| Restaurantes         | `restaurants_screen.dart`               | Restaurantes         |
| Reservar Mesa        | `restaurants_screen.dart` (flag)        | Reservar Mesa        |
| Supermercados        | `stores_screen.dart`                    | Supermercados        |
| Farmácia             | `stores_screen.dart` (flag)             | Farmácias            |
| Enviar Encomenda     | `send_package_screen.dart` + `send_package_form_screen.dart` | Enviar Encomenda |
| Levar Compras        | `carry_groceries_screen.dart` + `carry_groceries_form_screen.dart` | Levar Compras    |

**Nota de harmonização (aprovada):** "Enviar pacote" renomeado para "Enviar Encomenda", "Entregar compras" renomeado para "Levar Compras".

### Resultado `flutter analyze`

```
3 issues found (ran in 20.5s)
— 0 errors
— 0 warnings
— 3 info pre-existentes (dart:js/dart:html deprecation em place_autocomplete_service_web.dart e directions_service_web.dart, fora do âmbito desta campanha)
```

---

## C3 — Propostas de skills para campanhas futuras

Duas propostas alinhadas com o roadmap (campanhas 2/5, 3/5, 4/5, 5/5):

### 1. `taxonomy-mapper` (campanha 3/5 — taxonomia 18 secções)

**Objectivo:** Mapear produtos a uma taxonomia canónica de 18 secções Bora (mercearia, frescos, higiene, bebidas, limpeza, etc.) com regras de fallback consistentes.

**Capacidades:**
- Input: lista de produtos não-categorizados (nome + opcional descrição)
- Output: mapping `product_id → section` com score de confiança
- Regras: sinónimos pt-PT, variantes de marca, fuzzy match, override manual via whitelist
- Integração: `public.products.section`, validation via `SELECT DISTINCT section`

**Porquê útil:** Campanha 3/5 toca 18 secções. Sem skill dedicada, risco alto de produtos espalhados em secções erradas (ex.: "leite" em "bebidas" vs "frescos") → UX partida na listagem por categoria.

### 2. `market-data-cleaner` (campanhas 4/5 e 5/5 — limpeza produtos + menus restaurantes)

**Objectivo:** Normalizar dados de catálogo (produtos, menus) em bulk preservando fotos reais e preços.

**Capacidades:**
- Detecta duplicados (mesmo produto com SKU diferente entre parceiros)
- Normaliza unidades (`500g`, `0.5kg`, `500 gr` → `500g`)
- Detecta placeholders (`Nome do produto`, `Lorem ipsum`, fotos stock)
- Valida preços fora de range (ex.: `price = 0.01` ou `price > 999`)
- **NUNCA toca em fotos reais** (zona protegida) — apenas metadata
- Relatório de dry-run antes de qualquer UPDATE

**Porquê útil:** Campanha 4/5 = limpeza produtos, 5/5 = menus restaurantes. Sem skill, cada limpeza vira work ad-hoc com risco de apagar fotos reais (zona protegida).

### 3. Não-proposta (descartada)

`ui-consistency-auditor` foi considerada mas descartada: com `BoraScreenAppBar` agora no barrel e a estratégia de reuso estabelecida, basta um checklist manual de 15 min nas próximas campanhas UI. Criar skill para isto seria over-engineering.

---

## Ficheiros modificados nesta campanha

```
lib/screens/profile_screen.dart                 (C1 fix cirúrgico)
lib/widgets/bora/bora_screen_app_bar.dart       (NOVO — C2)
lib/widgets/bora/bora.dart                      (export C2)
lib/screens/restaurants_screen.dart             (C2)
lib/screens/stores_screen.dart                  (C2 + remoção import não usado)
lib/screens/send_package_screen.dart            (C2)
lib/screens/send_package_form_screen.dart       (C2)
lib/screens/carry_groceries_screen.dart         (C2)
lib/screens/carry_groceries_form_screen.dart    (C2)
```

## Instruções de teste

1. `flutter clean && flutter pub get && flutter run`
2. **C1:** Conta real → Perfil → upload foto → restart → foto persistente
3. **C2:** Abrir Restaurantes / Reservar Mesa / Supermercados / Farmácia / Enviar Encomenda / Levar Compras → confirmar header verde com seta e título laranja em todos
4. Confirmar que zonas protegidas (checkout Stripe, dispatch, fees, tokens) continuam a funcionar end-to-end

## Próxima acção recomendada

**BLOQUEADOR de lançamento:** abrir campanha dedicada Opção A (refactor `AuthStore` — sessão guest vs cliente real) antes de qualquer outra campanha UI/dados. As campanhas 2/5, 3/5, 4/5, 5/5 podem prosseguir em paralelo porque não tocam na auth, mas **não lançar enquanto o bug sistémico não estiver resolvido**.
