---
id: limpeza-e-monitor-real-2026-07-11
tipo: relatorio
origem: [executor loop autónomo — limpeza de ordem fantasma + monitor de verdade]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: prova-real
---

# Limpeza de ordem fantasma f6aa + monitor visível no ecrã do Danilo (prova real)

## PARTE 1 — ordem f6aa marcada como SUPERADA (não repetir)

**Ordem:** `ordem-20260711160402-f6aa` (Córtex, `orquestracao/`) — "REFORÇO à ordem 2a29:
botão '+' de adicionar ao carrinho + regra de ouro nunca-travar".

- Estava **`estado: travada`, tentativa 5/5** (atingiu o teto → ficava a re-tentar em vão).
- O **conteúdo já estava resolvido** por trabalho posterior, confirmado no repo + inbox:
  1. `Semantics(identifier:'btn_add_carrinho')` em `store_products_screen.dart` e
     `market_product_card.dart`; flow `delivery-mercado-cash.yaml` em *ladder* (id → fallback
     detalhe → prova "Ver carrinho.*"). `flutter analyze`: No issues.
  2. Regra de ouro "nunca travar" → `screenshot_falha()` no `runner.py` + lição
     `wiki/licoes/teste-nunca-trava-tira-foto-e-segue.md`.
  3. Sintomas colaterais (scroll do carrossel, categoria não abria, permissões) resolvidos
     por ordens posteriores e confirmados no e2e_log.
  4. Relatório entregue em `inbox/e2e-reforco-botao-carrinho-2026-07-11.md`.
- **Ação:** `cortex_escrever` → `estado: superada` + `superada_em: 2026-07-11` + nota explicando
  a cobertura posterior (a "nota" antiga "não implementou nada" era da 1ª tentativa falhada).
  `written:true`. O push git da ponte foi rejeitado (remote à frente) — esperado; o loop
  concorrente empurra. O ficheiro no Córtex ficou atualizado.

## PARTE 2 — porque o Danilo NÃO via o monitor (causa raiz) + prova de que agora vê

**Diagnóstico (2 causas somadas):**
1. **Sessão errada (a principal):** o executor autónomo corre como `laptop-2Q09VQA1\hermes` na
   **sessão 0 (services, sem desktop visível)**. O Danilo está na **sessão 1 (console, `danil`,
   ativa)**. Janelas GUI abertas na sessão 0 **nunca aparecem** no ecrã da sessão 1 (isolamento
   de sessão do Windows). Os `schtask-*.cmd` existentes correm como **SYSTEM = sessão 0** → nada
   aparecia. **scrcpy estava morto** (0 processos) no arranque.
2. **scrcpy fora do PATH:** instalado via WinGet
   (`...WinGet\Packages\Genymobile.scrcpy_..._v4.0\scrcpy.exe`). O `monitor-bora.cmd` chamava
   `scrcpy` diretamente → falhava em silêncio → janela `start` abria e fechava.

**Solução (correr NA sessão do Danilo + provar):**
- Novo `.claude/testes-e2e/monitor-e-prova.ps1` — lança scrcpy (caminho absoluto, `ADB` do SDK)
  + tail do e2e_log, traz para a frente, e tira **screenshot do ECRÃ DO PC** (não do telemóvel).
  Idempotente (não empilha scrcpy se já houver janela viva).
- Tarefa agendada **`BoraE2E_MonitorProva`** criada com **`/ru danil /it`** (interativo) →
  corre dentro da **sessão 1**. `schtasks /run` → **ÊXITO**.
- **Prova real (log `_monitor_prova.log`):** `whoami: laptop-2q09vqa1\danil` · scrcpy lançado
  para `N75LTG5X5DSKDMV4` · `scrcpy vivos apos lancar: 1` · screenshot gravado (680 KB).
- **Screenshot inspecionado por mim:** mostra a janela **`Bora-N75LTG5X5...`** com o espelho do
  telemóvel (Redmi 23028RN4DG, Android 13) em **primeiro plano** no desktop + a consola scrcpy 4.0
  ("ADB device found N75LTG5X5DSKDMV4", "Texture 480x1072"). Guardado em
  **`.claude/testes-e2e/screenshots-pc/monitor-confirmado.png`** (o Claude.ai pode pedir ao Danilo
  para o abrir).
- **e2e_log:** linha `monitor-visual / "monitor confirmado visível com screenshot" / passou`
  registada (via `e2e_diario.registar`, `ativo=True`).
- **Fix de recorrência:** `monitor-bora.cmd` passou a resolver o caminho do scrcpy (WinGet) e a
  fixar o `ADB` do SDK, para o Danilo poder relançar manualmente no desktop dele.

> Nota: enquanto o loop correr como `hermes`/sessão 0, o monitor **tem de ser lançado via a tarefa
> `/it` (sessão 1)** para ser visível. `schtasks /run "BoraE2E_MonitorProva"` é o gatilho on-demand
> para o trazer de volta (idempotente).

## Ficheiros tocados
- Córtex `ordem-20260711160402-f6aa` → `estado: superada` (via cortex_escrever)
- `.claude/testes-e2e/monitor-e-prova.ps1` (novo) — lança monitor na sessão do Danilo + screenshot
- `.claude/testes-e2e/monitor-bora.cmd` — resolve scrcpy (WinGet) + ADB do SDK (fix silent-fail)
- `.claude/testes-e2e/screenshots-pc/monitor-confirmado.png` (novo) — prova visual
- e2e_log: +1 linha "monitor confirmado visível com screenshot"
- Tarefa agendada `BoraE2E_MonitorProva` (`/ru danil /it`) — relançador on-demand do monitor
