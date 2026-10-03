---
id: e2e-render-fix-2026-07-21
tipo: diagnostico
tema: web-rendering
estado: atual
data: 2026-07-21
---

# Flutter Web Rendering Fix — 2 tentativas, 2 falhas

## Contexto

Flutter web (HTML renderer) não renderiza no headless Chromium da VPS `srv1786862.hstgr.cloud`. O `flt-glass-pane` fica sempre vazio (0 children). Testadas 2 correções específicas.

## Fix 1: SwiftShader (GPU por software)

**Flags:** `--enable-unsafe-swiftshader --use-gl=angle --use-angle=swiftshader --disable-gpu-sandbox`

**Resultado:** ❌ FALHOU
```
gpChildren: 0
hasCanvas: false
semanticsCount: 0
totalElements: 47
```

## Fix 2: xvfb + headless:false

**Setup:** `apt-get install -y xvfb` → `xvfb-run -a node fix2-test.js`

**Resultado:** ❌ FALHOU
```
gpChildren: 0
hasCanvas: false
semanticsCount: 0
totalElements: 47
```

## Erro WebGL da consola (ambos os fixes)

```
[warning]: [.WebGL-0x...]GL Driver Message (OpenGL, Performance, GL_CLOSE_PATH_NV, High): GPU stall due to ReadPixels
```

## Screenshots comparativos

- `screenshots/fix1-swiftshader.png` (111560 bytes) — shell vazio
- `screenshots/fix2-xvfb.png` (111560 bytes) — shell vazio
- Ambos mostram o mesmo output: DOM com 47 elementos, `flt-glass-pane` vazio, 0 semantics

## Conclusão

O rendering pipeline do Flutter web não completa em nenhum modo de Chromium nesta VPS:
- headless shell: ❌
- headless=false (xvfb): ❌
- SwiftShader: ❌
- Chrome completo: ❌

A causa provável é que o Flutter web HTML renderer depende de features WebGL que não estão implementadas no driver OpenGL/software desta VPS (AMD EPYC sem GPU dedicada).

**Aprovo o caminho GitHub Actions** (ubuntu-latest, ~7GB RAM, 2 vCPU, GPU por software disponível).
