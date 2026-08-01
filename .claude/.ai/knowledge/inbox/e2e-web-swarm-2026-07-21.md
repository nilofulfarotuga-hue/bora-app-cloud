# E2E Web Testing — Relatório Final: Caminhos A e B Bloqueados

## Run_ID: WEB-E2E-2026-07-21-B

## Resumo

| Fluxo | Status | Observação |
|---|---|---|
| 01 Login cliente cash | ⚠️ Não executado | Ambos os caminhos bloqueados infra |
| 02 Chamar TVDE | ⚠️ Não executado | — |
| 03 Delivery | ⚠️ Não executado | — |
| 04 Contrato limpeza | ⚠️ Não executado | — |
| 05 Reserva | ⚠️ Não executado | — |
| 06 Varredura | ⚠️ Não executado | — |

## Resultado dos Caminhos

### Caminho A — HTML Renderer (❌)
- **Impossível**: Flutter 3.41.2 ≥ 3.29 removeu `--web-renderer html`
- CanvasKit (WebGL) requer GPU → VPS headless não tem

### Caminho B — flutter drive (❌)
- **FALHOU**: Compilação Flutter web consumiu **toda RAM (2.3GB)** → OOM → sistema derrubado
- Problema adicional: chromedriver 149 + webdriver Dart 3.1.0 incompatíveis
- Problema adicional: Chrome debug connection (dwds) timeout
- **Problema base**: RAM insuficiente na VPS (Hoster) para compilar Flutter web

## Infra construída (aproveitável)

Na VPS `srv1786862.hstgr.cloud`:
- ✅ Flutter 3.44.7 SDK
- ✅ Chromedriver 149.0.7827.55
- ✅ Chrome-wrapper (`--no-sandbox --headless --disable-gpu`)
- ✅ `integration_test/e2e_test.dart` (teste com 6 fluxos)
- ✅ `test_driver/integration_test.dart`
- ✅ Assets do projeto
- ✅ `.dart_defines` (Supabase + Stripe + Google Maps)

No PC:
- ✅ `build/web/` compilado (funcional, deployado em Cloudflare Pages)
- ✅ Projecto completo com todas as contas swarm

## Solução Recomendada

**GitHub Actions** com runner `ubuntu-latest` (8GB RAM):

| Recurso | VPS (Hoster) | GitHub Runner |
|---|---|---|
| RAM livre | 2.3 GB | ~8 GB |
| Chrome | Playwright (instalação manual) | google-chrome-stable nativo |
| Compilação Flutter | OOM | ✅ |

Workflow proposto em `docs/e2e-web-2026-07-21/E2E-ONBOARDING-GUIDE.md`.

## Lições aprendidas
1. VPS de 4GB (2.3GB livre) é insuficiente para compilar Flutter web (precisa ≥4GB livre)
2. `webdriver` Dart 3.1.0 envia `desiredCapabilities` + `capabilities`; ChromeDriver 149 rejeita (precisa só W3C)
3. `flutter drive -d chrome` requer dwds → timeout em headless lento
4. Playwright não acede à widget tree do Flutter (só DOM) → inútil sem renderização
