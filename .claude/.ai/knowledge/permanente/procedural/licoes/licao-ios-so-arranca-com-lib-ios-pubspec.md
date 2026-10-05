---
tema: licao-ios-so-arranca-com-lib-ios-pubspec · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-ios-so-arranca-com-lib-ios-pubspec
tipo: licao
origem: [.github/workflows/build_ios.yml:28-39 e 476-485, commit feb3de27, run 37374708212]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — o iPhone só se publica sozinho quando o push muda `lib/`, `ios/`, `integration_test/` ou `pubspec.yaml`

- **Contexto:** desde 30/09/2026 (commit `feb3de27`, "publicar no iPhone sozinho em cada push
  no ramo de produção") o `build_ios.yml` corre no push ao ramo `autonomous-night-2026-04-29`
  e o job `release` envia à Apple nesse caso
  (`github.event_name == 'push' && github.ref == 'refs/heads/autonomous-night-2026-04-29'`).
- **A descoberta:** o gatilho de push tem **filtro de pastas** (`paths:`): só arranca quando
  mudam `lib/**`, `ios/**`, `integration_test/**`, `pubspec.yaml` ou o próprio
  `.github/workflows/build_ios.yml`. Um push **só de `test/`** (ou só de documentos) corre o
  Android e a web, mas **não o iPhone** — em silêncio.
- **O que aconteceu (05/10/2026):** o conserto do iOS #166 mexeu só em `test/` (commit
  `ac626b95`). O push trouxe a web #195, o olho-golden #187 e o Android #501, e nenhum build
  iOS. Arrancou-se à mão: **iPhone #167** (run 37374708212, `workflow_dispatch`).
- **Regra a aplicar:** depois de um conserto só de testes (ou de qualquer push sem `lib/`,
  `ios/`, `integration_test/` nem `pubspec.yaml`) que tenha de chegar ao iPhone:
  ```
  gh run list --branch autonomous-night-2026-04-29 --limit 6   # confirmar que não há build-ios novo
  gh workflow run build_ios.yml --ref autonomous-night-2026-04-29 -f enviar=true -f submeter_revisao=true
  ```
  Disparar o iPhone é publicar: aplica-se a mesma regra de "push é publicação".
- **Nota de frescura:** o digest de 23/09 (`permanente/memoria-claude-ai/digest-2026-09-23-ios-lancar-102.md`)
  diz que o push só olhava o ramo `ios-lancamento` e que o envio exigia disparo à mão — isso
  valia antes de `feb3de27` (30/09). Hoje vale esta lição. (O digest é espelho da tabela
  `claude_ai_memoria`; não foi editado aqui.)
- **Evidência:** `.github/workflows/build_ios.yml:28-39` (push + paths) e `:476-485` (`if` do
  job `release`); `gh run list` de 05/10: `build-ios #167 in_progress ac626b95 workflow_dispatch`;
  relatório `.claude/.ai/reports/2026-10-05-fecho-home-dinheiro.md` ("iPhone #166").

`estado: atual`
