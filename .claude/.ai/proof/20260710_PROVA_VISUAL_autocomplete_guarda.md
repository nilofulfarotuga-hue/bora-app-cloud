# PROVA VISUAL — Autocomplete com viés geográfico Guarda (2026-07-10)

Ordem: continuação de `ordem-20260709110949-8448` (que travou por falta de prova visual).
Executor: loop autónomo (Opus 4.8), MODO PROTEÇÃO TOTAL.

## Contexto / premissas da ordem — reavaliadas

| Premissa da ordem | Realidade encontrada |
|---|---|
| "fix pronto mas NÃO commitado" | **Já commitado** — `f90d9fa` (viés Guarda + retry `<query> Guarda` + fallback nacional) e `b1f1b5d` (ícone storefront para estabelecimentos). Ficheiros `place_autocomplete_service*.dart` sem alterações por commitar. |
| "falta `adb` no ambiente" | **adb já instalado** em `C:\Users\danil\AppData\Local\Android\Sdk\platform-tools\adb.exe` (v1.0.41), no PATH. Nada a instalar. |
| "não consegue ver o telemóvel" | **2 dispositivos online**: `N75LTG5X5DSKDMV4` e `RZGYB1XQD2P` (Bora app `pt.boraapp.bora` instalado em ambos). |

Conclusão: as três barreiras que travaram a ordem anterior já não existem. A prova foi obtida.

## Prova 1 — "LaVie" aparece (estabelecimento com ícone storefront)
Ficheiro: `20260710_device_baseline.png` (1080×2340, device `RZGYB1XQD2P`)
Ecrã "Levar Compras" → campo "Local da loja" preenchido com **"LaVie Guarda"** + ícone storefront.
→ Confirma que o estabelecimento "Lavie" da Guarda é encontrado e desenhado como loja (não como morada).

## Prova 2 — "Continente" → todos os resultados na Guarda
Ficheiro: `20260710_continente_guarda.png` (1080×2340, device `RZGYB1XQD2P`)
Digitado "Continente" no campo. Predições devolvidas (todas Guarda):
1. **Continente Modelo** — Guarda · 0.7 km
2. **Continente** `Loja Bora` (ícone storefront) — Rua do Ferrinho, 6300-566 Guarda · 0.7 km
3. **Continente Bom Dia** — Avenida de São Miguel, Guarda · 2.3 km

→ Zero resultados de Lisboa/Porto. Viés geográfico para a Guarda a funcionar. Parceiro "Loja Bora" com badge + ícone storefront (`b1f1b5d`).

## Como foi capturado
`juiz_capture.py --mode mobile --serial RZGYB1XQD2P` (Python do venv `scripts/e2e/.venv`, pois `python` não está no PATH global — apenas o trampoline uv partido em `~/.local/bin`). Interação via `adb shell input tap/text/keyevent`.

## Nota para o Danilo
- Os commits `f90d9fa` + `b1f1b5d` estão **à frente de `origin`** (não foram feitos push — regra do loop: não faço push sem pedido explícito).
- A build instalada no device `RZGYB1XQD2P` **já contém o fix** (as predições mostram o comportamento novo).
- Não foi tocado no bug dos tokens do TVDE (fica para ordem separada, conforme instruído).
