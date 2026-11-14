# Poupança medida (bloco 2.5, 14/11/2026)

Medição: `claude -p "/context"` numa sessão nova na pasta `C:\BoraLocal\projetosflutter\bora_app`
(o mesmo arranque que o Danilo usa). Não gasta modelo: o `/context` é local.

## Antes (12:55) → depois (13:10)

- Total ao arrancar: **58,3 mil → 48,7 mil tokens** (−9,6 mil, −16%).
- Ficheiros de memória: 29,1 mil → 19,5 mil.
  - Índice de memória do Claude Code (`MEMORY.md`): 9,4 mil → 1 mil. Partido em 8 sub-índices por tema;
    as 232 ligações continuam todas lá (230 nos sub-índices novos + 2 nos que já existiam).
  - Cópia dos erros do livro (`~/.claude/cache/livro/erros.md`, importada pelo CLAUDE.md global): 4,1 mil →
    2,9 mil (guarda o FIM da página, que é onde entram as correções novas).
- Skills: 9,9 mil (a cortar no bloco 2-bis). Agentes: 4 mil (bloco 2-ter).
- Ferramentas MCP: já estão em modo adiado. Custo real ao arrancar ≈ 3 mil (647 de ferramentas + 2,3 mil de
  instruções dos servidores). Os 31,5 mil medidos antes eram de uma sessão sem a pesquisa de ferramentas.

## Defeito encontrado e corrigido

O gancho de arranque do repo (`injeta-digest.sh`) emitia ~15 mil caracteres. Acima de ~10 mil, o Claude Code
guarda a saída do gancho num ficheiro e ela não entra no contexto: o digest estava a perder-se quase todo
(no `/context`, "Messages" = 2,7 mil). Agora tem teto total de 9 500 caracteres, com as 25 últimas linhas de
erros-aprendidos primeiro (vale depois de a Claude.ai juntar o ramo).

## O que fica por cortar (propostas, por ordem de ganho)

1. Lista de skills (9,9 mil): descrições curtas e duplicadas fundidas — bloco 2-bis.
2. `CLAUDE.md` do projeto (4 mil): metade é texto antigo (diz "No test suite exists", "Current Focus" de abril)
   e repete o `PADRAO_BORA.md`; pode ficar com 1 mil a apontar para os ficheiros. Mexe nas regras do repo:
   fica para a Claude.ai decidir.
3. `regras.md` (3,7 mil) + `AGENTS.md` (3 mil) dizem quase o mesmo; o CLAUDE.md global podia importar só um.
4. Conectores do claude.ai pouco usados no Claude Code (Higgsfield, Canva, Glovo, Play Sheet Music): desligar
   no `/mcp` quando a missão não os usa poupa as instruções deles (a do Higgsfield é a mais comprida).
5. Agentes (4 mil): os 33 agentes entram todos em todas as sessões — bloco 2-ter.
