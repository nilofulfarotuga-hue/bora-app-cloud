# Fix tela branca Serviços — causa-raiz REAL (via adb) · 2026-06-09
### MODO PROTECÇÃO TOTAL · `prompt-blindado-validator` ✅ PASS

> **CAUSA-RAIZ (confirmada na app, build 272):** bug de **layout** no card do prestador.
> `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` dentro de um `ListView`
> (eixo vertical ilimitado) esticava o card para a **altura do viewport (~1910px)**,
> empurrando o conteúdo para fora do ecrã → parecia **tela branca**.
> **Latente desde a criação da feature** — a Barbearia Nobre é o **1º prestador
> aprovado+online** a renderizar, por isso este caminho nunca tinha sido exercido.
>
> ⚠️ A 1ª hipótese ("APK 270 stale") estava **errada**. Foi descartada quando o
> build 272 (já com os marcadores) renderizou na mesma branco — ver §3.

---

## 1. Método (device RZGYB1XQD2P / A36, via adb)
Liguei a Bora ao foreground (estava em background com o Uber à frente → loop de
DNS/`AuthRetryableFetchException` = só throttling de background, **não** o bug).
Naveguei eu próprio até Serviços via árvore de acessibilidade (`uiautomator dump`
→ tile "Serviços" bounds [386,1748][694,2025] → `input tap 540 1886`). Capturei
logcat + screenshot + semântica.

## 2. Confirmação de que NÃO é dados/parse/rede/stale
Versão instalada: **versionCode=272** (já tem o meu código + os marcadores).
Logcat ao abrir Serviços (build 272):
```
[SERVICOS] initState mount        ← ecrã monta ✅
[SERVICOS] build providers=0 loading=true
[SERVICOS] fetchProviders raw=1 parsed=1   ← Barbearia carregada ✅
[SERVICOS] build providers=1 loading=false err=null  ← rebuild c/ 1 prestador ✅
```
**Zero exceptions.** Logo: query OK, parse OK, sem crash. (O "zero chamadas a
/service_providers" reportado antes era porque a app NÃO estava mesmo em Serviços.)

## 3. A prova do bug de layout
- **Screenshot:** título "Serviços" + corpo branco.
- **Semântica:** o nó do card (`InkWell`, content-desc "Barbearia Nobre\n…") tem
  `bounds=[45,295][1035,2205]` → **altura 1910px** (um card devia ter ~96–120px).
  O scroll-view é [0,250][1080,2205]. **O único card enche o viewport inteiro.**
- **Cores (descartam invisibilidade):** card=`#FFFFFF`, texto=`#111111`,
  primary(tesoura)=`#16A34A` — alto contraste. Não é cor; é o card esticado +
  `Column(mainAxisAlignment.center)` a centrar o conteúdo no meio dos 1910px,
  fora da área visível esperada.

→ `CrossAxisAlignment.stretch` exige eixo cruzado **limitado**; num item de
`ListView` a altura é ilimitada → o card estica até ao viewport.

## 4. Fix (cirúrgico, só Serviços)
`lib/screens/client/services/services_category_screen.dart` — `_ProviderCard`:
```diff
  child: Row(
-   crossAxisAlignment: CrossAxisAlignment.stretch,
+   crossAxisAlignment: CrossAxisAlignment.center,   // card compacto = altura da foto
    children: [ ... ]
```
```diff
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
+   mainAxisSize: MainAxisSize.min,                  // não expande na vertical
    children: [ ... ]
```
Resultado esperado: card de ~96px (altura da foto 96), foto à esquerda + nome +
morada + chevron, **visível**. Nada de pricing/dispatch/Stripe/RLS/mercados tocado.

## 5. Lições / notas de processo
- **CI auto-incrementa o versionCode** (`build_android.yml` faz `Bump versionCode`
  + commit `[skip ci]` + `flutter build appbundle` → Play Internal). Por isso o
  versionCode é **por-build, não por-commit** — o que baralhou o diagnóstico
  ("271 = build anterior ao fix"). **A partir de agora não toco no versionCode
  manualmente; deixo o CI gerir.** Este commit NÃO bumpa pubspec.
- **Detectar binário/screen errado:** procurar os marcadores `debugPrint`
  (`[SERVICOS] …`) no logcat — se faltam, o ecrã não está a correr o código novo.
- **Método para tela branca em release:** semântica (`uiautomator dump`) mostra
  o widget na árvore mesmo quando invisível; comparar bounds vs screenshot revela
  bugs de layout (aqui, 1910px vs ~96px).

## 6. FIM
- Commit + push origin autonomous-night-2026-04-29 → CI compila o próximo build
  (versionCode ~273) com o fix de layout.
- `/ctx doctor` + `/ctx stats`.
- Danilo: instalar o build mais recente (>272) do Play Internal, abrir Serviços
  → a Barbearia Nobre deve aparecer. Eu re-confirmo via adb (screenshot).
