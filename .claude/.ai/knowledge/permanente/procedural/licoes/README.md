---
tema: licoes-index · escopo: projeto · estado: atual · atualizado: 2026-07-05
id: licoes-index
tipo: conceito
origem: [.claude/.ai/knowledge/PROTOCOLO.md]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 📖 Lições — como esta pasta cresce

> Cada lição = uma aprendizagem verificada que evita repetir um erro. **Só o
> `bibliotecario-cerebro` escreve aqui** (via handoff — ver `../../../PROTOCOLO.md`).

## Formato de uma lição (1 ficheiro por lição ou agrupadas por tema)
```
---
tema: licao-<slug> · escopo: projeto|agente:<nome> · estado: atual · atualizado: <data>
---
# <título curto>
- **Contexto:** o que se estava a fazer.
- **O que correu mal / a descoberta:** o facto.
- **Regra a aplicar:** o que fazer da próxima vez.
- **Evidência:** commit / ficheiro:linha / data.
```

## Regras
- Uma lição só entra **apoiada no que aconteceu** (não invenção) e **depois de dedup**.
- Se contradiz uma lição antiga → a antiga fica `estado: superado (por <esta>, <data>)`.
- Ficheiro que passe ~24 KB → partir por sub-tema. O Bibliotecário atualiza o `INDEX.md`.

## Lições registadas
- `licao-crlf-sh-eol.md` — CRLF em scripts `.sh` no Windows.
- `licao-asserts-weakened.md` — não enfraquecer asserções de teste (Juiz).
- `licao-anti-trapaca-base-stale.md` — em branch longa usar `--base` da sessão.
- `licao-context-watch-getter.md` — getter com `context.watch` em callback → crash (2026-07-05).
