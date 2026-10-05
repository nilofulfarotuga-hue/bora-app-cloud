---
tema: licao-skip-ci-no-commit-de-cima · escopo: projeto · estado: atual · atualizado: 2026-10-05
id: licao-skip-ci-no-commit-de-cima
tipo: licao
origem: [reflog do ramo ronda-dinheiro-despacho-05-10 (101a7210 → d5e2d027), commit 5efd2d96, .github/workflows/build_android.yml]
ultima_confirmacao: 2026-10-05
zona: verde
confianca: auto
---

# Lição — `[skip ci]` no commit de CIMA salta o build do push inteiro

- **Contexto:** fecho da missão `ronda-dinheiro-despacho-2026-10-05`. Um só envio com dois
  commits: o de código (`5efd2d96`) e, por cima, o do relatório (só `.md`).
- **A descoberta:** o GitHub Actions lê a marca `[skip ci]` no commit de **cima** (o HEAD) do
  push. Se esse commit a levar, o push inteiro fica sem autoteste, sem build Android e sem deploy
  web — mesmo com código nos commits de baixo. O código chega ao ramo de produção e não é
  publicado, em silêncio. O `paths-ignore` não protege aqui: ele avalia os ficheiros de todos os
  commits do push (por isso o código "pega boleia"), mas a marca corta o push antes disso.
- **O que aconteceu (2026-10-05):** o commit do relatório foi gravado com `[skip ci]`
  (`101a7210`) por cima do `5efd2d96`. Foi apanhado **antes** de empurrar: a marca saiu por
  `commit --amend` (`cdad8ee9`, depois `d5e2d027`) e o envio das 08h15 de Lisboa disparou as
  corridas normais. Não chegou a haver build saltado.
- **Regra a aplicar:** só pôr `[skip ci]` quando **TODOS** os commits do push são só-documentos.
  Antes de empurrar, com código no meio, isto tem de dar 0:
  `git log --format=%B origin/<ramo>..HEAD | grep -ci "skip ci"`.
- **Evidência:**
  - reflog do ramo `ronda-dinheiro-despacho-05-10`: `101a7210 commit: docs(ronda-04-10): … [skip ci]`
    → `cdad8ee9 commit (amend)` → `d5e2d027 commit (amend)` (sem a marca; pai = `5efd2d96`);
  - `.github/workflows/build_android.yml:249-258` usa a mesma marca **de propósito** no commit
    `ci: bump versionCode to N [skip ci]`, para o push do próprio CI não disparar nova corrida;
  - 21/09/2026: quatro commits com a marca (`b08fe8b9`, `6f6fdaf2`, `bc1dea7f`, `75f56bb2`) não
    dispararam Android nem web (`permanente/memoria-claude-ai/digest-2026-09-21-paridade-3-plataformas.md`).

`estado: atual`
