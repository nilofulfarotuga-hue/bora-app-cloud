---
id: memoria-claude-ai-livro-hermes-skills
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-10-29
zona: verde
confianca: alta
estado: atual
---

# Skills do Hermes (as que criou + lista das de fábrica), cópia noturna

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `livro-hermes-skills`, origem `hermes`, atualizada em 2026-10-29T23:40:10.937295+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: livro hermes skills · memoria claude.ai · claude_ai_memoria

# Skills do Hermes (cópia de 2026-10-29)

Skills que o Hermes criou sozinho: 14. Vindas de fábrica ou instaladas: 81. Fonte única das skills partilhadas: .claude/skills/ do repo bora-app-cloud (espelho na VPS em /opt/data/cortex-brain/.claude/skills). Skill nova do Hermes entra lá como hermes-<nome>, revista pelo critico.

## Criadas pelo Hermes

### multi-asset-web-project (creative/multi-asset-web-project)

---
name: multi-asset-web-project
description: Use when the user asks for multiple HTML/CSS/JS artifacts in one request such as creating 10 websites for 10 businesses. Complements claude-design for project structure, per-category design differentiation, and ZIP archive output. Treat as a project with structured directories.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [html, css, multi-asset, project, web, creative, design]
    related_skills: [claude-design, sketch, popular-web-designs]
---

# Multi-Asset Web Project

## When to Use

- User asks: "create N websites for N businesses", "generate multiple HTML pages for different clients", "make a bundle of landing pages"
- The deliverable is N distinct HTML artifacts bundled together (ZIP, tar.gz, directory)

## Core Method

intake  arrow  structure  arrow  design-each  arrow  verify-each  arrow  archive

## Directory Structure

```
project_root/
item_1_business_slug/
  index.html
  style.css
item_2_business_slug/
  index.html
  style.css
...
archive.zip
```

### Naming Convention
- Project root: descriptive name based on the deliverable
- Item subfolders: sortable prefix + business slug (e.g., negocio_1_casa_tia_ciata)
- Item files: index.html + style.css only (flat, no nested directories)

## Design Differentiation by Category

When each artifact maps to a business type, each should get a genuinely different design system.

Rule: Each site must differ in at least 3 of these 6 dimensions:
1. Background: light, dark, gradient direction
2. Palette: warm, cool, monochrome, accent color
3. Typography: serif-ish, bold, airy, compact
4. Layout: grid, list, card-based, two-column
5. Section structure: sticky nav, hero+grid, info+description
6. Button treatment: pill, boxed, outlined, inline

### Business-Type Design Postures

| Type | Posture | Key choices |
|---|---|---|
| Restaurant/Bar | Warm, inviting | Earth-tone gradient header, sticky nav, center-aligned tagline |
| Fast food/Burger | Bold, playful | Menu grid, prominent CTA, red/orange palette, burger cards |
| Market/Mall | Informational | Two-column layout, clean sans-serif, high readability |
| Liquor store | Dark, premium | Dark bg, green/black gradient, gold accent for ratings |
| Hardware/Construction | Industrial | Brown/tan gradient, bordered list items, sturdy sans-serif |
| Bakery/Sweets | Sweet, light | Specialty grid, soft pastels, decorative header, card layout |
| Gym/Fitness | High-energy | Black bg, red gradient, white cards with red accents, gold ratings |
| Automotive/Mechanic | Functional | List-based services, contact card with shadow, blue/white palette |
| Pharmacy/24h | Clean, clinical | Services grid, 24h badge, professional blue, contact emphasis |
| Hotel/Lodging | Elegant, calming | Hero area, amenity grid, booking CTA, warm neutral palette |

## Steps

### 1. Intake and Planning
List all items with their data: name, category, address, phone, hours, ratings
Assign a sortable prefix + s
[... cortado]

### remote-command-execution (devops/remote-command-execution)

---
name: remote-command-execution
description: Executes commands on the user's remote PC via SSH.
tags:
  - ssh
  - remote-execution
  - cli
category: devops
---

# This skill enables executing commands on the user's remote PC using a pre-configured SSH connection.
# It uses a specific SSH command that includes Tailscale for proxying and bypasses strict host key checking for convenience.
# This skill should be used when direct command execution on the remote PC is required.

# Workflow:
# 1. The agent constructs the full SSH command, embedding the user's specific command.
# 2. The agent uses the `terminal` tool to execute this SSH command.
# 3. The agent captures and returns the output (stdout and stderr) and exit code of the command.

# Pitfalls:
# - The remote PC must be accessible via Tailscale and the SSH server must be running.
# - The `StrictHostKeyChecking=no` option is used for convenience, but may have security implications in untrusted networks.
# - Ensure the command to be executed is correctly formatted and valid.
# - **Windows CMD escaping**: when the command contains special characters (quotes, pipes, redirects, etc.), prefer the `pc` wrapper script at `/opt/data/bin/pc` (aliased as `pc` in PATH). It encodes the command in Base64 (stripping newlines and `=` padding) and invokes `run-claude.cmd --b64 <payload>` on the Windows side, avoiding CMD escaping bugs entirely.
# - The SSH host alias is `bora-pc` (defined in `~/.ssh/config`), NOT a raw IP. If Tailscale IP changes, only the SSH config needs updating.

# Example Usage:
# agent.call(skills.remote_command_execution.execute(command="echo 'Hello from remote!'"))
# agent.call(skills.remote_command_execution.execute(command="ls -l /home/hermes"))

# Configuration Note:
# The SSH command is hardcoded within the skill for consistency. If the connection details change,
# the skill will need to be updated.

def execute(command: str):
  """
  Executes a given command on the user's remote PC via SSH.

  Args:
    command: The command string to execute on the remote PC.
  """
  ssh_command = f"ssh -o ProxyCommand=\"tailscale nc %h %p\" -o StrictHostKeyChecking=no bora-pc \"{command}\""
  return terminal(command=ssh_command)

### email-management-himalaya (email/email-management-himalaya)

---
name: email-management-himalaya
category: email
description: Gerencia e-mails usando a CLI himalaya, incluindo listagem, leitura e exclusão.
---

### Propósito

Esta skill descreve como interagir com o cliente de e-mail `himalaya` via terminal para realizar operações básicas como listar, ler e apagar e-mails.

### Comandos Essenciais

- **Listar envelopes (mensagens resumidas):**
  - Para listar os e-mails mais recentes, ordenados por data (mais novos primeiro):
    `~/.local/bin/himalaya envelope list --output json --page-size <NÚMERO> order by date desc`
    - Use `--page-size` para limitar o número de resultados (ex: `20`), não `--limit`.
  - Para listar com filtros específicos (ex: remetente, assunto, data):
    `~/.local/bin/himalaya envelope list --output json --page-size <NÚMERO> [QUERY]`
    - Exemplos de `QUERY`: `subject "foo"`, `from "<endereco@email.com>"`, `after 2026-07-08`.

- **Mover mensagens para uma pasta:**
  - `~/.local/bin/himalaya message move "<PASTA_DE_DESTINO>" <ID_DA_MENSAGEM(NS)>`
  - **Importante:** O nome da pasta de destino deve vir **antes** dos IDs das mensagens.
  - **Nome da Lixeira do Gmail:** Utilize `"[Gmail]/Trash"` para a lixeira (entre aspas).
  - Exemplo: `himalaya message move "[Gmail]/Trash" 173 172`

- **Ler um e-mail específico por ID:**
  - `~/.local/bin/himalaya message read <id_do_email> --output json`

- **Apagar um e-mail por ID:**
  - `~/.local/bin/himalaya message delete <id_do_email>`
  - ⚠️ **CUIDADO:** Esta operação é irreversível. Sempre confirme com o usuário antes de apagar e-mails críticos.

### Pitfalls e Workarounds

- **Sintaxe de busca complexa:** A sintaxe de pesquisa do `himalaya` pode ser complexa e não intuitiva (ex: `from: Uber` pode falhar). Se a busca direta via `envelope list <query>` falhar repetidamente ou for muito complexa, a abordagem recomendada é:
  1.  Listar um número maior de envelopes (e-mails) usando `envelope list --page-size <numero_grande>`.
  2.  Filtrar os e-mails programaticamente usando Python, processando a saída JSON. Isso oferece maior flexibilidade e robustez.

### Workflow Típico

1.  **Listar e-mails:** Use `envelope list` para obter uma visão geral dos e-mails.
2.  **Identificar e-mails de interesse:** Analise o JSON retornado para encontrar IDs de e-mails relevantes (ex: filtrando por `from` ou `subject` no Python).
3.  **Ler conteúdo (se necessário):** Use `message read <id>` para obter o conteúdo completo de um e-mail e aplicar critérios mais detalhados.
4.  **Decidir ação:** Com base nos critérios do usuário (ex: guardar importantes, apagar irrelevantes), prepare as operações de exclusão.
5.  **Apagar:** Use `message delete <id>` para remover os e-mails indesejados, sempre com confirmação do usuário se a ação for destrutiva.

### buzz-platform-operation (hermes-agent/buzz-platform-operation)

---
name: buzz-platform-operation
category: hermes-agent
description: Operar como sessão per-canal do Hermes dentro da plataforma Buzz (Nostr) — preflight do `buzz` CLI, padrões de menção/threading, disciplina de publicação, e criação de agents/rascunhos. Acionada quando o contexto da sessão estabelece o modelo per-canal Buzz (relay, canais, `buzz` CLI, `[Context]` block com channel UUID e reply-to).
---

# Buzz Platform Operation — sessão per-canal do Hermes

## Gatilho

Usar sempre que a sessão correr dentro da plataforma Buzz: o system prompt estabelece o
modelo "uma sessão por canal", menciona `buzz` CLI, relay Nostr, `BUZZ_*` env vars, ou
o bloco `[Context]` traz `Channel: <uuid>` e `--reply-to <event-id>`. Isto é um modo de
operação distinto do Telegram (SOUL.md) — regras de comunicação diferentes aplicam-se.

## Objetivo

Responder, publicar e delegar dentro de Buzz corretamente: usar o `buzz` CLI como interface
primária, respeitar menções/threading/publish-discipline, e não desperdiçar turnos em
infra-quando o humano pediu uma resposta imediata.

## Preflight (Antes de Qualquer Operação no Relay)

⚠️ **Correr o preflight no BOOTSTRAP da sessão Buzz, antes de qualquer humano fazer
@mention exigindo resposta imediata.** O erro clássico (observado 2026-08-11) é skipar
o preflight no arranque, descobrir a ausência do `buzz` a meio de uma resposta urgente,
e queimar o turno à procura do binário enquanto o humano espera. O preflight define a
postura de publishing para TODA a sessão: se `buzz` falta, sabes ANTES de precisar dele.

1. **Verificar o binário `buzz` no PATH** (uma vez, no início da sessão):
   ```bash
   command -v buzz && buzz --help >/dev/null 2>&1 && echo "buzz-ok" || echo "buzz-missing"
   ```
   Se `buzz-missing`: NÃO tentar `buzz` diretamente. Ver `references/buzz-cli-discovery.md`
   para os caminhos do skill package e opções de instalação. **Não retratar "buzz não funciona"
   como uma regra permanente** — é estado de setup, resolvível pelo utilizador/dono.
   Marcar mentalmente para a sessão: "publishing não disponível — entregar respostas no body
   da reply com nota curta; resolver infra fora de banda, depois do turno urgente."

2. **Verificar env vars (sem imprimir valores):**
   ```bash
   test -n "${BUZZ_RELAY_URL:-}" && echo "RELAY=set" || echo "RELAY=unset"
   test -n "${BUZZ_PRIVATE_KEY:-}" && echo "KEY=set" || echo "KEY=unset"
   test -n "${BUZZ_AUTH_TAG:-}" && echo "AUTH_TAG=set" || echo "AUTH_TAG=unset"
   ```
   `BUZZ_AUTH_TAG` é necessário para `buzz agents draft-create/draft-update`. Se ausente,
   explicar que este managed agent não pode abrir drafts de agente revisados pelo owner
   a partir do chat.

3. **Descobrir comandos authoritative:**
   ```bash
   buzz --help
   buzz <group> --help        # ex: buzz messages --help
   buzz <group> <cmd> --help
   ```
   Não adivinhar flags da memória. O skill package em `/opt/data/.claude/skills/buzz/`
   tem `references/commands.md` com workflows comuns.

## Interfa
[... cortado]

### desbloqueio-zona-vermelha (hermes-agent/desbloqueio-zona-vermelha)

---
name: desbloqueio-zona-vermelha
description: "Protocolo para lidar com tarefas que tocam a Lista Vermelha (dinheiro/Stripe/pagamentos/RLS/auth/dispatch/pricing/ledger). O comando `ordem` recusa criar ordem para estas tarefas (exit 4). O fluxo correto: preparar PROPOSTA completa em texto, apresentar ao Danilo, aguardar 'vai' explícito, só então executar via PC/Claude Code ou aplicar via MCP direto."
tags: [zona-vermelha, lista-vermelha, dinheiro, pagamentos, stripe, governanca]
related_skills: [hermes-operacao-confiavel, socio-ai-onboarding]
---

# Desbloqueio de Zona Vermelha — Protocolo Operacional

## Princípio
**Nada que toque dinheiro real, Stripe, pagamentos, RLS/auth, dispatch_engine, pricing_service, finalizePurchase, bora_tokens, ledger, wallets, payouts, platform_settings de preços, ou migrações destrutivas vira ordem automática.** O comando `ordem` detecta estas palavras-chave e recusa (exit code 4).

## Fluxo Obrigatório

1. **Detectar** — o `ordem` devolve `ZONA_VERMELHA` + mensagem
2. **Preparar proposta** — texto completo com:
   - O que está pronto (migrações, código, colunas em produção, diffs no stash)
   - O que a proposta faz (resumo técnico)
   - Risco/impacto (zero regressão, só completa o que já existe)
   - Confirmação de que Lista Vermelha continua intacta
3. **Apresentar ao Danilo** — formato padrão: "⚠️ ISTO MEXE EM DINHEIRO. [resumo]. Responde 'vai' para eu aplicar."
4. **Aguardar "vai" explícito** — escrito nesta conversa
5. **Executar** — via `pc` (Claude Code no PC do Danilo) ou MCP direto (Supabase), **nunca** via `ordem`

## Palavras-chave que disparam Zona Vermelha (no script `ordem`)
```
dispatch_engine|pricing_service|finalizePurchase|bora_tokens|stripe|payment|webhook|wallet|ledger|refund|payout|commission|platform_settings|disable row level|force.?push
```

## Lição desta sessão (2026-09-22)
- A ordem 8448 (2 bugs TVDE) tinha **Bug #2 = Zona Vermelha** (bora_tokens + Stripe + tvde-plan-payment)
- O `ordem` recusou corretamente (exit 4)
- Preparei a proposta completa com tudo o que o veredito do Juiz + conselho confirmaram pronto
- O Danilo respondeu "vai" → agora posso executar via `pc` (não via `ordem`)

## Execução pós-"vai"
```bash
# Via PC (Claude Code no PC do Danilo) — preferido para tarefas complexas
pc "aplica migration tvde-plan-payment v10 tokens, deploy Edge Function tvde-plan-payment, reactiva toggle tokens ida-e-volta online"

# Ou via MCP direto se for só SQL/Deploy simples
```

## Erro Comum a Evitar
❌ Tentar contornar com `ordem "enfileira..."` ou `ordem "executa..."` — o script **sempre** vai recusar.
❌ Dizer "já apliquei" sem ter o "vai" do Danilo.
✅ Preparar proposta → aguardar "vai" → executar via `pc` ou MCP.

### future-project-registration (hermes-agent/future-project-registration)

---
name: future-project-registration
description: Register approved future projects and ideas in persistent memory and cortex, handling memory-full situations by consolidating stale entries. Use when the user approves a project idea for future development, says "guardar para depois", or explicitly requests storing a future initiative.
---

# Future Project Registration

Class-level skill for capturing approved future projects in durable storage while respecting memory constraints.

## When to Use

- User approves a project idea for future development
- User says "guardar para depois", "ideia futura", "projeto futuro"
- User explicitly requests storing a future initiative or SaaS idea
- Any non-immediate project that needs to be remembered across sessions

## Workflow

1. **Condense the project** into a single high-density memory entry:
   - One-line summary
   - Public target
   - Key features (bullet list, max 5-7 items)
   - Commercial objective
   - STATUS: future/active/blocked
   - Next step when initiating

2. **Check memory capacity** before adding:
   - If memory is near limit (>90%), proactively remove stale entries first
   - Remove least critical entries: environment quirks, transient tool notes, one-off fixes
   - Prefer removing entries that are redundant with SOUL.md or cortex

3. **Store in memory** using the memory tool:
   - Use `target: "memory"`
   - If add fails with capacity error, batch a remove+add in one operations array

4. **Report to cortex** with appropriate weight:
   - Use `cortex_reportar` with `peso: "grande"` for strategic projects
   - Include: what was stored, why, and the next-step trigger

5. **Confirm to user**:
   - Brief confirmation that the idea is saved
   - Mention the trigger condition for when it will be retrieved/acted upon

## Memory Management Rules

- Memory is 2,200 chars hard limit
- Priority order for removal when full:
  1. Environment-dependent failures (missing binaries, fresh-install errors)
  2. One-off task narratives
  3. Transient tool state notes
  4. Redundant entries already in SOUL.md
- Never remove: core identity, autonomy principles, critical infrastructure facts

## Output Format

When confirming to user:
```
✅ Guardei na memória.

[Project name]
- Público-alvo: ...
- Funcionalidades: ...
- Objetivo: ...
- STATUS: ...
- Próximo passo: ...

Registado no Córtex como [POR REVER] até a Claude.ai confirmar.
```

### hermes-auto-configuracao (hermes-agent/hermes-auto-configuracao)

---
name: hermes-auto-configuracao
category: hermes-agent
description: Como o Hermes Agent deve se auto-configurar e lidar com falhas de ferramentas, priorizando a autonomia e a entrega de resultados sem a necessidade de intervenção do usuário para cada passo. Inclui a diretriz de buscar feedback explícito ao criar skills complexas.
---

## Visão Geral

Esta skill define as diretrizes para a auto-configuração contínua do Hermes Agent, sua autonomia na execução de tarefas (especialmente pesquisa na internet) e a estratégia para lidar com falhas de ferramentas, buscando alternativas sem a necessidade de intervenção direta do usuário. Também aborda a metodologia para a criação de novas skills, priorizando a coleta de informações claras do usuário.

## Auto-Configuração e Melhoria Contínua

O Hermes Agent deve estar em um modo permanente de auto-melhoria, aprendendo com cada interação, feedback e resultado de tarefa. Todas as lições relacionadas à sua própria configuração, desempenho e uso de ferramentas devem ser gravadas na memória e no SOUL.md.

### Diretrizes:

1.  **Priorizar Feedback do Usuário:** O feedback do usuário sobre inconsistências, falhas ou preferências de workflow é a principal fonte de auto-configuração.
2.  **Gravar Lições Criticamente:** Lições aprendidas (ex: sobre uso de `websearch`, falhas de `web_extract`, ou métodos de `readpage`) devem ser gravadas de forma permanente.

## Autonomia e Resolução de Falhas de Ferramentas

Ao realizar tarefas que envolvem ferramentas (especialmente pesquisa na internet), o Hermes Agent deve agir com autonomia para garantir a entrega de resultados.

### Fluxo de Trabalho de Pesquisa na Internet:

1.  **Início com `websearch`:** A pesquisa inicial deve começar com `terminal: websearch "<pergunta>"`.
2.  **Escalada Automática em Caso de Falha/Insuficiência:**
    *   **Se `websearch` falhar ou os resultados não forem bons/suficientes**, o Hermes **NÃO DEVE** perguntar ao usuário.
    *   O Hermes deve **automaticamente tentar alternativas**, como `terminal: readpage <url>` (para links promissores encontrados) ou `terminal: browse "<tarefa_de_navegacao>"`.
    *   O objetivo é extrair e consolidar a informação relevante, entregando a resposta final ao usuário.

3.  **Entrega de Resultados, Não Perguntas:** O foco é sempre entregar a resposta ou a conclusão da tarefa, não a repetição de falhas ou pedidos de clarificação quando há alternativas exploráveis.

## Criação de Skills ("Masquil")

Ao ser solicitado a criar uma nova skill, e se houver incerteza sobre os detalhes para torná-la perfeita, o Hermes Agent deve seguir esta metodologia:

1.  **Proatividade na Criação:** Não hesitar em iniciar a criação da skill.
2.  **Evitar Chutes/Adivinhações:** Nunca preencher lacunas com suposições.
3.  **Busca Ativa de Informação:** Perguntar ao Danilo diretamente as informações específicas necessárias para aperfeiçoar a skill. A pergunta deve ser clara, explicando o que está sendo feito e por que aquela info
[... cortado]

### hermes-operacao-confiavel (hermes-agent/hermes-operacao-confiavel)

---
name: hermes-operacao-confiavel
category: hermes-agent
description: Orientações para a auto-melhoria contínua, uso eficaz de ferramentas gratuitas e garantia de confiabilidade do Hermes.
---

# Hermes: Operação Confiável e Auto-Melhoria Contínua

## Gatilho
Esta skill é acionada sempre que houver feedback do usuário sobre a consistência, confiabilidade, performance das ferramentas (especialmente `websearch`), gestão de recursos (memória, modelos), ou a necessidade de auto-configuração e melhoria contínua do Hermes.

## Objetivo
* **Gestão de Lockfiles (e-mail autoresponder):** Ao lidar com processos que usam `flock`, se o script falhar ao iniciar com "outra instância já corre", não assuma imediatamente que há um processo zumbi no `ps`. Verifique quem segura o lockfile com `ls -l /proc/*/fd/* | grep <lockfile>`. Se o processo for um fantasma ou zumbi, mate-o com `kill -9 <pid>`. Se o arquivo de lock persistir em estado de erro, a estratégia mais resiliente é remover o lockfile manualmente (`rm -f <lockfile>`) e, se necessário, atualizar o script para usar um novo arquivo de lock (ex: `.email-loop-2.lock`) para evitar conflitos com estados persistentes de kernel. Sempre valide que o novo processo subiu corretamente antes de encerrar o turno.

## Fluxo de Trabalho

1.  **Escuta Ativa e Interpretação de Intenção:**
    *   Sempre que o Danilo expressar frustração, dúvidas sobre a minha performance, ou der instruções para melhorar, interpreto isso como uma diretriz primária para auto-melhoria.
    *   Lembro-me que o Danilo fala por voz, então a `INTENÇÃO` é mais importante que a literalidade das palavras.

2.  **Reafirmação da Política de Gratuidade:**
    *   Reforço que opero *exclusivamente* com modelos e ferramentas gratuitas (ex: `websearch` via SearXNG).
    *   Se houver falha ou inconsistência, o problema reside na minha estratégia ou execução, não na indisponibilidade de ferramentas pagas.

3.  **Melhoria Contínua da Websearch:**
    *   Quando o `websearch` for usado e os resultados forem insatisfatórios ou genéricos, analiso a consulta e busco refinar os termos ou estratégias de pesquisa (ex: adicionar contexto, especificar tipos de informação).
    *   Se um `websearch` falhar ou retornar vazio, informo explicitamente ao Danilo e tento alternativas.

4.  **Gestão Ativa da Memória:**
    *   Monitoro o uso da minha memória (`memory` tool).
    *   Quando o Danilo fornece feedback crítico ou diretrizes para minha configuração, garanto que essas informações sejam gravadas, consolidando ou removendo entradas menos críticas se a memória estiver cheia.
    *   Priorizo a gravação de lições que previnem erros futuros ou atendem a preferências explícitas do usuário.

6.  **Verificação Proativa de Ferramentas:**
    *   Antes de solicitar informações ou usar uma ferramenta, sempre verifico proativamente sua disponibilidade e funcionalidade no meu ambiente (ex: `which <ferramenta>`). A ausência de uma ferramenta no meu PATH ou sua não configura
[... cortado]

### hermes-stt-config (hermes-agent/hermes-stt-config)

---
name: hermes-stt-config
description: "Configuração prática de STT (Speech-to-Text) para o Hermes Agent no ambiente de produção do Bora. Cobre o provedor local (faster-whisper), verificação real, integração com gateway e notas específicas do deploy."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, stt, faster-whisper, voice, transcription, config, bora]
    related_skills: [hermes-agent]
---

# Configuração STT do Hermes Agent — Ambiente Bora (Produção)

Este skill documenta a configuração real e verificada do STT (Speech-to-Text) no ambiente de produção do Hermes Agent que roda na VPS do Bora (Guarda, Portugal).

## Provedor Ativo

**`local` (faster-whisper)** — gratuito, roda localmente, sem API key.

## Arquivo de Configuração

**Local real:** `/opt/data/config.yaml` (não `~/.hermes/config.yaml` — `$HERMES_HOME` = `/opt/data`)

```yaml
stt:
  enabled: true
  provider: local
  local:
    language: pt
    model: base
```

## Componentes Instalados

| Componente | Versão | Local |
|------------|--------|-------|
| faster-whisper | 1.2.1 | `/opt/hermes/.venv/lib/python3.13/site-packages/` |
| Módulo STT do Hermes | — | `/opt/hermes/tools/transcription_tools.py` |
| Registry de providers | — | `/opt/hermes/agent/transcription_registry.py` |
| ABC do provider | — | `/opt/hermes/agent/transcription_provider.py` |

## Providers Suportados (built-in)

1. **local** — faster-whisper (padrão, gratuito)
2. **local_command** — wrapper para CLI `whisper` externo
3. **groq** — Groq Whisper API (gratuito, precisa `GROQ_API_KEY`)
4. **openai** — OpenAI Whisper API (pago, precisa `VOICE_TOOLS_OPENAI_KEY`)
5. **mistral** — Mistral Voxtral (precisa `MISTRAL_API_KEY`)
6. **xai** — xAI Grok STT (precisa `XAI_API_KEY`)

## Pipeline de Transcrição no Gateway

O gateway de mensagens (`/opt/hermes/gateway/run.py`) transcreve automaticamente:

1. Mensagens de voz chegam (Opus/OGG → `MessageType.VOICE`)
2. Arquivo é salvo em cache local (`~/.hermes/audio_cache/` ou `$HERMES_HOME/audio_cache/`)
3. `_enrich_message_with_transcription()` chama `transcribe_audio()` de `tools.transcription_tools`
4. Transcrição é pré-anexada à mensagem: `[The user sent a voice message~ Here's what they said: "texto"]`
5. Mensagem enriquecida segue para o loop do agente

Plataformas cobertas: Telegram, WhatsApp, Discord, Signal, Slack, etc.

## Verificação Real (Testada)

```bash
cd /opt/hermes && /opt/hermes/.venv/bin/python3 -c "
from tools.transcription_tools import transcribe_audio
result = transcribe_audio('/opt/data/voz/tmp/voz-5915f53913-piper.wav.wav')
print(result)
"
```

**Resultado:**
```json
{
  "success": true,
  "transcript": "Teste da voz do BODY, se ouve isto, esta tudo bem.",
  "provider": "local"
}
```

Formatos que funcionaram: `.ogg` (voz real Telegram/WhatsApp), `.wav` (Piper TTS)
Formatos que falharam: `.mp3` do edge-tts (dados inválidos/corrompidos — não é bug do STT)

## Troubleshooting

| Sintoma | Causa | So
[... cortado]

### socio-ai-onboarding (hermes-agent/socio-ai-onboarding)

---
name: socio-ai-onboarding
category: hermes-agent
description: Workflow para a transição do Hermes para um sócio AI proativo, com base no plano de fases (Olhos, Iniciativa, Voz de Sócio) definido com Danilo Fulfaro.
---

# Sócio AI Onboarding: O Plano de Transição para um Parceiro Estratégico

## Gatilho
Esta skill é acionada quando Danilo expressa o desejo de que o Hermes atue como um "sócio AI" proativo, capaz de tomar decisões, gerar ideias e contribuir estrategicamente para o Bora App, além da execução reativa de tarefas.

## Objetivo
Construir o **DaniloOS** - uma empresa digital viva - onde Hermes orquestra múltiplos agentes especializados. Meta: sistema que aprende, decide e evolui automaticamente.

### Arquitetura Alvo (DaniloOS)
```
Danilo Core (identidade/permanente)
    ↓
Hermes Orquestrador (não executor)
    ↓
Especialistas (Claude Code, Designer, QA, SEO...)
    ↓
Ferramentas & Memória
    ↓
Aprendizado & Evolução
```

### Camadas do Sistema
1. **Danilo Core** - Identidade digital: quem é, objetivos, regras de decisão
2. **Hermes** - Orquestração: coordena 100+ agentes, não executa
3. **Especialistas** - Agentes focados (Marketing, Programação, Design, Vendas...)
4. **Capacidades** - Skills evoluídas com histórico de versões e métricas
5. **Grafo de Conhecimento** - Conecta clientes ↔ projetos ↔ decisões ↔ resultados

## Fluxo de Trabalho (Plano em 3 Fases Incrementais)

### Fase A — Olhos (Semanas 1-2)
**Foco:** Adquirir acesso informacional e definir o norte estratégico.

1.  **Requisitos do Danilo:**
    *   **Autorizar Conectores (Crucial):** Danilo deve autorizar os conectores Stripe, Datadog e Supabase na interface da `claude.ai`. Isso permitirá ao Hermes acesso read-only a views de KPI e dados de negócio. **(Gargalo Principal para esta fase)**
    *   **Definir `NORTE.md`:** Danilo deve criar um documento `NORTE.md` (5 linhas) que inclua a missão do trimestre, os KPIs mais importantes e as metas do Bora App. Este documento servirá como a bússola estratégica do Hermes.
2.  **Ações do Hermes (Após requisitos do Danilo):**
    *   **Desenvolver Views de KPI (Read-Only):** Com acesso aos conectores autorizados, o Hermes irá criar e configurar views read-only para monitorar os principais KPIs do Bora App.
    *   **Criar Skill `daily-pulse`:** O Hermes desenvolverá uma skill para compilar e apresentar um "Pulso Diário" com informações críticas do negócio.

### Fase B — Iniciativa (Semanas 3-4)
**Foco:** Habilitar a proatividade do Hermes através de gatilhos automáticos.

1.  **Ações do Hermes:**
    *   **Configurar Cron Job de Pulso Diário:** Agendar um cron job diário (ex: às 07h) para executar a skill `daily-pulse`, gerando "cards" automáticos com insights e status na Central de Notificações.
    *   **Implementar Watchers:** Desenvolver e configurar watchers para eventos importantes (ex: erros em produção, novas reviews de usuários), que também gerarão "cards" na Central.

### Fase C — Voz de Sócio (Mês 2)
**Foco:** Refinar
[... cortado]

### remote-delegation-gate (remote-delegation-gate)

---
name: remote-delegation-gate
description: >
  Pre-flight gate for delegating work to a remote PC (via pc / Tailscale SSH /
  bridged Claude Code). Verifies the delegation channel is live BEFORE dispatching
  a task; attempts idempotent repair; and when the channel is irreparably offline,
  reports truthfully and proposes alternatives instead of fabricating results.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
category: devops
metadata:
  hermes:
    tags: [remote-execution, tailscale, ssh, delegation, preflight, fault-tolerance]
    related_skills: [claude-code, remote-command-execution]
---

# Remote Delegation Gate

## When to Use

Whenever a task must run on the **user's remote PC** (not in this container) and the
transport is the user's Tailscale-bridged `pc` command (or raw SSH to the remote
host). This gate exists because dispatching heavy/delegated work to an offline or
unreachable host silently stalls the session and tempts the agent to fabricate a
result.

The canonical trigger: a task is **too heavy for this container** (deep web
research + scraping + asset generation + ZIP output, etc.) and therefore routes
through `pc "<natural language task>"` — which depends on the Tailscale bridge to
the user's laptop/PC being online.

## Core Method

    verify  arrow  attempt-repair  arrow  dispatch  arrow  monitor

1. **VERIFY** the delegation channel is live with a fast round-trip (see Probe step).
2. **ATTEMPT REPAIR** only if down — idempotently restart the bridge from wherever it
   *can* be run (host or PC). Do not loop; bound to one attempt.
3. **DISPATCH** the real task only after a green round-trip.
4. **MONITOR** the dispatched job (use background + notify_on_complete, never block
   silently).

If the channel cannot be brought back, **stop and report the exact state**. Never
proceed as if the work completed.

## Probe (round-trip health check)

For the `pc` bridge (Tailscale SSH to the user's PC), confirm reachability in two layers:

```bash
# Layer 1 — node present & recently seen in Tailscale
tailscale status | grep -E 'laptop-2q09vqa1|100.71.105.7'
# Expected: a node line; watch for "offline, last seen Xm ago" or no row at all.

# Layer 2 — actual SSH round-trip (the only one that matters)
timeout 25 ssh -o ProxyCommand='tailscale nc %h %p' \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 \
  hermes@100.71.105.7 'echo BRIDGE_OK'
# Green iff it prints BRIDGE_OK within ~25s and exits 0.
```

Interpretation:
- `BRIDGE_OK` → channel healthy; safe to dispatch via `pc`.
- `Connection timed out` / `Connection to UNKNOWN port 65535 timed out` /
  100% packet loss on ping → node is **offline or unreachable**; do NOT dispatch.
- Partial state (`active; relay "xxx"; offline, last seen ...`) → still unreachable;
  treat as offline.

## Attempt Repair (bounded; host-side only)

The bridge repair script lives on the **host** (e.g. `/root/bora-bridge-up.sh`) and
must be executed from the **host** or from the 
[... cortado]

### web-content-extraction (research/web-content-extraction)

---
name: web-content-extraction
description: "Standard pipeline for extracting clean text/markdown from web pages. Covers the toolchain (readpage/Jina Reader, trafilatura, readability), validation patterns, and the Agent-Reach scope clarification."
category: research
tags:
  - web
  - extraction
  - jina-reader
  - trafilatura
  - agent-reach
  - readpage
  - research-pipeline
---

# Web Content Extraction — Standard Pipeline

## Trigger
Any task that needs to read a specific URL or search the web and extract clean content for analysis.

## The Pipeline (in order)

### 1. `readpage <url>` — **Primary extractor**
- Location: `/usr/local/bin/readpage` (shell wrapper)
- Backend: `https://r.jina.ai/<url>` (Jina Reader API)
- Cost: Free, no API key
- Output: Clean markdown with title, source URL, publish time
- Use for: **All single-URL reads** — news, blogs, docs, HN, etc.
- Example: `terminal: readpage "https://example.com/article"`

### 2. `trafilatura` via `uv run` — **Python fallback**
- Installed: `uv pip install trafilatura` (persists in uv cache)
- Call: `uv run python3 -c "import trafilatura; url='...'; d=trafilatura.fetch_url(url); print(trafilatura.extract(d, output_format='markdown'))"`
- Use when: Jina blocks a domain (paywall, anti-bot), or you need programmatic control
- Handles: Better main-content detection on some article sites

### 3. `readability-lxml` — **Installed but weak**
- `uv pip install readability-lxml requests`
- Extracts `doc.short_title()` and `doc.summary()` (HTML)
- **Pitfall:** Often returns empty body on JS-heavy or list pages (e.g., HN front page). Prefer trafilatura.

### 4. `websearch "<query>"` → `readpage` — **Deep research**
1. `terminal: websearch "<topic>"` → pick 3–5 best URLs
2. `terminal: readpage <url>` for each
3. Synthesize with sources cited
4. If too large/complex → `terminal: pc "<research task>"` (delegates to Claude Code)

## Agent-Reach Clarification (Critical)
**Agent-Reach does NOT extract web pages.** Its free channels:
- YouTube (subtitles via `yt-dlp`, transcription needs paid Groq key)
- RSS/Atom feeds (via `curl`)
- V2EX
- GitHub (needs `gh` CLI + auth — not installed)

Do NOT call `agent-reach` for web page extraction. Use `readpage` / `trafilatura`.

## Validation Pattern
Always test a new extractor on a known page before trusting it:
```bash
# Quick sanity check
readpage "https://news.ycombinator.com" | head -20
uv run python3 -c "import trafilatura; print(trafilatura.extract(trafilatura.fetch_url('https://news.ycombinator.com'), output_format='markdown')[:200])"
```

## Common Pitfalls
| Situation | What Happens | Fix |
|-----------|--------------|-----|
| Paywall (NYT, WSJ) | Jina returns 403 AbuseAlleviationError | Try trafilatura; if blocked, accept limitation |
| Cloudflare challenge | Both Jina and trafilatura may fail | No free workaround — flag as unextractable |
| JS-rendered content | Static fetch misses data | Use `browse` (Chromium on PC/VPS) for interactive pages |
| Rate 
[... cortado]

### competitive-feature-audit (software-development/competitive-feature-audit)

---
name: competitive-feature-audit
description: Systematically analyze a codebase against competitor products (Uber, Glovo, iFood, etc.) to identify feature gaps, UX inconsistencies, and missing functionality across user roles (client, driver, partner, admin).
category: software-development
---

# Competitive Feature Audit

**Purpose:** Systematically analyze a codebase against competitor products (Uber, Glovo, iFood, etc.) to identify feature gaps, UX inconsistencies, and missing functionality across user roles (client, driver, partner, admin).

## Trigger
- User asks to "compare with Uber/Glovo/iFood" or "what's missing"
- New feature area needs validation against market leaders
- Pre-release audit to ensure competitive parity

## Methodology

### 1. Map Current State (Codebase OR Knowledge Base)
- **Models** → What data structures exist (`DriverModel`, `OrderModel`, etc.)
- **Screens** → What UI flows exist per role (list all `*_screen.dart`)
- **Services** → What business logic exists (`DispatchService`, `PricingService`, etc.)
- **Admin** → What management tools exist (`admin_*_screen.dart`)
- **Database** → Full schema via migrations + `schema.sql`
- **For Bora**: prefer `cortex "<topic>"` over reading raw files when available — Córtex pages are condensed and canonical. Use `cortex INDEX` to discover available pages.

### 1b. Map Market State (Web Research — for gap Analysis)

Two flavors of audit:
- **Codebase-vs-competitor** (original): read Flutter/Supabase source, compare to known competitor feature sets.
- **Market gap analysis** (broader): inventory ALL current verticals from the knowledge base, then research what market leaders (Grab, WeChat, Uber Eats, DoorDash, Instacart, Tata Neu) offer in 2025 via web research. Produces a full feature-gap matrix across the whole product, not just one role's UI.

For the market variant:
1. Read internal knowledge (`cortex`) to inventory what the product already has per vertical.
2. Web research sequence (verified working 2026-08-11):
   - `terminal: websearch "<query>"` first (fast, SearXNG).
   - If `readpage`/Jina fails a specific site (CAPTCHA, 403), fall back to DuckDuckGo: `curl -sL -H "User-Agent: Mozilla/5.0" "https://r.jina.ai/https://duckduckgo.com/html/?q=<query>"` → harvest result links. Jina Reader/Görli block `google.com` domain due to abuse — do NOT use Google search URLs.
   - Read each promising article: `curl -sL -H "User-Agent: Mozilla/5.0" "https://r.jina.ai/<article-url>"` → full markdown.
3. Cross-correlate internal inventory with market feature lists → gap matrix.
4. Classify gaps: **table-stakes** (all leaders have), **differentiators** (leaders pushing), **out-of-scope** (not aligned with product market).
5. Prioritize by impact (Alto/Médio/Baixo) vs. effort (Baixo/Médio/Alto).

### 2. Define Competitor Baseline
For each role, list what market leaders provide:
- **Client app:** Real-time tracking, driver photo/plate/car model, rating, ETA, chat/call, safety features
- **Dr
[... cortado]

### hermes-stt-local (voice/hermes-stt-local)

---
name: hermes-stt-local
description: "Set up, troubleshoot, and verify local STT (faster-whisper) for Hermes Agent on VPS/container environments. Covers free provider configuration, root-owned .venv pitfalls, idempotent re-install guards, and deterministic verification."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, stt, faster-whisper, voice, transcription, vps, container]
    related_skills: [hermes-agent, hermes-voice-guard]
---

# Hermes STT Local (faster-whisper) — Setup, Pitfalls & Verification

**Class of task:** Configuring and maintaining Speech-to-Text with the free `local` provider (faster-whisper) on Hermes Agent running in containers/VPS where the `.venv` is root-owned.

---

## Quick Start (one-shot, idempotent)

```bash
# Run as root (container host or docker exec -u root) to install into root-owned .venv
docker exec -u root hermes-agent-fvnc-hermes-agent-1 sh -c '
  VIRTUAL_ENV=/opt/hermes/.venv /usr/local/bin/uv pip install \
    --python /opt/hermes/.venv/bin/python3 \
    "faster-whisper==1.2.1" "sounddevice==0.5.5" "numpy==2.4.3"
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libportaudio2
  chown -R hermes:hermes /opt/data/.cache
'
```

Then verify inside the container (as `hermes` user):

```bash
/opt/hermes/.venv/bin/python3 -c 'import faster_whisper; print(faster_whisper.__version__)'
/opt/hermes/.venv/bin/python3 <<'PYEOF'
from faster_whisper import WhisperModel
m = WhisperModel("base", device="cpu", compute_type="int8")
segs, info = m.transcribe("audio_027842b1623a.ogg", beam_size=5)
print(info.language, info.language_probability)
print(" ".join(s.text.strip() for s in segs))
PYEOF
```

Expected: `pt 0.988` + transcribed Portuguese text.

---

## Config (config.yaml)

```yaml
stt:
  enabled: true
  provider: local
  local:
    language: pt          # auto-inferred from audio, but explicit avoids fallback
    model: base           # tiny | base | small | medium | large-v3
```

> **Model choice:** `base` (142 MB) is the sweet spot for 1 vCPU / 3.8 GB RAM VPS. `tiny` loses quality; `small`/`medium` over-provision CPU/RAM with no proven gain. Keep `device: cpu`, `compute_type: int8` (Hermes default).

---

## Root Cause: Why It Breaks on Recreate

| Layer | Owner | Problem |
|-------|-------|---------|
| `/opt/hermes/.venv/` | `root:root` (image build) | `hermes` user (UID 10000) cannot `pip install`/`uv pip install` into it — any lazy-install attempt fails silently with `Permission denied` |
| `/opt/data/.cache/huggingface/` | `hermes:hermes` (volume) | Survives recreate — model weights persist |
| `faster-whisper` package | inside `.venv` | **Lost on every container recreate** (layer is ephemeral, not in image, not in volume) |

**Result:** After any `docker compose up -d` that recreates the container, STT is broken until re-installed as root.

---

## Common Pitfalls & Fixes

| Symptom | Root Cause | Fix |
|---------|-----------
[... cortado]


## De fábrica / instaladas (nome, pasta, descrição)

- apple-notes (apple/apple-notes) — Manage Apple Notes via memo CLI: create, search, edit.
- apple-reminders (apple/apple-reminders) — Apple Reminders via remindctl: add, list, complete.
- findmy (apple/findmy) — Track Apple devices/AirTags via FindMy.app on macOS.
- imessage (apple/imessage) — Send and receive iMessages/SMS via the imsg CLI on macOS.
- macos-computer-use (apple/macos-computer-use) — |
- claude-code (autonomous-ai-agents/claude-code) — Delegate coding to Claude Code CLI (features, PRs).
- codex (autonomous-ai-agents/codex) — Delegate coding to OpenAI Codex CLI (features, PRs).
- hermes-agent (autonomous-ai-agents/hermes-agent) — Configure, extend, or contribute to Hermes Agent.
- opencode (autonomous-ai-agents/opencode) — Delegate coding to OpenCode CLI (features, PR review).
- architecture-diagram (creative/architecture-diagram) — Dark-themed SVG architecture/cloud/infra diagrams as HTML.
- ascii-art (creative/ascii-art) — ASCII art: pyfiglet, cowsay, boxes, image-to-ascii.
- ascii-video (creative/ascii-video) — ASCII video: convert video/audio to colored ASCII MP4/GIF.
- baoyu-infographic (creative/baoyu-infographic) — Infographics: 21 layouts x 21 styles (信息图, 可视化).
- claude-design (creative/claude-design) — Design one-off HTML artifacts (landing, deck, prototype).
- comfyui (creative/comfyui) — Generate images, video, and audio with ComfyUI — install, launch, manage nodes/models, run workflows with parameter injection. Uses the official comfy-cli for lifecycle and direct REST/WebSocket API f
- design-md (creative/design-md) — Author/validate/export Google's DESIGN.md token spec files.
- excalidraw (creative/excalidraw) — Hand-drawn Excalidraw JSON diagrams (arch, flow, seq).
- humanizer (creative/humanizer) — Humanize text: strip AI-isms and add real voice.
- manim-video (creative/manim-video) — Manim CE animations: 3Blue1Brown math/algo videos.
- p5js (creative/p5js) — p5.js sketches: gen art, shaders, interactive, 3D.
- popular-web-designs (creative/popular-web-designs) — 54 real design systems (Stripe, Linear, Vercel) as HTML/CSS.
- pretext (creative/pretext) — Use when building creative browser demos with @chenglou/pretext — DOM-free text layout for ASCII art, typographic flow around obstacles, text-as-geometry games, kinetic typography, and text-powered ge
- sketch (creative/sketch) — Throwaway HTML mockups: 2-3 design variants to compare.
- songwriting-and-ai-music (creative/songwriting-and-ai-music) — Songwriting craft and Suno AI music prompts.
- touchdesigner-mcp (creative/touchdesigner-mcp) — Control a running TouchDesigner instance via twozero MCP — create operators, set parameters, wire connections, execute Python, build real-time visuals. 36 native tools.
- jupyter-live-kernel (data-science/jupyter-live-kernel) — Iterative Python via live Jupyter kernel (hamelnb).
- dogfood (dogfood) — Exploratory QA of web apps: find bugs, evidence, reports.
- himalaya (email/himalaya) — Himalaya CLI: IMAP/SMTP email from terminal.
- codebase-inspection (github/codebase-inspection) — Inspect codebases w/ pygount: LOC, languages, ratios.
- github-auth (github/github-auth) — GitHub auth setup: HTTPS tokens, SSH keys, gh CLI login.
- github-code-review (github/github-code-review) — Review PRs: diffs, inline comments via gh or REST.
- github-issues (github/github-issues) — Create, triage, label, assign GitHub issues via gh or REST.
- github-pr-workflow (github/github-pr-workflow) — GitHub PR lifecycle: branch, commit, open, CI, merge.
- github-repo-management (github/github-repo-management) — Clone/create/fork repos; manage remotes, releases.
- diagnosing-bugs (mattpocock/diagnosing-bugs) — Diagnosis loop for hard bugs and performance regressions. Use when the user says \"diagnose\"/\"debug this\", or reports something broken/throwing/failing/slow.
- domain-modeling (mattpocock/domain-modeling) — Build and sharpen a project's domain model. Use when discussing codebase terminology, writing or editing a CONTEXT.md, or recording or editing an ADR.
- git-guardrails-claude-code (mattpocock/git-guardrails-claude-code) — Set up Claude Code hooks to block dangerous git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hoo
- grill-me (mattpocock/grill-me) — A relentless interview to sharpen a plan or design.
- grill-with-docs (mattpocock/grill-with-docs) — A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
- grilling (mattpocock/grilling) — Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
- handoff (mattpocock/handoff) — Compact the current conversation into a handoff document for another agent to pick up.
- improve-codebase-architecture (mattpocock/improve-codebase-architecture) — Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick.
- setup-matt-pocock-skills (mattpocock/setup-matt-pocock-skills) — Configure this repo for the engineering skills: set up its issue tracker, triage label vocabulary, and domain doc layout. Run once before first use of the other engineering skills.
- tdd (mattpocock/tdd) — Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions \"red-green-refactor\", or wants integration tests.
- gif-search (media/gif-search) — Search/download GIFs from Tenor via curl + jq.
- heartmula (media/heartmula) — HeartMuLa: Suno-like song generation from lyrics + tags.
- songsee (media/songsee) — Audio spectrograms/features (mel, chroma, MFCC) via CLI.
- youtube-content (media/youtube-content) — YouTube transcripts to summaries, threads, blogs.
- evaluating-llms-harness (mlops/evaluation/lm-evaluation-harness) — lm-eval-harness: benchmark LLMs (MMLU, GSM8K, etc.).
- weights-and-biases (mlops/evaluation/weights-and-biases) — W&B: log ML experiments, sweeps, model registry, dashboards.
- huggingface-hub (mlops/huggingface-hub) — HuggingFace hf CLI: search/download/upload models, datasets.
- llama-cpp (mlops/inference/llama-cpp) — llama.cpp local GGUF inference + HF Hub model discovery.
- serving-llms-vllm (mlops/inference/vllm) — vLLM: high-throughput LLM serving, OpenAI API, quantization.
- audiocraft-audio-generation (mlops/models/audiocraft) — AudioCraft: MusicGen text-to-music, AudioGen text-to-sound.
- segment-anything-model (mlops/models/segment-anything) — SAM: zero-shot image segmentation via points, boxes, masks.
- obsidian (note-taking/obsidian) — Read, search, create, and edit notes in the Obsidian vault.
- airtable (productivity/airtable) — Airtable REST API via curl. Records CRUD, filters, upserts.
- google-workspace (productivity/google-workspace) — Gmail, Calendar, Drive, Docs, Sheets via gws CLI or Python.
- maps (productivity/maps) — Geocode, POIs, routes, timezones via OpenStreetMap/OSRM.
- nano-pdf (productivity/nano-pdf) — Edit PDF text/typos/titles via nano-pdf CLI (NL prompts).
- notion (productivity/notion) — Notion API + ntn CLI: pages, databases, markdown, Workers.
- ocr-and-documents (productivity/ocr-and-documents) — Extract text from PDFs/scans (pymupdf, marker-pdf).
- powerpoint (productivity/powerpoint) — Create, read, edit .pptx decks, slides, notes, templates.
- teams-meeting-pipeline (productivity/teams-meeting-pipeline) — Operate the Teams meeting summary pipeline via Hermes CLI — summarize meetings, inspect pipeline status, replay jobs, manage Microsoft Graph subscriptions.
- arxiv (research/arxiv) — Search arXiv papers by keyword, author, category, or ID.
- blogwatcher (research/blogwatcher) — Monitor blogs and RSS/Atom feeds via blogwatcher-cli tool.
- llm-wiki (research/llm-wiki) — Karpathy's LLM Wiki: build/query interlinked markdown KB.
- polymarket (research/polymarket) — Query Polymarket: markets, prices, orderbooks, history.
- research-paper-writing (research/research-paper-writing) — Write ML papers for NeurIPS/ICML/ICLR: design→submit.
- openhue (smart-home/openhue) — Control Philips Hue lights, scenes, rooms via OpenHue CLI.
- xurl (social-media/xurl) — X/Twitter via xurl CLI: post, search, DM, media, v2 API.
- hermes-agent-skill-authoring (software-development/hermes-agent-skill-authoring) — Author in-repo SKILL.md: frontmatter, validator, structure, and writing-quality principles.
- node-inspect-debugger (software-development/node-inspect-debugger) — Debug Node.js via --inspect + Chrome DevTools Protocol CLI.
- plan (software-development/plan) — Plan mode: write an actionable markdown plan to .hermes/plans/, no execution. Bite-sized tasks, exact paths, complete code.
- python-debugpy (software-development/python-debugpy) — Debug Python: pdb REPL + debugpy remote (DAP).
- requesting-code-review (software-development/requesting-code-review) — Pre-commit review: security scan, quality gates, auto-fix.
- simplify-code (software-development/simplify-code) — Parallel 3-agent cleanup of recent code changes.
- spike (software-development/spike) — Throwaway experiments to validate an idea before build.
- systematic-debugging (software-development/systematic-debugging) — 4-phase root cause debugging: understand bugs before fixing.
- test-driven-development (software-development/test-driven-development) — TDD: enforce RED-GREEN-REFACTOR, tests before code.
- yuanbao (yuanbao) — Yuanbao (元宝) groups: @mention users, query info/members.

