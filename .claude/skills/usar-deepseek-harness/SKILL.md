---
name: usar-deepseek-harness
description: "Como usar o DeepSeek Harness (dsh) no PC do Danilo: lançar uma tarefa ou uma conversa, que motor grátis usa e os seus limites, a frase que liga o motor pago, o que o dsh sabe do Claude Code (CLAUDE.md, skills, livro, Córtex), o que ele NÃO pode fazer e como se atualiza. Usar sempre que o Danilo falar em dsh, harness, Dipsy ou pedir uma tarefa para o motor grátis."
---

# Usar o DeepSeek Harness (dsh)

O dsh é um segundo "Claude Code" do PC, feito pela DeepSeek (MIT, versão de pré-lançamento: pode partir
compatibilidade). Serve para o Danilo mandar uma tarefa ao dsh em vez de ao Claude Code e sair trabalho parecido,
com um motor GRÁTIS. Instalado a 29-30/10/2026 (missão `dsh-harness-2026-10-29`), versão 0.2.1-rc.5.

## Como lançar
- **Tarefa sem conversa:** escrever a tarefa em `Desktop\Bora\prompt-dsh.md` e abrir `DSH-MISSAO.cmd`
  (parâmetro opcional: `bora_app`, `BoraStudio`, `jai-site` ou `bora-site`; sem parâmetro = `bora_app`).
  A resposta aparece na janela e fica em `Desktop\Bora\dsh-saidas\AAAA-MM-DD_HHMM.md`.
- **Conversar:** abrir `DSH-ABRIR.cmd` e usar `http://127.0.0.1:3080` (só neste PC).
- **À mão (PowerShell):** primeiro `[Environment]::SetEnvironmentVariable('KILO_ANON_KEY', (Get-Content "$HOME\.dsh\kilo-anonima.txt" -Raw).Trim(), 'Process')`,
  depois `dsh --profile headless "tarefa"`. Os lançadores já fazem isto sozinhos.
- Tudo vive em `~/.dsh` (fora do repo): `cordis.patch.yml` (motores e MCP), `secrets/` (tokens, só o utilizador lê),
  `skills-ponte/` (pontes das skills que o dsh recusa), `AGENTS.md` (é o MESMO ficheiro que o CLAUDE.md global: um
  hardlink, editar um muda os dois).

## Motor (o que é grátis e os limites)
- Padrão: **Nemotron 3 Ultra** pela piscina grátis da **Kilo** (sem conta). Reserva 1: `kilo-auto/free`. Reserva 2:
  **Gemini grátis** (chave do juiz, sem faturação: 20 pedidos por dia e por modelo). O lançador tenta por esta ordem.
- ⚠️ **A Kilo pode guardar os pedidos.** Nunca meter segredos, chaves, dados de clientes nem conversas pessoais.
- O Gemini grátis também pode usar os pedidos para treinar. Mesma regra.
- Se aparecer erro 429, é abuso de quota: esperar. Erro 403: região recusada.
- O plugin comunitário `dsh-our-free-model` NÃO foi instalado (copia cabeçalhos do OpenCode, tem login de contas e
  atualizador próprio). A Kilo e o Gemini foram ligados à mão no `cordis.patch.yml`.

## Motor pago (preparado, sem chave)
O cartão "DeepSeek" existe nas definições, mas SEM chave e sem pagar nada. Só se liga quando o Danilo disser
**"autorizo carregar 5 € na DeepSeek"**. Até lá: grátis.

## O que o dsh sabe (igual ao Claude Code)
| O Claude Code tem | O dsh tem | Como se usa |
|---|---|---|
| CLAUDE.md global e do repo | `~/.dsh/AGENTS.md` (hardlink do global) + `AGENTS.md`/`CLAUDE.md` do repo | automático ao arrancar na pasta |
| Linhas `@ficheiro` do CLAUDE.md | NÃO as segue; `~/.agents/AGENTS.md` manda ler `erros.md`, `regras.md` e o AGENTS do repo | automático |
| ~150 skills | 146 visíveis ao modelo (+5 escondidas por `disable-model-invocation`) | o dsh carrega-as pelo nome |
| Skills que o dsh recusa (YAML estrito) | 9 pontes em `~/.dsh/skills-ponte` | idem |
| 42 agentes | skill `agentes-claude-code` (lista + como os usar como subagentes) | pedir "usa o agente X" |
| Córtex (MCP) | MCP `cortex` com token estático | `cortex_buscar`, `cortex_ler` |
| Supabase (conector) | MCP `supabase` **só leitura** | precisa do token novo (ver "Falta") |
| Nano Banana (MCP) | MCP `nano-banana` | chave grátis, quase sem imagens |
| REA (engenharia reversa) | pela shell (`npx rea-agents`), não como MCP (≈300 ferramentas) | só no NOSSO APK e sites |
| Hooks e tranca `bora-tranca` | **NÃO tem** | por isso o dsh só lê a base |

## Regras que nunca se quebram
1. **Nunca** apontar o Claude Code para o dsh como proxy/router (regra de 13/09 e termos da Anthropic de 04/04/2026).
2. **Nunca** meter contas Claude, ChatGPT/Codex, Gemini por cookie nem OpenCode por login no dsh.
3. Dinheiro, dispatch, carteira, RLS, push e publicação **nunca** se delegam ao dsh. Escrever na base é do Claude Code.
4. Engenharia reversa **só** no nosso APK (`pt.boraapp.bora`) e nos nossos sites; apps de terceiros só para comparar
   o que o utilizador vê (regra do Danilo de 13/10).
5. Sem app desktop do Harness (os Electron/Tauri comunitários não são assinados). Só `dsh` por npm.
6. Não ligar o encaminhamento local (portas 18899/18900) nem relé de rede.

## Segurança, sem fingir
- O dsh **lê qualquer ficheiro** do utilizador: não tem forma de negar leitura por padrão de nome (o fence só trava
  escrita). A regra "não ler `.env*`, `*.pem`, `~/.claude.json`…" está só escrita nas instruções, não é uma tranca.
- Por isso: modelos pagos sem chave, Supabase em só leitura, tokens em `~/.dsh/secrets` só com permissão do utilizador.
- O dsh envia telemetria de feedback para `dsh-otel-collector.deepseeksvc.com` só no modo `FEEDBACK_ONLY` (padrão).

## Atualizar
```bash
npm i -g @deepseek-ai/dsh@latest
```
Depois correr `DSH-MISSAO.cmd` com uma tarefa pequena para provar que continua a responder.

## Falta (ver o relatório da missão)
Token novo do Supabase (um clique no `COLAR-TOKEN-SUPABASE.cmd`), Gmail/Drive/Calendar das duas contas (OAuth),
e os plugins dos adendos C1–C10 (ver lista no relatório).
