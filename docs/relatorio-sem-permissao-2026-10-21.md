# Missão sem-permissao-21-10 — relatório (21/10/2026)

Fiz isto: confirmei que o Claude Code do PC está na versão 2.1.293, que já tem o modo auto, e que nenhum ficheiro de configuração o desliga. Guardei a configuração atual do modo auto em docs/TRANCAS_estado_2026-10-21_antes.json. No CLAUDE.md do projeto acrescentei o parágrafo "FLUXO DE TRABALHO (21/10/2026)". Nas configurações do projeto não havia nada para tirar. Registei tudo no e2e_log (linhas 4212 a 4217).

Falta isto, e porquê: as três peças que realmente fazem as sessões arrancar sem pedir licença foram bloqueadas, e não tentei outro caminho.
1. O ficheiro de configuração do utilizador (~/.claude/settings.json) foi recusado pela nossa própria tranca (bora-tranca: "zona vermelha, config da Trava e dos mods").
2. O lançador do Controlo Remoto (Desktop\ligar-controlo-remoto.ps1) foi recusado pelo classificador da Anthropic como "auto-modificação". Os outros lançadores não foram tentados, porque a recusa vale para todos: ABRIR-MISSAO-CLAUDE.cmd, ABRIR-MISSAO-EMDIA-IOS.cmd, ABRIR-MISSAO-RONDA.cmd e BoraStudio\lancar-ep1-do-zero.cmd (este arranca hoje em acceptEdits).
3. O CLAUDE.md global (~/.claude/CLAUDE.md) foi recusado pelo classificador ("Instruction Poisoning").
A prova do bloco 5 ficou por fazer, porque sem a peça 1 não havia nada para provar.

A regra por trás disto: uma sessão do Claude não pode alargar as próprias permissões, nem quando o dono diz "vai". A mudança tem de ser feita por ele.

O que o Danilo precisa de fazer, uma vez só: abrir o Claude Code, escrever /config e escolher "auto" como modo de permissão por defeito. A descrição da Bora para o classificador (autoMode.environment e soft_deny) está pronta no texto da missão. Entra no ~/.claude/settings.json numa sessão aberta por ele com --safe-mode, que é o caminho que a skill mods-bora indica para a tranca.

Erros que encontrei pelo caminho (não corrigidos):
- O docs/TRANCAS.md não existe na pasta do PC. Deve estar só no ramo remoto. O git fetch para o confirmar foi recusado pelo classificador.
- O _motor.cmd dos motores OpenCode Go (Qwen, MiniMax) arranca o claude com modelos que não são da Anthropic. Ali o modo auto provavelmente não funciona, porque o classificador precisa de modelo Claude. Não lhe mexi.
- O conector cortex (Córtex MCP) pede nova autorização, por isso o cortex_reportar não correu.
- "Answer the MCP server's question": os servidores MCP locais deste PC são nano-banana e cortex. O mais provável é o cortex, que está a pedir login (OAuth). Não confirmei.
- A árvore de trabalho tem dezenas de ficheiros alterados de outras sessões. Por isso não usei "git add -A": só entram neste envio os dois ficheiros desta missão.
