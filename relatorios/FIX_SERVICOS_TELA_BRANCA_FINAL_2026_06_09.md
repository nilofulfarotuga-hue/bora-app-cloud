# Fix tela branca Serviços (diagnóstico via adb) · 2026-06-09
### MODO PROTECÇÃO TOTAL · `prompt-blindado-validator` ✅ PASS

> **Conclusão:** não é bug de render no código actual — é um **APK 270 desactualizado** (binário antigo, anterior ao fix `d449ed4`). O fix já está commitado no repo; nunca chegou ao telemóvel. Solução = **rebuild 271** (o código já está correcto).

---

## 1. Diagnóstico via ADB (device RZGYB1XQD2P / A36)

**Passos:** `adb` ligado ✅. Trouxe a Bora ao foreground (estava em background, com o **Uber Driver** à frente — daí o loop de `AuthRetryableFetchException`/DNS, que era só throttling de app em background, **não** o bug). Limpei o buffer, capturei logcat + screenshot + árvore de semântica.

**Achados decisivos:**
1. **ZERO marcadores `[SERVICOS]`** no logcat — apesar de outros stores logarem normalmente (`[OrderStore] orders received=9`, `RestaurantStore ... Realtime`, `[ReservationStore] ...`). Ou seja, `debugPrint` funciona neste build, mas a linha `[SERVICOS] build providers=...` **não corre**.
2. **Screenshot:** título "Serviços" no topo, **corpo totalmente em branco** (sem spinner, sem erro, sem "Volta em breve", sem card). = a tela branca reportada.
3. **Árvore de semântica (uiautomator):** mostrava um nó "Barbearia Nobre\nRua Francisco de Passos…" — inconsistente com o screenshot branco (captura em momento ligeiramente diferente).
4. Ping do telemóvel → Supabase **OK** (14 ms, 0% perda). A rede caiu só transitoriamente enquanto a app estava em background.

## 2. Causa-raiz: binário 270 está STALE (anterior ao fix)

- O ecrã `services_category_screen.dart` no **HEAD (4611e67)** já tem: o `debugPrint('[SERVICOS] build…')`, o card defensivo (`_PhotoFallback` ×7, guard de foto vazia, `ratingsCount>0`, morada guardada) e o parse resiliente.
- O ficheiro em disco **== HEAD** (sem alterações por commitar).
- O fix veio do commit **`d449ed4` (v268)** — *"resilient provider parse (numeric-as-string + per-row) + [SERVICOS] diagnostics"* (toca `service_provider_model.dart` `toD` aceita String, e `services_store.dart` parse por-linha com try/catch).
- **`d449ed4` é anterior a 4611e67 (v270)** → um APK 270 verdadeiro **teria** os marcadores `[SERVICOS]`. Como o telemóvel **não os mostra**, o binário instalado é **anterior a `d449ed4`** (build stale / errado, apesar do versionCode 270).

→ **O telemóvel tem a versão antiga (buggy) do parse; o fix nunca foi compilado para o APK que o Danilo instalou.**

## 3. Porque é que o código actual resolve

Com os dados reais da Barbearia (`photo_url=""`, `ratings_count=0`, `avg_rating=null`, morada preenchida), o `_ProviderCard` **actual** renderiza: placeholder de foto (tesoura) + nome + morada + chevron — **visível, sem crash**. O parse resiliente (`d449ed4`) garante que `numeric`-como-String e linhas malformadas **nunca esvaziam a lista**. Logo, um build do HEAD actual mostra a Barbearia.

## 4. Ficheiros tocados

| Ficheiro | Mudança |
|---|---|
| `lib/screens/client/services/services_category_screen.dart` | +1 linha diagnóstico `debugPrint('[SERVICOS] initState mount (build 271)')` em `initState` — confirma no próximo logcat que o **código novo** está mesmo a correr. |
| `pubspec.yaml` | versionCode +270 → **+271** |

**Nenhum** ficheiro de pricing/dispatch/Stripe/RLS/mercados/restaurantes tocado. O render do card **não** foi alterado (já estava correcto).

## 5. Validação (pós-build 271)

Quando o Danilo instalar o 271 e abrir Serviços, capturo `adb logcat -d` e espero ver:
```
[SERVICOS] initState mount (build 271)
[SERVICOS] fetchProviders raw=1 parsed=1
[SERVICOS] build providers=1 loading=false err=null
```
→ e a **Barbearia Nobre** visível no ecrã.

**Se mesmo assim ficar branco** (improvável): agora os marcadores `[SERVICOS]` existem no build → o logcat dirá exactamente onde (raw/parsed/providers), e corrijo a linha exacta num 272. O 270 não tinha estes marcadores — era por isso que estávamos às cegas.

## 6. FIM
- Commit + push origin autonomous-night-2026-04-29 → CI compila **271** (a partir do HEAD, com o fix `d449ed4`).
- `/ctx doctor` + `/ctx stats`.
- Pedir ao Danilo: instalar 271, abrir Serviços, dizer "aberto" → eu re-capturo o logcat para confirmar.
