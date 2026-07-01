---
tema: licoes-index · escopo: projeto · estado: atual · atualizado: 2026-07-01
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

*(Ainda sem lições registadas — a pasta enche à medida que os agentes entregam handoffs.)*
