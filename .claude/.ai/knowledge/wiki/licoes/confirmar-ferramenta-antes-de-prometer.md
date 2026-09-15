---
id: licao-confirmar-ferramenta-antes-de-prometer
tipo: licao
origem: [sessão 2026-07-08: repoint do Obsidian pedia "agente de UI" e obsidian.json inexistente]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# Lição — confirmar que a ferramenta **existe** antes de prometer o passo

**Problema.** O Bloco 0.1 pedia "repontar a app Obsidian **via agente de UI**". Não há ferramenta de
automação de **desktop** disponível (só browser: claude-in-chrome/playwright), e o `obsidian.json`
não existe em `%APPDATA%\Roaming` nem em `Local`.

**Tentativas que falhariam.** Prometer o clique e "fingir" o repoint; ou editar um `obsidian.json`
que não existe.

**Porquê.** Assumir capacidades (desktop click) e ficheiros (config) sem verificar.

**Solução (regra generalizável).** Antes de prometer um passo que depende de uma ferramenta/ficheiro,
**confirmar que existe** (`ls` o config, listar as tools). Se não existe → **executar o que dá,
documentar o passo manual exato, e sinalizar a limitação no relatório** — não inventar a capacidade.
