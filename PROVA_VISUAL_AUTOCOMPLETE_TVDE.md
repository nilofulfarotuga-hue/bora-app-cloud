# Prova visual do autocomplete de comércios/POIs (TVDE) — estado + checklist de 1 passo

**Data:** 2026-07-09 · Loop autónomo (executor headless) · ordem `ordem-20260709072158-3bf9`
**Código em causa:** autocomplete Google Places com comércios/POIs (ex.: "KFC") no ecrã de
pedir corrida TVDE (`lib/screens/client/tvde/tvde_request_ride_screen.dart` → campos
`Ponto de recolha` e `Para onde vais?`, via `AddressAutocompleteField` +
`place_autocomplete_service_web.dart`).

## Situação

O código **já passou as camadas 1 e 2 do Juiz** (`flutter analyze` limpo + `flutter test` verde).
Só falta a **prova visual real**. Foram feitas 5 tentativas anteriores e esta 6.ª focou-se em
obter a prova **sem telemóvel**, via `flutter run` em modo web + `juiz_capture.py --mode web`.

## Conclusão honesta: prova visual automática NÃO é viável nesta máquina

Não invento sucesso (regra do `juiz_capture.py`: "HONESTIDADE ACIMA DE TUDO"). Cinco bloqueios,
qualquer um deles chega para travar; juntos são definitivos:

1. **O build web crashou por falta de memória.** `flutter run -d web-server` correu, baixou as
   dependências, começou a compilar e o **compilador Dart abortou**:
   `evacuation failed` + `Could not start thread DartWorker: 22` → **"Failed to compile
   application"**. É OOM/exaustão de recursos (o próprio PowerShell morreu em paralelo com
   `0x8007005af`, erro de memória). Sem build web, não há URL para fotografar.

2. **`juiz_capture.py --mode web` é uma foto ESTÁTICA de um URL.** Não faz login, não desbloqueia
   o TVDE, não abre o ecrã de pedir corrida, não escreve "KFC" no campo, nem espera o dropdown.
   Provar o autocomplete exige **todas** essas interações — o script não interage.

3. **Flutter web pinta num `<canvas>` (CanvasKit).** Mesmo com um Playwright interativo, o campo
   de morada e a lista de sugestões são **pixéis num canvas**, não elementos `<input>`/`<li>` do
   DOM. Automação DOM é cega ao conteúdo do canvas do Flutter.

4. **Navegação por estado, sem rota de URL.** O `_RootNavigator` (ver `CLAUDE.md`) decide o ecrã
   por estado, não há `/tvde/request`. Um browser que aterre em `http://127.0.0.1:8099/` só vê o
   ecrã de login/role — nunca o ecrã de recolha/destino.

5. **Ferramentas ausentes.** `playwright` + `chromium` não estão instalados e o `python` nem está
   no PATH desta máquina. Instalá-los não resolve os pontos 1–4.

> Isto é um `ok:false` legítimo do Juiz: o teto de nota 8 "sem olhos" mantém-se correto. A prova
> visual precisa mesmo de um olho humano num app a correr — e isso é rápido (ver abaixo).

## ✅ Checklist manual de 1 passo (para o Danilo — ~15 segundos)

O app Android já está publicado no track fechado (alpha). **Da próxima vez que abrires o Bora no
telemóvel:**

1. Cliente → **TVDE / Bora Motorista** → ecrã **"Pedir corrida"** → toca no campo
   **"Para onde vais?"** (ou **"Ponto de recolha"**) e escreve **`KFC`**.

**Confirma que aparece na lista de sugestões:** o **nome** ("KFC"), o **ícone de estabelecimento**
(não o pin genérico de morada) e a **morada** por baixo. Se aparecer → prova feita, autocomplete de
comércios/POIs a funcionar. Se só aparecerem ruas (sem comércios) → avisa que houve regressão.

*(É este o comportamento novo: o serviço deixou de estar preso a `types: geocode` e passou a
devolver moradas E comércios — ver comentário em `place_autocomplete_service_web.dart:94`.)*

## O que ficou pronto para desbloquear a prova por outra via (opcional, futuro)

- **Emulador Android** nesta máquina resolvia tudo (`juiz_capture.py --mode mobile` via `adb
  screencap` já existe e funciona) — mas não há emulador/dispositivo ligado agora.
- **Build web** só compilaria com mais RAM (fechar processos / máquina maior); e mesmo assim
  esbarraria nos pontos 2–4 acima. Não é o caminho certo para este ecrã.

**Ficheiros tocados:** apenas este relatório (`PROVA_VISUAL_AUTOCOMPLETE_TVDE.md`) e um log
temporário `.claude/scripts/_flutter_web_run.log`. **Nenhum código de produção foi alterado.**
