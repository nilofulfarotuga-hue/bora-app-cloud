# Skills que ficaram FORA da pasta comum (e porquê)

> Missão `livro-comum-2026-10-23`, adendo do Danilo de 23/10 ("a do Claude Code, a sua e a deles vão
> ser uma só"). Análise feita a 25/10/2026 sobre as três pastas: repo (61 + 12 novas), PC
> `~/.claude/skills` (135 com subpastas) e Hermes `/opt/data/skills` (93 ativas; as outras ~190 são
> cópias de arquivo/curadoria em `.archive`, `.curator_backups`, `.hub`).
> **Nada foi apagado.** O que está aqui continua onde estava; só não entrou na pasta comum.

## Regra de escolha

- Uma versão de cada skill, a melhor, aqui em `.claude/skills/` com `SKILL.md` e frontmatter `name`/`description`.
- Repetidas entre o repo e o PC (52): ficou a do **repo**. As do PC eram cópias antigas (algumas diziam
  "CÓPIA de bora_app"); as diferenças eram finais de linha ou o repo mais recente. As do PC foram
  substituídas pela versão do repo pelo espelho; a pasta anterior está em `~/.claude/skills.bak-2026-10-25`.
- Só do PC (68): entraram 66. Licenças de terceiros verificadas na origem: ver `LICENCAS-TERCEIROS.md`.
- Skills do Hermes que prestam entram como `hermes-<nome>/`, depois de revistas pelo bot `critico`.

## Fora por licença (nunca copiar para o repo nem para o Hermes)

- `docx`, `pdf`, `pptx`, `xlsx`, `chrome-browser`, `built-in-browser`, `computer-use` (PC, `~/.claude/skills/synced/`) — licença proprietária da Anthropic. Para Word/Excel/PDF/PowerPoint no Hermes, escrever skills próprias do zero (python-docx, openpyxl, pypdf, python-pptx).
- `file-reading`, `pdf-reading` — idem (não estavam no PC; ficam proibidas).
- `artifact-emulator`, `deep-research`, `docs`, `google-workspace`, `import-memory`, `morning`, `skill-creator` (cópia em `synced/`) — skills da plataforma Claude sincronizadas pela app; dependem de ferramentas que só existem lá. A `skill-creator` de licença aberta já está na pasta comum.
- `testsprite-onboard`, `testsprite-verify` (PC) — origem/licença não verificável (o repositório público da TestSprite não foi encontrado); o repo bora-app-cloud é público.

## Fora por não serem skills ou por serem do motor do Hermes

- `sistema/` (PC) — não tem `SKILL.md`; são relatórios de identificação.
- Hermes, 67 de fábrica — vêm com o programa Hermes Agent e dependem do ambiente dele; ficam em `/opt/data/skills` e o Hermes continua a usá-las:
  - `apple/`: apple-notes, apple-reminders, findmy, imessage, macos-computer-use
  - `autonomous-ai-agents/`: claude-code, codex, hermes-agent, opencode
  - `creative/`: architecture-diagram, ascii-art, ascii-video, baoyu-infographic, claude-design, comfyui, design-md, excalidraw, humanizer, manim-video, p5js, popular-web-designs, pretext, sketch, songwriting-and-ai-music, touchdesigner-mcp
  - `data-science/`: jupyter-live-kernel · `dogfood/`: dogfood · `email/`: himalaya · `note-taking/`: obsidian · `smart-home/`: openhue · `social-media/`: xurl · `yuanbao/`: yuanbao
  - `github/`: codebase-inspection, github-auth, github-code-review, github-issues, github-pr-workflow, github-repo-management
  - `media/`: gif-search, heartmula, songsee, youtube-content
  - `mlops/`: huggingface-hub, llama-cpp, weights-and-biases
  - `productivity/`: airtable, google-workspace, maps, nano-pdf, notion, ocr-and-documents, powerpoint, teams-meeting-pipeline
  - `research/`: arxiv, blogwatcher, llm-wiki, polymarket, research-paper-writing
  - `software-development/`: hermes-agent-skill-authoring, node-inspect-debugger, plan, python-debugpy, requesting-code-review, simplify-code, spike, systematic-debugging, test-driven-development
- Hermes `mlops/evaluation/lm-evaluation-harness`, `mlops/inference/vllm`, `mlops/models/audiocraft`, `mlops/models/segment-anything` — instaladas do hub; servidores de modelos e investigação de IA, sem uso no negócio do Danilo.
- Hermes `mattpocock/*` (10) — repetidas: a mesma skill (origem mattpocock/skills, MIT) já está na pasta comum.

## Skills do Hermes revistas pelo critico (25/10/2026)

Revisão feita pelo bot `critico` do Hermes (perfil `critico`, uma linha por skill). As aprovadas entraram aqui
como `hermes-<nome>/` (o IP interno do Tailscale e o nome do PC foram trocados por marcadores, porque o repo é
público). As originais continuam em `/opt/data/skills/` e o Hermes continua a tê-las.

Entraram (APROVADA): `hermes-multi-asset-web-project`, `hermes-email-management-himalaya`,
`hermes-desbloqueio-zona-vermelha`, `hermes-remote-delegation-gate`, `hermes-web-content-extraction`,
`hermes-competitive-feature-audit`.

Ficaram fora:
- `devops/remote-command-execution` — REPROVADA: tem IP e utilizador SSH fixos e permite executar comandos arbitrários sem controlo.
- `hermes-agent/buzz-platform-operation` — REPROVADA: irrelevante para o Bora e manda publicar mensagens para fora sem confirmação.
- `hermes-agent/hermes-auto-configuracao` — REPROVADA: manda guardar segredos no `.env` e esconder falhas de ferramentas em vez de as reportar. **Está em uso pelo Hermes: contradiz a regra de honestidade; reportado.**
- `hermes-agent/hermes-operacao-confiavel` — REPROVADA: fala em autoresponder de e-mail, contra "mensagens para fora só com confirmação".
- `hermes-agent/socio-ai-onboarding` — REPROVADA: inventa conectores que o Hermes não tem; teoria sem utilidade prática.
- `hermes-agent/future-project-registration` — sem veredito (o critico passou dos 300 s); fica fora até nova revisão.

Regra para o futuro (Bloco 4b): skill nova que o Hermes criar entra como `hermes-<nome>/` num ramo próprio
(`skills-hermes-AAAA-MM-DD`), só depois de o `critico` a aprovar; nunca direto no ramo de produção.
