---
tema: licao-crlf-sh-eol · escopo: projeto · estado: atual · atualizado: 2026-07-01
---

# Scripts `.sh` em Windows: forçar LF ou o bash quebra

- **Contexto:** Fase 1 (A Trava) — criar hooks `.claude/hooks/protege-*.sh` num repo em Windows.
- **A descoberta:** o git avisava "LF will be replaced by CRLF"; CRLF num script bash causa
  erro `\r` na execução. Além disso, `grep -c $'\r'` no Git Bash **conta todas as linhas**
  (não é fiável para detetar CR).
- **Regra a aplicar:** (1) criar/estender `.gitattributes` com `*.sh text eol=lf`;
  (2) verificar bytes CR com **python** (`open(f,'rb').read().count(b'\r')`), nunca com
  `grep -c $'\r'`; (3) se preciso, limpar com `sed -i 's/\r$//'`.
- **Evidência:** commit da Trava `f1ed9ad`→`d0e89cd`; `.gitattributes` na raiz de `bora_app/`;
  10/10 testes da trava OK. Ver também `../convencoes.md` (Windows/encoding).

> Primeira lição registada pelo `bibliotecario-cerebro` (teste do ciclo de escrita — Fase 2).
