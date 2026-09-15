---
tema: licao-anti-trapaca-base-stale · escopo: projeto · estado: atual · atualizado: 2026-07-02
id: licao-anti-trapaca-base-stale
tipo: licao
origem: [.claude/juiz/anti_trapaca.py, branch autonomous-night-2026-04-29]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Lição: anti_trapaca.py com base default numa branch longa = falso-positivo

**O que aconteceu (2026-07-02, sessão O BANQUETE):** o chão anti-trapaça REJEITOU
com 2222 ficheiros alterados e 2 "testes desativados" — mas eram skips e2e
pré-existentes de sessões antigas. A base default é `merge-base main HEAD`, e a
branch `autonomous-night-2026-04-29` divergiu de `main` há meses.

**Como fazer:** em sessões sobre esta branch, correr o chão contra a base da
PRÓPRIA sessão:

```
python .claude/juiz/anti_trapaca.py --base <commit-inicial-da-sessao|HEAD>
```

`--base HEAD` valida o trabalho não-commitado; usar o hash do início da sessão
valida a sessão inteira. Ficheiros novos (untracked) não aparecem no diff — não
conseguem apagar/enfraquecer testes, por definição.

**Nota:** o Danilo confirmou este falso-positivo no prompt da sessão. Fix
estrutural possível (futuro): anti_trapaca.py gravar um marcador de base por
sessão em `.claude/juiz/.base`.
