---
id: memoria-claude-ai-livro-porta-unica
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Livro — porta única: como ligar qualquer IA ao livro (MCP do Córtex ou LIVRO.md com senha)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-porta-unica`, origem `claude-code`, atualizada em 2026-10-29T14:57:01.895087+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro porta unica · memoria claude.ai · claude_ai_memoria

# Livro — porta única: como ligar qualquer IA ao livro do Bora

Missão final-app-2026-10-29, bloco 8. Vale para Claude.ai, Claude Code, Hermes, ChatGPT, DeepSeek ou qualquer IA nova. O livro é um só: a tabela `public.claude_ai_memoria` (Supabase `ojykpzwqrtusfeakzrna`). O Córtex é o espelho dela (de 30 em 30 min, minutos 7 e 37) e o `LIVRO.md` é a cópia plana para quem não tem MCP. Nenhuma palavra-passe vive nesta página: o espelho do Córtex é público no GitHub.

## Caminho A — ferramenta com MCP (o melhor)

1. Na ferramenta, adicionar um servidor/conector MCP remoto com o endereço `https://cortex.srv1786862.hstgr.cloud/` (HTTP, sem token fixo).
2. A autenticação é OAuth 2.1 com registo dinâmico do cliente (PKCE S256, scope `cortex`): `/.well-known/oauth-authorization-server`, `/register`, `/authorize`, `/token`. A ferramenta abre a página de autorização do Córtex e o Danilo aprova no navegador (perfil Danilo). A credencial dessa página fica só no Córtex e no gestor de senhas dele; não se escreve em páginas, relatórios nem e2e_log.
3. Depois de autorizado, a ferramenta passa a ter `cortex_buscar`, `cortex_ler`, `cortex_listar`, `cortex_escrever` (só páginas que já existem, zona verde) e `cortex_propor`.
4. Começar por `cortex_ler` com o id `memoria-claude-ai-livro-indice`; qualquer página do livro tem o id `memoria-claude-ai-<pagina>`.
5. Se a ferramenta perder o acesso depois de a VPS ser reiniciada, é só autorizar outra vez (skill `cortex-mcp-reauth-apos-redeploy`).

## Caminho B — ferramenta sem MCP: o ficheiro plano

- Tudo (todas as páginas, cerca de 2,4 MB): `https://livro.srv1786862.hstgr.cloud/LIVRO.md`
- Versão curta (índice, regras, erros e o último digest, cerca de 34 KB): `https://livro.srv1786862.hstgr.cloud/LIVRO-ESSENCIAL.md`
- Acesso com Basic Auth: utilizador `livro`. A palavra-passe NÃO está aqui. Está em `/opt/data/livro/.senha` na VPS (só root lê, modo 600). Quem tem SSH à VPS (Claude Code) lê-a de lá e entrega-a à ferramenta (está também na página à parte `livro-porta-unica-senha`, título [PESSOAL]: o sync não a põe no espelho público nem no `LIVRO.md`; lê-se pelo Supabase MCP no Claude.ai ou no Claude Code); a ferramenta manda-a no cabeçalho `Authorization: Basic`. Nunca na barra de endereço.
- O ficheiro é regenerado pelo mesmo sync de 30 em 30 min. Fica de fora tudo o que tem título `[PESSOAL]`; as linhas com cara de segredo (chaves, tokens, senhas com valor) são retiradas; e-mails, telefones, IBAN e NIF aparecem mascarados. Nomes próprios de pessoas podem continuar nas páginas operacionais: por isso o `LIVRO.md` não vai para motores grátis que treinam com o conteúdo.
- Só leitura. Quem lê não grava: se o Danilo corrigir a ferramenta, ela escreve "errei / regra certa" e o Claude Code grava com `select public.livro_aprender(...)`.

## Texto de arranque para colar numa IA nova

1. Antes de agir, lê o livro do Bora: `https://livro.srv1786862.hstgr.cloud/LIVRO-ESSENCIAL.md` (curto) e, se precisares de mais, `https://livro.srv1786862.hstgr.cloud/LIVRO.md` (utilizador "livro"; a palavra-passe dá-ta o Danilo).
2. Se tens MCP, liga ao Córtex em `https://cortex.srv1786862.hstgr.cloud/` (OAuth) e lê `memoria-claude-ai-livro-indice`.
3. Ordem de leitura: erros-aprendidos, regras-do-danilo, o digest mais recente; mandam sobre qualquer hábito teu.
4. O Danilo não é programador: português simples, texto corrido, sem jargão; "feito" só com prova; dinheiro, preços e Stripe só com o "autorizo" dele.
5. Se ele te corrigir, não gravas daqui: escreve "errei: ... / regra: ..." para o Claude Code gravar no livro; nunca copies o livro para fora, nem páginas pessoais ou dados de clientes.

## Como isto está montado (para quem mantém)

- Cron root `7,37 * * * *` corre `/opt/data/bin/sincroniza-memoria-claude.sh`. Por ordem: `livro_indice.py` (sincroniza as skills e regenera o `livro-indice`, só grava se o texto mudou), o espelho para o Córtex (`_sincroniza_memoria_claude.py` + git), e `livro_export.py` (gera `/opt/data/livro/publico/LIVRO.md` e `LIVRO-ESSENCIAL.md`, a limpeza está em `livro_limpar.py`; se a limpeza falhar, mantém o ficheiro anterior). O registo está em `/opt/data/bin/sincroniza-memoria-claude.log`.
- O endereço é servido por um contentor `bora-livro-web` (nginx:alpine) atrás do Traefik, certificado Let's Encrypt, Basic Auth e limite de pedidos. Configuração em `/opt/data/livro/nginx/`. Só os dois ficheiros em `/opt/data/livro/publico/` são servidos.
- Trocar a palavra-passe: apagar `/opt/data/livro/.senha` e correr `bash /opt/data/bin/livro_web_setup.sh` (gera outra, refaz o htpasswd e reinicia o contentor).
- Skills: o repo manda (PC → git → espelho da VPS, lido pelo Hermes). As que o Hermes cria ficam em `/opt/data/livro/skills/da-vps/` com o `DIFERENCA.md`; no PC `node ~/.claude/livro/puxar-skills-da-vps.mjs` mostra e `--aplicar` copia para o repo sem apagar nem fazer commit.

