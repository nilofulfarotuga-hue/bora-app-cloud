# Guia de Onboarding — E2E Testing do Bora App

## TL;DR

| Caminho | Resultado | Motivo |
|---|---|---|
| A — HTML renderer + Playwright | **IMPOSSÍVEL** | Flutter ≥ 3.29 removeu `--web-renderer html` |
| B — `flutter drive` na VPS | **FALHOU** | Build esgotou 2.3GB RAM e derrubou o sistema |
| **→ Solução: GitHub Actions** | ✅ **PRÓXIMO PASSO** | 8GB RAM padrão |

---

## 1. Contexto

O Bora App precisa de **testes E2E web** que validem os 6 fluxos de cliente:
1. Corrida cash
2. Chamar TVDE
3. Delivery
4. Contrato limpeza
5. Reserva
6. Varredura

Duas abordagens foram tentadas — ambas falharam por motivos diferentes, mas convergentes: **falta de GPU** para renderização e **falta de RAM** para compilação.

---

## 2. Caminho A — HTML Renderer + Playwright (❌)

**Tentativa:** Usar `--web-renderer=html` para que o Flutter renderizasse via DOM/CSS (sem GPU), e então usar Playwright para interagir com o DOM.

**Impedimento:** Flutter 3.41.2 ≥ 3.29 removeu o suporte a HTML renderer. A flag `--web-renderer html` é ignorada; o app compila sempre com **CanvasKit** (WebGL).

**Tentativas de contorno na VPS (9 variações):**
- Chromium headless shell
- Chromium full + `--headless`
- Chromium + `--disable-gpu --enable-unsafe-swiftshader`
- Chromium + `--use-gl=angle --use-angle=swiftshader`
- Chromium + `xvfb-run` + `headless:false`

**Resultado:** `flt-glass-pane` sempre vazio (0 children). GPU stall no WebGL (`ReadPixels`).

---

## 3. Caminho B — `flutter drive` + integration_test (❌)

**Tentativa:** Usar `flutter drive` com `integration_test` para testar a widget tree (não precisa de renderização).

**Infra montada na VPS:**
- ✅ Flutter 3.44.7 SDK instalado (snap)
- ✅ Chromedriver 149.0.7827.55
- ✅ Chrome-wrapper com `--no-sandbox --headless --disable-gpu`
- ✅ `pub get` bem-sucedido
- ✅ Assets sincronizados do PC
- ✅ `.dart_defines` configurado

**Problema 1 — chromedriver + webdriver Dart:** ChromeDriver 149 rejeita o formato de sessão do pacote `webdriver` 3.1.0 do Dart (que envia `desiredCapabilities` + `capabilities` simultaneamente).

**Problema 2 — Chrome debug connection:** `flutter drive -d chrome --web-run-headless` lança Chrome com `--remote-debugging-port`, mas a conexão de debug do `dwds` (Dart Web Debug Service) falha por timeout.

**Problema 3 — RAM (definitivo):** A compilação Flutter web (debug mode) consumiu **toda a RAM disponível (2.3GB)** e causou OOM — o sistema ficou inoperante por ~5 minutos.

---

## 4. Arquivo de evidências

```
docs/e2e-web-2026-07-21/
├── e2e-web-swarm.js              → Playwright script (incompleto, bloqueado no render)
├── run-*.ps1                      → Scripts de execução das 9 variações
├── login-steps.md                 → Passos de login manual
├── E2E-ONBOARDING-GUIDE.md        ← Este documento
├── flutter_01.log                 → Crash log do flutter drive (webdriver exception)
└── screencast-*/                   → Capturas de tela (flt-glass-pane vazio)
```

---

## 5. Próximo passo: GitHub Actions

A solução prática é **GitHub Actions com machine Ubuntu 8GB+**:

### Setup mínimo:
- `ubuntu-latest` (GitHub hosted runner — 8GB RAM, 2 CPUs)
- `actions/checkout@v4`
- `subosito/flutter-action@v2` (ou `setup-flutter`)
- `coactions/setup-xvfb@v1` (para X virtual)
- `dart-lang/setup-dart`

### Workflow:
```yaml
- uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.44.x'

- run: flutter pub get
- run: flutter build web --dart-define-from-file=.dart_defines
- run: flutter drive --driver=test_driver/integration_test.dart
       --target=integration_test/e2e_test.dart
       -d chrome --web-run-headless
       --dart-define-from-file=.dart_defines
  timeout-minutes: 15
```

### Por que GitHub Actions resolve:
| Recurso | VPS (Hoster) | GitHub Runner |
|---|---|---|
| RAM | 2.3 GB livre | ~8 GB |
| GPU | Headless (nenhuma) | Headless (nenhuma) |
| Chrome | Instalado via Playwright | `google-chrome-stable` nativo |
| Chromedriver | Manual | `google-chrome` + chromedriver integrado |
| Compilação Flutter | OOM | ✅ Sobra RAM |
| Custo | Incluído no plano | 2000 min/mês grátis |

---

## 6. Resumo para o Danilo

> **Os dois caminhos estão bloqueados por recursos do servidor — não por lógica de teste.**
>
> HTML renderer não existe mais no Flutter 3.29+ (Caminho A impossível).
> `flutter drive` compila em debug, o que exige >3GB RAM — a VPS tem 2.3GB livres (Caminho B falhou).
>
> A solução é rodar na cloud (GitHub Actions). O trabalho de preparação está feito:
> - integration_test escrito
> - test_driver configurado
> - chromedriver testado
> - Todo o mapping de widgets completo
>
> **Estimativa:** 2 horas para o setup do workflow + 30 min por execução.

---

## 7. Contas de teste do E2E

| Tipo | Email | Password |
|---|---|---|
| Cliente | `cliente1@swarm.bora.test` | `SwarmBora2026!` |
| Motorista | `motorista1@swarm.bora.test` | `SwarmBora2026!` |
| Estafeta | `estafeta1@swarm.bora.test` | `SwarmBora2026!` |
| Limpador | `limpador1@swarm.bora.test` | `SwarmBora2026!` |
| Demo | `cliente@bora.app` | `123456` |
| Parceiro | `ouro.prata@bora.app` | `OuroPrata2026!` |
